from pathlib import Path
import struct
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from native_section_input import HEADER,VERTEX,decode_section,decode_atlas,opaque_support
from native_section_partition import partition

def triangle(color=0xffffffff,flags=1,u=.05):
    return [(0.,0.,0.,u,.05,color,0x0f0f,flags),(1.,0.,0.,u+.15,.05,color,0x0f0f,flags),(0.,1.,0.,u,.2,color,0x0f0f,flags)]
def section(v):return HEADER.pack(1,2,3,len(v))+b''.join(VERTEX.pack(*r)for r in v)
def atlas():return struct.pack('<II',16,16)+bytes([120,140,160,255])*256
class PartitionTests(unittest.TestCase):
    def test_partial(self):
        s,a,mask,why=partition(section(triangle(0xff808080)+triangle(flags=2)+triangle(0xff102030)),atlas(),[])
        self.assertEqual(mask,'01');self.assertEqual(why,{'blend':1,'tint_or_alpha':1})
        v=decode_section(s);self.assertEqual(len(v.vertices),3);self.assertTrue(all(x[5]==0xffffffff for x in v.vertices))
        opaque_support(v,*decode_atlas(a));self.assertEqual(v.origin,(16,32,48))
    def test_animation_and_alpha(self):
        s,a,mask,why=partition(section(triangle()+triangle(u=.55)),atlas(),[[0,0,4,4]])
        self.assertEqual(mask,'02');self.assertEqual(why,{'animated':1})
        raw=bytearray(atlas());raw[8+3]=0
        s,a,mask,why=partition(section(triangle()),raw,[])
        self.assertIsNone(s);self.assertEqual(mask,'00');self.assertEqual(why,{'texture_alpha':1})
    def test_gutters_and_positions(self):
        raw=section(triangle());s,a,mask,why=partition(raw,atlas(),[])
        original=decode_section(raw);new=decode_section(s)
        self.assertEqual([v[:3]for v in original.vertices],[v[:3]for v in new.vertices])
        w,h,pixels=decode_atlas(a)
        for v in new.vertices:
            x,y=int(v[3]*w),int(v[4]*h)
            self.assertEqual(pixels[(y*w+x)*4:(y*w+x)*4+4],bytes([120,140,160,255]))
    def test_malformed(self):
        with self.assertRaises(ValueError):partition(section(triangle())[:-1],atlas(),[])
        with self.assertRaises(AssertionError):partition(section(triangle()),atlas(),[[10,0,16,16]])
    def test_non_neutral_transparent_vertices_remain(self):
        s,a,mask,why=partition(section(triangle(0x80ffffff)),atlas(),[])
        self.assertIsNone(s);self.assertEqual(why,{'tint_or_alpha':1})
if __name__=='__main__':unittest.main()
