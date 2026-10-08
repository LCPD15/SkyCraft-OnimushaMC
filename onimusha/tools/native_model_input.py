"""Complete baked block appearance -> opaque RE triangles and a tinted compact atlas.

Cutout texels become geometry holes, not an opaque rectangle. No block-name table.
Animated, blended, gradient-colored and oversized models fail as a whole and stay MC.
"""
import math
import struct
from native_section_input import decode_section, decode_atlas, HEADER, VERTEX, triangle_frame


def clip(poly, axis, bound, greater):
    out = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        va, vb = a[axis] - bound, b[axis] - bound
        ia, ib = (va >= -1e-8, vb >= -1e-8) if greater else (va <= 1e-8, vb <= 1e-8)
        if ia: out.append(a)
        if ia != ib:
            t = va / (va-vb)
            out.append(tuple(x + t*(y-x) for x, y in zip(a, b)))
    return out


def opaque_rectangles(w, h, rgba, rect, pixel_edges=False):
    x,y,cw,ch = rect
    active, done = {}, []
    for yy in range(ch):
        runs = []; start = None; color = None
        for xx in range(cw+1):
            pos=((y+yy)*w+x+xx)*4
            opaque = xx<cw and rgba[pos+3] >= 128
            current=bytes(rgba[pos:pos+3]) if opaque and pixel_edges else None
            if start is not None and (not opaque or current!=color):
                runs.append((start,xx,color));start=None
            if opaque and start is None: start = xx;color=current
        next_active={}
        for run in runs:
            top = active.pop(run, yy)
            next_active[run] = top
        for (a,b,_),top in active.items(): done.append((x+a,y+top,b-a,yy-top))
        active=next_active
    for (a,b,_),top in active.items(): done.append((x+a,y+top,b-a,ch-top))
    return done


def convert_model(section_data, atlas_data, animated, *, pixel_edges=True, white_flash=False):
    source=decode_section(section_data,strict=False)
    w,h,rgba=decode_atlas(atlas_data)
    if len(animated)>512: raise ValueError('Animation metadata overflow')
    for r in animated:
        if len(r)!=4 or any(type(v) is not int or v<0 for v in r) or r[0]+r[2]>w or r[1]+r[3]>h:
            raise ValueError('Invalid animation rectangle')
    triangles=[];patches={};work=0
    for i in range(0,len(source.vertices),3):
        tri=source.vertices[i:i+3]
        if any(v[7]&2 for v in tri): raise ValueError('translucent_model')
        colors={v[5] for v in tri}
        if len(colors)!=1 or next(iter(colors))>>24!=255: raise ValueError('gradient_vertex_color')
        tint=next(iter(colors));triangle_frame(tri)
        x=max(0,math.floor(min(v[3] for v in tri)*w+.001))
        y=max(0,math.floor(min(v[4] for v in tri)*h+.001))
        r=min(w,math.ceil(max(v[3] for v in tri)*w-.001))
        b=min(h,math.ceil(max(v[4] for v in tri)*h-.001))
        rect=(x,y,r-x,b-y)
        if min(rect[2:])<1 or max(rect[2:])>256: raise ValueError('model_uv_budget')
        if any(x<a+c and a<r and y<d+e and d<b for a,d,c,e in animated): raise ValueError('animated_model')
        patch=(*rect,tint)
        if patch not in patches:
            work+=rect[2]*rect[3]
            if work>1_048_576: raise ValueError('model_pixel_budget')
            patches[patch]=opaque_rectangles(w,h,rgba,rect,pixel_edges)
        # Clip in original atlas pixel coordinates. XYZ interpolates along UV edges.
        poly=[(*v[:3],v[3]*w,v[4]*h) for v in tri]
        for a,d,c,e in patches[patch]:
            clipped=clip(clip(clip(clip(poly,3,a,True),3,a+c,False),4,d,True),4,d+e,False)
            for j in range(1,len(clipped)-1):
                t=(clipped[0],clipped[j],clipped[j+1])
                try: triangle_frame(t)
                except ValueError: continue
                triangles.append((t,patch,(a,d,c,e)))
                if len(triangles)>65536: raise ValueError('cutout_triangle_budget')
    if not triangles: raise ValueError('fully_transparent_model')
    # Fixed deterministic shelf packing. Pad every texture by two source texels.
    used=sorted({p for _,p,_ in triangles},key=lambda p:(-p[3],-p[2],p))
    edge=32
    while True:
        px=py=row=0;placements={};fits=True
        for p in used:
            cw,ch=p[2]+4,p[3]+4
            if cw>edge: fits=False;break
            if px+cw>edge: px=0;py+=row;row=0
            if py+ch>edge: fits=False;break
            placements[p]=(px+2,py+2);px+=cw;row=max(row,ch)
        if fits: break
        edge*=2
        if edge>1024: raise ValueError('compact_atlas_budget')
    pixels=bytearray([255])*(edge*edge*4)
    for p,(tx,ty) in placements.items():
        x,y,cw,ch,tint=p;rgb=(tint&255,(tint>>8)&255,(tint>>16)&255)
        for yy in range(-2,ch+2):
            sy=y+max(0,min(ch-1,yy))
            for xx in range(-2,cw+2):
                sx=x+max(0,min(cw-1,xx));si=(sy*w+sx)*4;di=((ty+yy)*edge+tx+xx)*4
                color=[round(rgba[si+j]*rgb[j]/255) for j in range(3)]
                if white_flash:color=[round(v*.25+255*.75) for v in color]
                pixels[di:di+4]=bytes(color+[255])
    vertices=[];discarded_slivers=0
    for tri,p,region in triangles:
        tx,ty=placements[p]
        # Clipping near a texel corner can leave a zero-area sliver after the
        # final float32 UV conversion. Validate the actual serialized values.
        # Each region has one exact RGB value. Contract its UV footprint into
        # its interior, so the game's linear/aniso sampler cannot mix a different
        # pixel across the boundary. Geometry keeps the original pixel boundary;
        # no global game sampler change, per-frame conversion or new GameObjects.
        cx,cy=region[0]+region[2]*.5,region[1]+region[3]*.5
        def uv(v):
            u,vv=v[3],v[4]
            if pixel_edges:u,vv=cx+(u-cx)*.2,cy+(vv-cy)*.2
            return (u-p[0]+tx)/edge,(vv-p[1]+ty)/edge
        packed=[VERTEX.unpack(VERTEX.pack(*v[:3],*uv(v),0xffffffff,0,1)) for v in tri]
        try: triangle_frame(packed)
        except ValueError:
            discarded_slivers+=1;continue
        vertices.extend(packed)
    if not vertices: raise ValueError('fully_degenerate_model')
    return (HEADER.pack(0,0,0,len(vertices))+b''.join(VERTEX.pack(*v) for v in vertices),
            struct.pack('<II',edge,edge)+pixels,
            dict(source_triangles=len(source.vertices)//3,triangles=len(vertices)//3,patches=len(used),discarded_slivers=discarded_slivers,
                 pixel_edges=pixel_edges,white_flash=white_flash))
