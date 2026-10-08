"""Seed the local cache only from successfully round-tripped real capture test assets.
Run with background Blender. Does not write to the game or any Minecraft world.
"""
import hashlib,json,shutil,sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).parent))
from native_model_cache import ModelCache,converter_fingerprint
root=Path('G:/Onimusha_MC_mod');game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
probe=game/'natives/stm/mod/onimusha_mc/probe'
addon=Path('C:/Users/LCPD15/AppData/Roaming/Blender Foundation/Blender/5.2/scripts/addons/RE-Mesh-Editor-main')
cache=ModelCache(root/'assets/native-models/live',converter_fingerprint(Path(__file__).parent,
 (probe/'mc_stone_cube.mdf2.51',probe/'mc_stone_ALBD.tex.251111100'),addon,bpy.app.version_string))
rows=json.loads((root/'logs/tnt-pixel-model-validation.json').read_text())
count=0;keys=set()
for row in rows:
 if 'report' not in row:continue
 report=row['report'];assert report['offline_validation_passed'] and row['details']['pixel_edges']
 captured=root/'logs/automatic-models-20261008'/row['group'];raw=captured/(row['model']+'.bin')
 atlas=captured/('texture_'+row['model'].removeprefix('model_')+'.bin')
 if not atlas.exists():atlas=captured/'atlas.bin'
 key=cache.key(raw.read_bytes(),atlas,json.loads((captured/'animated.json').read_text()),row['white'])
 asset=Path(report['mesh_path']).stem;target=cache.root/asset;target.mkdir(exist_ok=True)
 source=root/'assets/native-models/pixel-validation-20261009'/asset
 for name,sha in report['files'].items():
  data=(source/name).read_bytes();assert hashlib.sha256(data).hexdigest()==sha
  dest=target/name
  if dest.exists():assert hashlib.sha256(dest.read_bytes()).hexdigest()==sha
  else:shutil.copy2(source/name,dest)
 # The builder also uses this immutable report when unrelated atlas changes
 # produce the same compact resource under a new input-content key.
 validation=target/'validation.json'
 if not validation.exists():shutil.copy2(source/'validation.json',validation)
 assert cache.store(key,asset,report['files'],row['details'])
 assert cache.load(key)
 count+=1;keys.add(key)
(root/'logs/tnt-pixel-20261009/primed-cache.json').write_text(json.dumps(dict(validated_cases=count,unique_entries=len(keys),root=str(cache.root),converter=cache.fingerprint),indent=2))
print('VALIDATED LOCAL CACHE SEEDED',len(keys),'unique entries from',count,'cases',flush=True)
