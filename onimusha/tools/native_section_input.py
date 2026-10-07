"""Bounded offline reader for protocol-13 REN_SECTION / REN_ATLAS payloads.

The first native material prototype accepts opaque, untinted geometry only.
Unsupported inputs must remain in the overlay; this tool never changes runtime
visibility or claims that a file-backed mesh is a dynamic RE mesh upload API.
"""
from dataclasses import dataclass
import math
import struct

HEADER = struct.Struct('<iiiI')
VERTEX = struct.Struct('<5f3I')
MAX_VERTICES = 196608
MAX_ATLAS_BYTES = 32 * 1024 * 1024


@dataclass(frozen=True)
class Section:
    key: tuple
    vertices: tuple

    @property
    def origin(self):
        return tuple(c * 16 for c in self.key)


def decode_section(data):
    if len(data) < HEADER.size:
        raise ValueError('Missing section header')
    x, y, z, count = HEADER.unpack_from(data)
    if max(abs(x), abs(y), abs(z)) > 1_000_000:
        raise ValueError('Section coordinate out of bounds')
    if not count or count > MAX_VERTICES or count % 3:
        raise ValueError('Expected a bounded, nonempty triangle list')
    if len(data) != HEADER.size + count * VERTEX.size:
        raise ValueError('Section payload length mismatch')
    vertices = tuple(VERTEX.iter_unpack(data[HEADER.size:]))
    for v in vertices:
        if not all(math.isfinite(a) for a in v[:5]):
            raise ValueError('Non-finite vertex')
        if any(a < -16 or a > 32 for a in v[:3]):
            raise ValueError('Vertex outside bounded section-local range')
        if any(a < 0 or a > 1 for a in v[3:5]):
            raise ValueError('UV outside atlas')
        if v[5] != 0xffffffff:
            raise ValueError('Tint / AO / vertex alpha needs a separately verified native material')
        if v[7] & ~0x71 or (v[7] >> 4) > 6:
            raise ValueError('Blended or unknown vertex flags')
        if (v[6] & ~0x0f0f):
            raise ValueError('Invalid MC light encoding')
    return Section((x, y, z), vertices)


def decode_atlas(data):
    if len(data) < 8:
        raise ValueError('Missing atlas header')
    w, h = struct.unpack_from('<II', data)
    if not w or not h or max(w, h) > 8192 or w*h*4 > MAX_ATLAS_BYTES:
        raise ValueError('Atlas dimensions out of bounds')
    if len(data) != 8 + w*h*4:
        raise ValueError('Atlas payload length mismatch')
    return w, h, data[8:]


def opaque_support(section, width, height, rgba):
    """Conservative rectangle check including bilinear footprint and half-UV error.

    Alpha-bearing sprites are rejected, not made opaque. A production atlas needs
    mip gutters and a certified alpha material; this offline prototype has no
    mipmaps and reports that limitation in its output manifest.
    """
    if all(a == 255 for a in rgba[3::4]):
        return
    work = 0
    for i in range(0, len(section.vertices), 3):
        triangle = section.vertices[i:i+3]
        uv = [v[3:5] for v in triangle]
        x0 = max(0, math.floor(min(p[0] for p in uv)*width - .5) - 1)
        x1 = min(width-1, math.ceil(max(p[0] for p in uv)*width - .5) + 1)
        y0 = max(0, math.floor(min(p[1] for p in uv)*height - .5) - 1)
        y1 = min(height-1, math.ceil(max(p[1] for p in uv)*height - .5) + 1)
        # Avoid unbounded per-triangle scans on large UV spans.
        if (x1-x0+1)*(y1-y0+1) > 262144:
            raise ValueError('UV footprint too large for offline opaque check')
        work += (x1-x0+1)*(y1-y0+1)
        if work > 16_777_216:
            raise ValueError('Opaque footprint scan budget exceeded')
        for y in range(y0, y1+1):
            if any(rgba[(y*width+x)*4+3] != 255 for x in range(x0, x1+1)):
                raise ValueError('Alpha-bearing footprint needs cutout / blended material')


def triangle_frame(tri):
    def sub(a, b): return tuple(x-y for x, y in zip(a, b))
    def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    def dot(a, b): return sum(x*y for x, y in zip(a, b))
    def unit(a):
        length = math.sqrt(dot(a, a))
        if length < 1e-10: raise ValueError('Degenerate triangle or tangent')
        return tuple(x/length for x in a)
    e1, e2 = sub(tri[1][:3], tri[0][:3]), sub(tri[2][:3], tri[0][:3])
    normal = unit(cross(e1, e2))
    # Tangent handedness is calculated in the serialized top-row-first UV basis.
    du1, dv1 = sub(tri[1][3:5], tri[0][3:5])
    du2, dv2 = sub(tri[2][3:5], tri[0][3:5])
    det = du1*dv2-du2*dv1
    if abs(det) < 1e-12: raise ValueError('Degenerate UV triangle')
    tangent = unit(tuple((a*dv2-b*dv1)/det for a, b in zip(e1, e2)))
    bitangent = tuple((b*du1-a*du2)/det for a, b in zip(e1, e2))
    sign = 1 if dot(cross(normal, tangent), bitangent) >= 0 else -1
    return normal, tangent, sign
