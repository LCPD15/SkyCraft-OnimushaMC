import struct
import unittest
from native_model_input import convert_model
from native_section_input import HEADER, VERTEX, decode_section, decode_atlas

def face(color=0xffffffff,flags=1):
    return HEADER.pack(0,0,0,6)+b''.join(VERTEX.pack(x,y,0,x,y,color,0,flags) for x,y in [(0,0),(1,0),(1,1),(0,0),(1,1),(0,1)])
def atlas(w=4,h=4,alpha=None,rgb=(100,200,80)):
    return struct.pack('<II',w,h)+b''.join(bytes((*rgb,alpha(x,y) if alpha else 255)) for y in range(h) for x in range(w))
def area(s):
    v=decode_section(s).vertices
    return sum(abs((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/2 for a,b,c in zip(v[::3],v[1::3],v[2::3]))

class Models(unittest.TestCase):
    def test_opaque_keeps_shape(self):
        s,a,r=convert_model(face(),atlas(),[])
        self.assertEqual(area(s),1);self.assertEqual(r['triangles'],2)
    def test_ladder_holes_are_geometry(self):
        s,a,r=convert_model(face(),atlas(alpha=lambda x,y:0 if x in (1,2) and y in (1,2) else 255),[])
        self.assertAlmostEqual(area(s),.75)
        self.assertTrue(all(c==255 for c in decode_atlas(a)[2][3::4]))
    def test_uniform_tint_baked_once(self):
        s,a,r=convert_model(face(0xff80ffff),atlas(),[])
        self.assertIn(bytes((100,200,40,255)),decode_atlas(a)[2])
        self.assertTrue(all(v[5]==0xffffffff for v in decode_section(s).vertices))
    def test_no_partial_conversion(self):
        for raw,tex,ani in [(face(flags=2),atlas(),[]),(face(),atlas(),[[0,0,2,2]]),(face(),atlas(alpha=lambda x,y:0),[])]:
            with self.assertRaises(ValueError):convert_model(raw,tex,ani)
    def test_cutout_alpha_threshold(self):
        s,_,_=convert_model(face(),atlas(alpha=lambda x,y:127 if x<2 else 128),[])
        self.assertAlmostEqual(area(s),.5)
    def test_deterministic_reuse(self):
        self.assertEqual(convert_model(face(),atlas(),[]),convert_model(face(),atlas(),[]))
    def test_pixel_boundaries_and_half_uv_sampler(self):
        # Every original texel has a unique colour. Interpolate the final half
        # UVs as the RE mesh does, then check the 4x atlas's bilinear footprint.
        colors=[bytes((x*43,y*37,(x+y)*21,255)) for y in range(4) for x in range(4)]
        s,a,details=convert_model(face(),struct.pack('<II',4,4)+b''.join(colors),[])
        self.assertAlmostEqual(area(s),1)
        w,h,pixels=decode_atlas(a);verts=decode_section(s).vertices
        import math
        half=lambda n:struct.unpack('<e',struct.pack('<e',n))[0]
        for i in range(0,len(verts),3):
            tri=verts[i:i+3]
            cx=sum(v[0] for v in tri)/3;cy=sum(v[1] for v in tri)/3
            expected=colors[min(3,int(cy*4))*4+min(3,int(cx*4))]
            for v in tri:
                # The real atlas repeats each texel into 4x4 identical pixels.
                px=half(v[3])*w*4-.5;py=half(v[4])*h*4-.5
                for yy in (math.floor(py),math.floor(py)+1):
                    for xx in (math.floor(px),math.floor(px)+1):
                        sample=((yy//4)*w+xx//4)*4
                        self.assertEqual(pixels[sample:sample+4],expected)
        self.assertTrue(details['pixel_edges'])
    def test_white_flash_keeps_mesh_and_cutout_shape(self):
        raw=atlas(alpha=lambda x,y:0 if x==1 else 255)
        base,tex,_=convert_model(face(),raw,[])
        flash,white,_=convert_model(face(),raw,[],white_flash=True)
        self.assertEqual(base,flash)
        self.assertAlmostEqual(area(flash),.75)
        self.assertIn(bytes((216,241,211,255)),decode_atlas(white)[2])
        self.assertNotEqual(tex,white)

if __name__=='__main__': unittest.main()
