"""Actual Blender worker restart test in an isolated fixture directory, not the live game."""
import json,os,shutil,subprocess,sys,time
from pathlib import Path
root=Path('G:/Onimusha_MC_mod');tools=Path(__file__).parent
from native_worker_io import atomic_json
out=root/'logs/tnt-pixel-20261009/cache-worker-test'/time.strftime('%H%M%S')
game=out/'fixture-game';probe=game/'natives/stm/mod/onimusha_mc/probe';probe.mkdir(parents=True)
(game/'OnimushaWotS.exe').write_bytes(b'Offline fixture marker; never executed')
real=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS/natives/stm/mod/onimusha_mc/probe')
for name in ('mc_stone_cube.mdf2.51','mc_stone_ALBD.tex.251111100'):shutil.copy2(real/name,probe/name)
captured=root/'logs/automatic-models-20261008/real-mc'
mail=game/'reframework/data/onimusha_mc/native_models';mail.mkdir(parents=True)
results=[]
for run in range(2):
 host=subprocess.Popen([sys.executable,'-c','import time;time.sleep(90)'],creationflags=subprocess.CREATE_NO_WINDOW)
 log=(out/f'worker-{run}.log').open('w',encoding='utf-8')
 worker=None
 try:
  jobid=f'{host.pid}_{int(time.time()*1000)}_1';job=mail/jobid;job.mkdir()
  atlas=f'atlas_{host.pid}_1_0_1.bin';shutil.copy2(captured/'atlas.bin',mail/atlas)
  shutil.copy2(captured/'model_1.bin',job/'section.bin')
  atomic_json(job/'request.json',dict(id=jobid,host_pid=host.pid,world=run+1,epoch=run+81,mc_pid=100+run,
      generation=run+1,model=1+run*200,atlas=atlas,animated=json.loads((captured/'animated.json').read_text()),priority=0,white_flash=False))
  args=['D:/SteamLibrary/steamapps/common/Blender/blender.exe','--background','--factory-startup','--disable-autoexec',
      '--python-exit-code','1','--python',str(tools/'Native-Model-Worker.py'),'--','--game',str(game),'--out',str(out/'cache'),
      '--addon','C:/Users/LCPD15/AppData/Roaming/Blender Foundation/Blender/5.2/scripts/addons/RE-Mesh-Editor-main','--host-pid',str(host.pid)]
  worker=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
  deadline=time.monotonic()+45
  while not (job/'result.json').exists():
   if worker.poll() is not None:raise RuntimeError(f'Worker stopped, see {log.name}')
   if time.monotonic()>deadline:raise TimeoutError('Cache worker result timed out')
   time.sleep(.1)
  result=json.loads((job/'result.json').read_text());assert result['ok'],result
  assert result['cache_hit']==(run==1),result
  if run:assert result['asset_id']==results[0]['asset_id'] and result['files']==results[0]['files']
  results.append(result)
 finally:
  host.terminate();host.wait(5)
  if worker:
   try:worker.wait(10)
   except subprocess.TimeoutExpired:worker.terminate();worker.wait(5)
  log.close()
assert len(results)==2
(out/'result.json').write_text(json.dumps(results,indent=2))
print(json.dumps(dict(passed=True,path=str(out),cold_seconds=results[0]['seconds'],restart_cache_seconds=results[1]['seconds']),indent=2))
