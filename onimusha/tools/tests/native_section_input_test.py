import math
from pathlib import Path
import struct
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native_section_input import decode_section, decode_atlas, opaque_support, triangle_frame, HEADER, VERTEX


class NativeSectionInputTest(unittest.TestCase):
    def setUp(self):
        self.vertices = [(0., 0., 1., 0., 0., 0xffffffff, 0x0f00, 1),
                         (1., 0., 1., 1., 0., 0xffffffff, 0x0f00, 1),
                         (0., 1., 1., 0., 1., 0xffffffff, 0x0f00, 1)]
    def encoded(self):
        return HEADER.pack(-3, 4, 5, 3) + b''.join(VERTEX.pack(*v) for v in self.vertices)
    def test_xyz_and_top_first_uv_are_preserved(self):
        s = decode_section(self.encoded())
        self.assertEqual(s.origin, (-48, 64, 80))
        self.assertEqual(s.vertices[2][3:5], (0., 1.))
        normal, tangent, sign = triangle_frame(s.vertices)
        self.assertEqual(normal, (0., 0., 1.))
        self.assertEqual(tangent, (1., 0., 0.))
        self.assertEqual(sign, 1)
    def test_mirrored_uv_changes_tangent_sign(self):
        self.vertices = [(*v[:3], 1-v[3], v[4], *v[5:]) for v in self.vertices]
        n, t, sign = triangle_frame(decode_section(self.encoded()).vertices)
        self.assertEqual(n, (0., 0., 1.))
        self.assertEqual(t, (-1., 0., 0.))
        self.assertEqual(sign, -1)
    def test_invalid_section_data_rejected(self):
        valid = self.encoded()
        for data in [b'', valid[:-1], valid+b'\0', HEADER.pack(0,0,0,0), HEADER.pack(0,0,0,3_000_000)]:
            with self.subTest(data_len=len(data)), self.assertRaises(ValueError): decode_section(data)
        for index, value in [(0, math.nan), (2, 40.), (3, 1.1), (5, 0xff808080), (6, 0x10), (7, 2), (7, 0x71)]:
            saved = self.vertices[0]
            v = list(saved); v[index] = value; self.vertices[0] = v
            with self.subTest(index=index, value=value), self.assertRaises(ValueError): decode_section(self.encoded())
            self.vertices[0] = saved
    def test_opaque_footprint_and_atlas_bounds(self):
        opaque = bytes([100,120,130,255])*16
        w,h,rgba = decode_atlas(struct.pack('<II',4,4)+opaque)
        s = decode_section(self.encoded())
        opaque_support(s,w,h,rgba)
        alpha = bytearray(rgba); alpha[3] = 0
        with self.assertRaises(ValueError): opaque_support(s,w,h,alpha)
        for data in [b'', struct.pack('<II',8192,8192), struct.pack('<II',4,4)+rgba[:-1]]:
            with self.assertRaises(ValueError): decode_atlas(data)
    def test_degenerate_geometry_and_uv_rejected(self):
        with self.assertRaises(ValueError): triangle_frame([self.vertices[0]]*3)
        bad = [(*v[:3], 0., 0., *v[5:]) for v in self.vertices]
        with self.assertRaises(ValueError): triangle_frame(bad)


if __name__ == '__main__': unittest.main()
