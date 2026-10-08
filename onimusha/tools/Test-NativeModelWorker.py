"""End-to-end disk mailbox -> persistent Blender -> verified immutable RE assets.
No game process, GameObject, Lua hook, game save, or active MC mapping is touched.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,subprocess,time
root=Path('G:/Onimusha_MC_mod');game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
mail=game/'reframework/data/onimusha_mc/native_models';mail.mkdir(parents=True,exist_ok=True)
out=root/'assets/native-models/live';fixtures=root/'logs/automatic-models-20261008'
parser=argparse.ArgumentParser();parser.add_argument('--log-dir',type=Path,default=fixtures)
logs=parser.parse_args().log_dir;logs.mkdir(parents=True,exist_ok=True)
pid=os.getpid();session=int(time.time()*1000)
cases=[('real-mc',4),('real-mc',5),('real-mc',8)]
dynamic=root/'logs/automatic-models-20261008/real-hands'
cases.append(('real-hands',int(next(dynamic.glob('model_*.bin')).stem.split('_')[1])))
jobs=[]
for sequence,(folder,model) in enumerate(cases,1):
 source=fixtures/folder;job=mail/f'{pid}_{session}_{sequence}';job.mkdir()
 atlasname=f'atlas_{pid}_{session}_{sequence}_1.bin'
 texture=source/f'texture_{model}.bin';texture=texture if texture.exists() else source/'atlas.bin'
 (mail/atlasname).write_bytes(texture.read_bytes());(job/'section.bin').write_bytes((source/f'model_{model}.bin').read_bytes())
 request=dict(id=job.name,host_pid=pid,model=model,world=9,epoch=1,mc_pid=0,generation=1,atlas=atlasname,animated=json.loads((source/'animated.json').read_text()))
 (job/'request.json').write_text(json.dumps(request),encoding='utf-8');jobs.append(job)
args=['D:/SteamLibrary/steamapps/common/Blender/blender.exe','--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(Path(__file__).with_name('Native-Model-Worker.py')),'--','--game',str(game),'--out',str(out),'--addon','C:/Users/LCPD15/AppData/Roaming/Blender Foundation/Blender/5.2/scripts/addons/RE-Mesh-Editor-main','--host-pid',str(pid)]
with (logs/'worker-test.log').open('w') as log:
 proc=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
 deadline=time.monotonic()+90
 while time.monotonic()<deadline and any(not (j/'result.json').exists() for j in jobs):
  if proc.poll() is not None:raise RuntimeError('Converter exited early')
  time.sleep(.2)
 results=[]
 for j in jobs:
  result=json.loads((j/'result.json').read_text());assert result['id']==j.name and result['ok'],result
  if not result.get('empty'):
   for name,sha in result['files'].items():
    installed=game/'natives/stm/mod/onimusha_mc/sections'/result['asset_id']/name
    assert hashlib.sha256(installed.read_bytes()).hexdigest()==sha
  results.append(result)
 (logs/'worker-test-result.json').write_text(json.dumps(dict(passed=True,worker_pid=proc.pid,host_pid=pid,results=results),indent=2),encoding='utf-8')
 print('WORKER PASSED',len(results),'jobs; worker exits automatically when this test host ends',flush=True)
