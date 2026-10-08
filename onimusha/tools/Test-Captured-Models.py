"""Offline conversion integration test using actual Fabric-exported complete appearances."""
import importlib.util,json,sys,time
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).parent))
from native_model_input import convert_model
root=Path('G:/Onimusha_MC_mod')
source=root/'logs/automatic-models-20261008'/('real-hands' if '--hands' in sys.argv else 'real-dynamic' if '--dynamic' in sys.argv else 'real-mc')
out=root/'assets/native-models/selftest'
spec=importlib.util.spec_from_file_location('builder',Path(__file__).with_name('Build-Native-Section.py'))
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
opts=SimpleNamespace(addon=Path('C:/Users/LCPD15/AppData/Roaming/Blender Foundation/Blender/5.2/scripts/addons/RE-Mesh-Editor-main'),
 material_template=game/'natives/stm/mod/onimusha_mc/probe/mc_stone_cube.mdf2.51',
 tex_template=game/'natives/stm/mod/onimusha_mc/probe/mc_stone_ALBD.tex.251111100',
 out=out,source_kind='runtime-capture',texel_scale=4)
atlas=(source/'atlas.bin').read_bytes() if (source/'atlas.bin').exists() else None
animated=json.loads((source/'animated.json').read_text())
results=[]
for p in sorted(source.glob('model_*.bin')):
 start=time.perf_counter()
 own=source/p.name.replace('model_','texture_')
 try: section,texture,details=convert_model(p.read_bytes(),own.read_bytes() if own.exists() else atlas,animated)
 except ValueError as e:
  # Invisible skin faces / zero-area item UV strips should stay on the MC side.
  if str(e) in ('fully_transparent_model','model_uv_budget','Degenerate UV triangle'):
   print('FALLBACK',p.stem,str(e),flush=True);continue
  raise
 folder=out/p.stem;folder.mkdir(parents=True,exist_ok=True)
 opts.section=folder/'section.bin';opts.atlas=folder/'atlas.bin'
 opts.section.write_bytes(section);opts.atlas.write_bytes(texture)
 report=builder.build(opts)
 results.append(dict(model=p.stem,seconds=round(time.perf_counter()-start,3),details=details,report=report))
 print('CONVERTED',p.stem,results[-1]['seconds'],details,flush=True)
(source/'conversion-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
assert len(results)>=7
print('ALL REAL CAPTURED MODELS PASSED',len(results),flush=True)
