"""Real capture partition: opaque static untinted triangles -> compact padded atlas.

Neutral MC ambient-occlusion vertex multipliers are removed so native lighting owns
shading. Colored tint, alpha, animations and degenerate triangles stay in MC overlay.
No model/world edits. Standard library only, independently testable without Blender.
"""
import math
import struct
from collections import Counter
from native_section_input import decode_section, decode_atlas, HEADER, VERTEX, triangle_frame


def partition(section_data, atlas_data, animated):
    source = decode_section(section_data, strict=False)
    w, h, rgba = decode_atlas(atlas_data)
    assert len(animated) <= 512
    for r in animated:
        assert len(r) == 4 and all(isinstance(n, int) and n >= 0 for n in r)
        assert r[0]+r[2] <= w and r[1]+r[3] <= h
    def overlap(a, b):
        x,y,c,d = a; X,Y,C,D = b
        return x < X+C and X < x+c and y < Y+D and Y < y+d
    sprites, accepted, skipped = {}, [], Counter()
    mask = bytearray((len(source.vertices)//3+7)//8)
    scan_budget = 0
    for i in range(0,len(source.vertices),3):
        tri = source.vertices[i:i+3]
        if any(v[7]&2 for v in tri): skipped['blend']+=1; continue
        colors = [(v[5]&255,(v[5]>>8)&255,(v[5]>>16)&255,v[5]>>24) for v in tri]
        if any(c[3]!=255 or c[0]!=c[1] or c[1]!=c[2] for c in colors): skipped['tint_or_alpha']+=1; continue
        try: triangle_frame(tri)
        except ValueError: skipped['degenerate']+=1; continue
        x = max(0,int(math.floor(min(v[3] for v in tri)*w+.001)))
        y = max(0,int(math.floor(min(v[4] for v in tri)*h+.001)))
        right = min(w,int(math.ceil(max(v[3] for v in tri)*w-.001)))
        bottom = min(h,int(math.ceil(max(v[4] for v in tri)*h-.001)))
        rect = (x,y,right-x,bottom-y)
        if min(rect[2:])<1 or max(rect[2:])>256: skipped['large_uv']+=1; continue
        if any(overlap(rect,r) for r in animated): skipped['animated']+=1; continue
        if rect not in sprites:
            scan_budget += rect[2]*rect[3]
            if scan_budget>4_194_304: raise ValueError('UV scan budget exceeded')
            opaque = all(rgba[(yy*w+xx)*4+3]==255 for yy in range(y,bottom) for xx in range(x,right))
            sprites[rect] = {'opaque':opaque}
        if not sprites[rect]['opaque']: skipped['texture_alpha']+=1; continue
        accepted.append((i,rect))
    if not accepted:
        return None, None, mask.hex(), dict(skipped)
    used = sorted({r for _,r in accepted},key=lambda r:(-r[3],-r[2],r))
    # Padded shelves. Four output texels per source pixel keeps nearest-looking MC texture.
    edge = 32
    while True:
        px=py=row=0; placements={};fits=True
        for r in used:
            cw,ch=r[2]+4,r[3]+4
            if cw>edge: fits=False;break
            if px+cw>edge: px=0;py+=row;row=0
            if py+ch>edge: fits=False;break
            placements[r]=(px+2,py+2);px+=cw;row=max(row,ch)
        if fits:break
        edge*=2
        if edge>1024:raise ValueError('Compact atlas budget exceeded')
    pixels=bytearray([255])*(edge*edge*4)
    for r,(tx,ty) in placements.items():
        x,y,cw,ch=r
        for yy in range(-2,ch+2):
            sy=y+max(0,min(ch-1,yy))
            for xx in range(-2,cw+2):
                sx=x+max(0,min(cw-1,xx));si=(sy*w+sx)*4;di=((ty+yy)*edge+tx+xx)*4
                pixels[di:di+4]=rgba[si:si+4]
    vertices=[]
    for i,r in accepted:
        tx,ty=placements[r]
        for v in source.vertices[i:i+3]:
            vertices.append((*v[:3],(v[3]*w-r[0]+tx)/edge,(v[4]*h-r[1]+ty)/edge,0xffffffff,v[6],v[7]))
        ti=i//3;mask[ti//8]|=1<<(ti%8)
    section=HEADER.pack(*source.key,len(vertices))+b''.join(VERTEX.pack(*v) for v in vertices)
    atlas=struct.pack('<II',edge,edge)+pixels
    return section,atlas,mask.hex(),dict(skipped)
