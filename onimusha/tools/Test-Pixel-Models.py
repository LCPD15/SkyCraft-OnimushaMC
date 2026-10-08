"""Convert real captured block/entity models with pixel edges and verify RE file round trips.
No live game mutation. Run using background Blender, as Build-Native-Section.py.
"""
import importlib.util,json,sys,time
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).parent))
from native_model_input import convert_model
from native_section_input import decode_section
def surface_area(data):
 vertices=decode_section(data).vertices
 total=0
 for i in range(0,len(vertices),3):
  a,b,c=vertices[i:i+3];u=[b[k]-a[k] for k in range(3)];v=[c[k]-a[k] for k in range(3)]
  cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
  total+=sum(n*n for n in cross)**.5*.5
 return total
root=Path('G:/Onimusha_MC_mod');game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
spec=importlib.util.spec_from_file_location('builder',Path(__file__).with_name('Build-Native-Section.py'))
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
out=root/'assets/native-models/pixel-validation-20261009'
opts=SimpleNamespace(addon=Path('C:/Users/LCPD15/AppData/Roaming/Blender Foundation/Blender/5.2/scripts/addons/RE-Mesh-Editor-main'),
 material_template=game/'natives/stm/mod/onimusha_mc/probe/mc_stone_cube.mdf2.51',
 tex_template=game/'natives/stm/mod/onimusha_mc/probe/mc_stone_ALBD.tex.251111100',
 out=out,source_kind='runtime-capture',texel_scale=4)
builder.initialize(opts)
results=[]
for group in ('real-mc','real-dynamic','real-hands'):
 source=root/'logs/automatic-models-20261008'/group
 animated=json.loads((source/'animated.json').read_text())
 shared=(source/'atlas.bin').read_bytes() if (source/'atlas.bin').exists() else None
 models=sorted(source.glob('model_*.bin'))
 if group!='real-mc':models=models[:8] # include skin, equipment/held-item canonical faces
 for p in models:
  own=source/p.name.replace('model_','texture_');atlas=own.read_bytes() if own.exists() else shared
  for white in (False,True) if group=='real-dynamic' else (False,):
   start=time.perf_counter()
   try:s,a,details=convert_model(p.read_bytes(),atlas,animated,white_flash=white)
   except ValueError as e:
    if str(e) not in ('fully_transparent_model','model_uv_budget','Degenerate UV triangle'):raise
    results.append(dict(group=group,model=p.stem,fallback=str(e)));continue
   convert_seconds=time.perf_counter()-start
   baseline,_,_=convert_model(p.read_bytes(),atlas,animated,pixel_edges=False)
   area_before,area_after=surface_area(baseline),surface_area(s)
   assert abs(area_before-area_after)<=max(1e-7,area_before*1e-5),(p.name,area_before,area_after)
   folder=out/(group+'-'+p.stem+('-white' if white else ''));folder.mkdir(parents=True,exist_ok=True)
   opts.section=folder/'section.bin';opts.atlas=folder/'atlas.bin'
   opts.section.write_bytes(s);opts.atlas.write_bytes(a)
   report=builder.build(opts)
   row=dict(group=group,model=p.stem,white=white,seconds=round(time.perf_counter()-start,3),
      convert_seconds=round(convert_seconds,3),area_before=area_before,area_after=area_after,details=details,report=report)
   results.append(row);print('PIXEL_MODEL',group,p.stem,white,row['seconds'],details,flush=True)
(root/'logs/tnt-pixel-model-validation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
assert sum('report' in r for r in results)>=20
print('PIXEL MODEL ROUND TRIPS PASSED',len(results),flush=True)
