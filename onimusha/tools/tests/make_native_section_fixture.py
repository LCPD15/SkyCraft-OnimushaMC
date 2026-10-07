"""Generate clearly labeled synthetic protocol payloads, never a real MC capture."""
from pathlib import Path
import argparse
import json
import struct
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from native_section_input import HEADER, VERTEX

def generate(output, dense=False, minecraft_jar=None):
    output.mkdir(parents=True,exist_ok=False)
    # Asymmetric, colored atlas makes axes / UV orientation distinguishable.
    w,h = 64,32
    pixels = bytearray()
    for y in range(h):
        for x in range(w):
            if x < 32:
                color = (240 if x<16 else 50,220 if y<16 else 40,70)
            else:
                color = (40,110 if y<16 else 230,230 if (x//4+y//4)%2 else 80)
            pixels.extend((*color,255))
    textures = []
    if minecraft_jar:
        # Optional Blender-only texture source. Geometry remains a synthetic fixture.
        import bpy
        import numpy as np
        import zipfile
        import hashlib
        tiles=[]
        with zipfile.ZipFile(minecraft_jar) as jar:
            for name in ('stone','iron_block'):
                entry='assets/minecraft/textures/block/'+name+'.png'
                raw=jar.read(entry); path=output/(name+'.png');path.write_bytes(raw)
                img=bpy.data.images.load(str(path),check_existing=False)
                img.colorspace_settings.name='Non-Color'
                assert tuple(img.size)==(16,16)
                tile=np.rint(np.asarray(img.pixels[:]).reshape(16,16,4)*255).astype(np.uint8)
                tiles.append(np.repeat(np.repeat(tile[::-1],2,axis=0),2,axis=1))
                textures.append({'entry':entry,'sha256':hashlib.sha256(raw).hexdigest()})
        pixels=np.concatenate(tiles,axis=1).tobytes()
    (output/'atlas.bin').write_bytes(struct.pack('<II',w,h)+pixels)
    cells = {(1,2,3),(2,2,3),(1,3,3),(2,3,3),(2,2,4)}
    if dense:
        cells = {(x,y,z) for x in range(16) for y in range(16) for z in range(16) if (x+y+z)%2==0}
    # Ordinal, outward normal, U, V. U cross V == normal.
    faces = [(0,(0,-1,0),(1,0,0),(0,0,1)),(1,(0,1,0),(1,0,0),(0,0,-1)),
             (2,(0,0,-1),(-1,0,0),(0,1,0)),(3,(0,0,1),(1,0,0),(0,1,0)),
             (4,(-1,0,0),(0,0,1),(0,1,0)),(5,(1,0,0),(0,0,-1),(0,1,0))]
    vertices=[]
    for p in sorted(cells):
        tile=(sum(p)%2)*.5
        for ordinal,n,u,v in faces:
            if tuple(p[i]+n[i] for i in range(3)) in cells: continue
            quad=[]
            for s,t in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]:
                xyz=tuple(p[i]+.5+n[i]*.5+u[i]*s+v[i]*t for i in range(3))
                uv=(tile+1/64+(s+.5)*(0.5-2/64),1/32+(t+.5)*(1-2/32))
                quad.append((*xyz,*uv,0xffffffff,0x0f00,1|((ordinal+1)<<4)))
            vertices.extend(quad[k] for k in (0,1,2,0,2,3))
    (output/'section.bin').write_bytes(HEADER.pack(-3,4,7,len(vertices))+b''.join(VERTEX.pack(*v) for v in vertices))
    (output/'fixture.json').write_text(json.dumps({'source':'synthetic-fixture','live_capture':False,
        'cells':len(cells),'vertices':len(vertices),'triangles':len(vertices)//3,'internal_faces_culled':True,
        'minecraft_textures':textures},indent=2),encoding='utf-8')
    print(output, 'cells',len(cells),'vertices',len(vertices))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--dense',action='store_true')
    p.add_argument('--minecraft-jar',type=Path)
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    a=p.parse_args(argv);generate(a.output,a.dense,a.minecraft_jar)
