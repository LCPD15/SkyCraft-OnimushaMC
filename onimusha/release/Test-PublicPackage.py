"""Release integration checks, isolated from the user's game and saves."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, struct, subprocess, sys, tempfile, time, zipfile

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--package',type=Path,required=True);ap.add_argument('--blender',type=Path,required=True)
    a=ap.parse_args();a.package=a.package.resolve();a.blender=a.blender.resolve()
    # Keep failed artifacts for inspection, avoid recursive deletion of computed paths.
    test=Path(tempfile.mkdtemp(prefix='OnimushaMC release test '));package=test/'package with spaces'
    shutil.copytree(a.package,package)
    game=test/'fake game';game.mkdir();(game/'OnimushaWotS.exe').write_bytes(b'isolated fixture');(game/'dinput8.dll').write_bytes(b'existing framework')
    unrelated=game/'unrelated-mod.txt';unrelated.write_text('preserve me')
    legacy=game/'reframework/autorun/onimusha_mc.lua';legacy.parent.mkdir(parents=True);legacy.write_text('-- old script')
    old_dll=game/'reframework/plugins/OnimushaMC.dll';old_dll.parent.mkdir(parents=True);old_dll.write_bytes(b'old plugin')
    def manage(action,success=True):
        proc=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(package/'Manage-OnimushaMC.ps1'),'-Action',action,'-GameRoot',str(game),'-Blender',str(a.blender)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=40)
        assert (proc.returncode==0)==success,proc.stdout+'\n'+proc.stderr
    manifest=json.loads((package/'package-manifest.json').read_text())
    for e in manifest['files']:assert sha(package/e['path'])==e['sha256'],e['path']
    damaged=package/'game/reframework/plugins/OnimushaMC.dll';original=damaged.read_bytes();damaged.write_bytes(original+b'damaged')
    manage('Install',False);assert old_dll.read_bytes()==b'old plugin';damaged.write_bytes(original)
    manage('Install');assert not legacy.exists();assert sha(old_dll)==sha(damaged)
    cfg=game/'reframework/data/onimusha_mc_config.json';settings=json.loads(cfg.read_text());assert settings['runtime_stage']=='C' and not settings['enabled']
    settings['enemy_host_damage_per_mc_point']=500;cfg.write_text(json.dumps(settings))
    manage('Install');assert json.loads(cfg.read_text())['enemy_host_damage_per_mc_point']==500
    manage('Uninstall');assert old_dll.read_bytes()==b'old plugin' and legacy.read_text()=='-- old script'
    assert unrelated.read_text()=='preserve me' and (game/'dinput8.dll').read_bytes()==b'existing framework'
    assert not (game/'reframework/autorun/onimusha_loader.lua').exists()
    manage('Install')
    # Synthetic triangle/opaque checker: no captured commercial game artwork in tests.
    raw=struct.pack('<iiiI',0,0,0,3)+b''.join(struct.pack('<5f3I',*v,0xffffffff,0,1) for v in ((0,0,0,0,0),(1,0,0,1,0),(0,1,0,0,1)))
    atlas=struct.pack('<II',2,2)+bytes([255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255])
    lifetime=subprocess.Popen([sys.executable,'-c','import time; time.sleep(240)'],creationflags=subprocess.CREATE_NO_WINDOW)
    mail=game/'reframework/data/onimusha_mc/native_models';mail.mkdir(parents=True,exist_ok=True)
    logs=test/'worker.log';worker=None
    def job(sequence):
        ident=f'{lifetime.pid}_100_{sequence}';folder=mail/ident;folder.mkdir()
        atlas_name=f'atlas_{lifetime.pid}_100_{sequence}_1.bin';(mail/atlas_name).write_bytes(atlas);(folder/'section.bin').write_bytes(raw)
        req=dict(id=ident,host_pid=lifetime.pid,model=sequence,world=1,epoch=1,mc_pid=0,generation=1,atlas=atlas_name,animated=[])
        (folder/'request.json').write_text(json.dumps(req));(mail/'inbox').mkdir(exist_ok=True);(mail/'inbox'/(ident+'.json')).write_text('{}')
        return folder
    def result(folder):
        deadline=time.monotonic()+75
        while not (folder/'result.json').exists():
            if worker.poll() is not None:raise AssertionError('Worker exited: '+logs.read_text(errors='replace'))
            if time.monotonic()>deadline:raise TimeoutError('Worker timeout: '+logs.read_text(errors='replace'))
            time.sleep(.1)
        r=json.loads((folder/'result.json').read_text());assert r['ok'],r
        for name,digest in r['files'].items():assert sha(game/'natives/stm/mod/onimusha_mc/sections'/r['asset_id']/name)==digest
        return r
    try:
        first=job(1)
        with logs.open('w') as log:
            worker=subprocess.Popen([str(a.blender),'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(package/'worker/Native-Model-Worker.py'),'--','--game',str(game),'--out',str(package/'cache/native-models'),'--host-pid',str(lifetime.pid),'--addon',str(package/'third-party/RE-Mesh-Editor')],stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            r1=result(first);assert not r1['cache_hit']
            r2=result(job(2));assert r2['cache_hit'] and r2['asset_id']==r1['asset_id']
            lifetime.terminate();lifetime.wait(timeout=5);worker.wait(timeout=15)
            assert worker.returncode==0
    finally:
        if lifetime.poll() is None:lifetime.terminate();lifetime.wait(timeout=5)
        if worker and worker.poll() is None:worker.terminate();worker.wait(timeout=5)
    with zipfile.ZipFile(package/'Minecraft-instance.zip') as z:
        assert 'lang:zh_cn' in z.read('.minecraft/options.txt').decode()
        assert 'skycraft.showWindow=true' in z.read('instance.cfg').decode()
        assert not any('saves/' in n or 'accounts' in n.lower() for n in z.namelist())
        jar=next(n for n in z.namelist() if 'skycraft-onimusha-' in n)
        assert jar.endswith('-0.2.0.jar')
    report=dict(passed=True,test_directory=str(test),checks=['manifest','tamper rejection','first install','legacy autorun migration','repeat install preserves settings','uninstall restores files','other mods preserved','space paths','cold Blender conversion','disk cache hit','host exit shuts down worker','Prism profile and privacy'])
    (a.package.parent/'package-validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))

if __name__=='__main__':main()
