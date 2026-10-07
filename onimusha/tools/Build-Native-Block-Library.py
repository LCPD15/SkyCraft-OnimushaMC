"""Prebuild reusable default Minecraft cube resources; no conversion during placement.
Run inside Blender, output library.json plus verified MESH/MDF/TEX files on G:.
MOD制作：LCPD15/LCPD拉灯
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import time
from types import SimpleNamespace
import zipfile
import bpy
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from native_section_input import HEADER,VERTEX

ap=argparse.ArgumentParser();ap.add_argument('--addon',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--game',type=Path,required=True);ap.add_argument('--jar',type=Path,required=True)
a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);a.out.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('builder',Path(__file__).with_name('Build-Native-Section.py'))
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
names=['stone','cobblestone','iron_block','tnt','dirt','oak_planks','obsidian','gold_block','diamond_block',
       'stone_bricks','bricks','netherite_block','emerald_block','copper_block','quartz_block','bedrock']
faces=[((0,-1,0),(1,0,0),(0,0,1)),((0,1,0),(1,0,0),(0,0,-1)),
       ((0,0,-1),(-1,0,0),(0,1,0)),((0,0,1),(1,0,0),(0,1,0)),
       ((-1,0,0),(0,0,1),(0,1,0)),((1,0,0),(0,0,-1),(0,1,0))]
template=a.game/'natives/stm/mod/onimusha_mc/probe';items={};start=time.perf_counter()
with zipfile.ZipFile(a.jar)as jar:
 for kind,name in enumerate(names,1):
    folder=a.out/name;folder.mkdir(exist_ok=True)
    sprites=[name]*3
    if name=='tnt':sprites=['tnt_side','tnt_top','tnt_bottom']
    if name=='quartz_block':sprites=['quartz_block_side','quartz_block_top','quartz_block_bottom']
    atlas=np.full((32,64,4),255,dtype=np.uint8);sources=[]
    for index,sprite in enumerate(sprites):
        entry='assets/minecraft/textures/block/'+sprite+'.png';data=jar.read(entry)
        path=folder/(sprite+'.png');path.write_bytes(data)
        img=bpy.data.images.load(str(path),check_existing=False);img.colorspace_settings.name='Non-Color'
        assert tuple(img.size)==(16,16)
        pixels=np.rint(np.array(img.pixels[:]).reshape(16,16,4)[::-1]*255).astype(np.uint8)
        bpy.data.images.remove(img);assert np.all(pixels[:,:,3]==255)
        atlas[0:20,index*20:index*20+20]=np.pad(pixels,((2,2),(2,2),(0,0)),mode='edge')
        sources.append(dict(entry=entry,sha256=hashlib.sha256(data).hexdigest()))
    vertices=[]
    for ordinal,(n,u,v) in enumerate(faces):
        tile=2 if ordinal==0 else 1 if ordinal==1 else 0
        quad=[]
        for s,t in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]:
            xyz=tuple(n[i]*.5+u[i]*s+v[i]*t for i in range(3))
            uv=((tile*20+2+(s+.5)*16)/64,(2+(.5-t)*16)/32)
            quad.append((*xyz,*uv,0xffffffff,0x0f0f,1|((ordinal+1)<<4)))
        vertices.extend(quad[k]for k in(0,1,2,0,2,3))
    section=folder/'section.bin';section.write_bytes(HEADER.pack(0,0,0,len(vertices))+b''.join(VERTEX.pack(*v)for v in vertices))
    pixels=folder/'atlas.bin';pixels.write_bytes(struct.pack('<II',64,32)+atlas.tobytes())
    opts=SimpleNamespace(addon=a.addon,section=section,atlas=pixels,material_template=template/'mc_stone_cube.mdf2.51',
        tex_template=template/'mc_stone_ALBD.tex.251111100',out=a.out/'generated',source_kind='synthetic-fixture',texel_scale=8)
    report=builder.build(opts);stem=Path(report['mesh_path']).stem
    items[str(kind)]={'name':name,'asset_id':stem,'files':report['files'],'source_textures':sources}
manifest={'default_textures_only':True,'cube_bounds':[-.5,.5],'items':items,'seconds':time.perf_counter()-start,
          'live_game_tested':False,'minecraft_jar_sha256':hashlib.sha256(a.jar.read_bytes()).hexdigest()}
(a.out/'library.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'kinds':len(items),'seconds':manifest['seconds'],'library':str(a.out/'library.json')}),flush=True)
