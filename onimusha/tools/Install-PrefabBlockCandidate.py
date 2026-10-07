"""Stopped-host deployment of the tested Onimusha-only prefab collision candidate."""
from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, sys

root=Path(r'G:\Onimusha_MC_mod')
game=Path(r'F:\SteamLibrary\steamapps\common\OnimushaWotS')
repo=root/'source/SkyCraft'
manifest_path=root/'runtime/deployment.json'
jar=root/'runtime/minecraft/.minecraft/mods/skycraft-onimusha-0.1.0-dev.jar'
world=root/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def stopped():
    command="@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or ($_.Name -match '^javaw?\\.exe$' -and $_.CommandLine -match 'Onimusha_MC_mod') } | Select-Object Name,ProcessId) | ConvertTo-Json -Compress"
    s=subprocess.run(['powershell.exe','-NoProfile','-Command',command],check=True,capture_output=True,text=True).stdout.strip()
    assert s in ('','null','[]'), 'Host/client running: '+s
def atomic(p,data):
    p.parent.mkdir(parents=True,exist_ok=True)
    temp=p.with_name(p.name+'.prefab-candidate.tmp')
    assert not temp.exists(), 'Inspect leftover temporary file: '+str(temp)
    temp.write_bytes(data);os.replace(temp,p)

stopped()
assert (world/'level.dat').is_file(),'Expected existing MC test world is missing'
manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
assert Path(manifest['GameRoot']).resolve()==game.resolve()
for e in manifest['Entries']: assert sha(game/e['Relative'])==e['InstalledSHA256'],e['Relative']
assert sha(jar)=='5A64BF0D97B2CB8CDD6534E33C642A3C601431C8CE42817B5B865EB07EBD43C7','Unexpected installed client; inspect before migration'
cfg_path=game/'reframework/data/onimusha_mc_config.json'
cfg=json.loads(cfg_path.read_text(encoding='utf-8-sig'))
assert cfg['runtime_stage']=='C' and cfg['units_per_block']==1
cfg.update(enabled=False,enable_prefab_block_colliders=True,enable_native_block_colliders=False,enable_block_collider_tests=False)
writes={game/'reframework/plugins/OnimushaMC.dll':(root/'build/native/Release/OnimushaMC.dll').read_bytes(),
        game/'reframework/autorun/onimusha_loader.lua':(repo/'onimusha/adapter/onimusha_loader.lua').read_bytes(),
        cfg_path:(json.dumps(cfg,ensure_ascii=False,indent=2)+'\n').encode(),
        jar:(repo/'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar').read_bytes()}
for n in ['onimusha_mc.lua','onimusha_native_blocks.lua']:
    writes[game/'reframework/data/onimusha_mc/scripts'/n]=(repo/'onimusha/adapter'/n).read_bytes()
sys.path.insert(0,str(root/'tools/python_packages'))
from lupa.lua54 import LuaRuntime
for path,data in writes.items():
    if path.suffix=='.lua': LuaRuntime().execute('assert(load(...))',data.decode('utf-8-sig'))
for n in ['unit_collision.pfb.18','unit_collision_loader.user.3']:
    assert sha(game/'natives/stm/mod/onimusha_mc/probe'/n)==sha(root/'assets/native-probe/generated'/n)
assert not (game/'natives/stm/mod/onimusha_mc/probe/unit_navigation.pfb.18').exists()
assert json.loads((game/'reframework/data/onimusha_native_object_probe_control.json').read_text())['enabled'] is False
for p in writes:
    if p!=jar:
        rel=str(p.relative_to(game))
        owned=next((e for e in manifest['Entries'] if e['Relative']==rel),None)
        assert owned or not p.exists(),'Unowned file: '+str(p)
backup=root/'runtime/test-backups'/('before-prefab-collision-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
backup.mkdir(parents=True,exist_ok=False)
receipt={'backup':str(backup),'world':[], 'changed':[], 'live_test':'pending', 'limit':1280, 'radius':16, 'protocol':13}
shutil.copy2(manifest_path,backup/'deployment.before.json')
for source in world.rglob('*'):
    if source.is_file():
        dest=backup/world.name/source.relative_to(world);dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,dest);assert sha(source)==sha(dest)
        receipt['world'].append({'path':str(source.relative_to(world)),'sha256':sha(dest)})
assert receipt['world'],'World backup must not be empty'
before={p:p.read_bytes() if p.exists() else None for p in writes}
for p,data in before.items():
    if data is not None:
        dest=backup/('client/'+p.name if p==jar else 'game/'+str(p.relative_to(game)))
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        assert sha(dest)==sha(p)
stopped()
try:
    for p,data in writes.items():
        assert (p.read_bytes() if p.exists() else None)==before[p],str(p)
        atomic(p,data)
        digest=sha(p);receipt['changed'].append({'path':str(p),'sha256':digest})
        if p!=jar:
            rel=str(p.relative_to(game));entry=next((e for e in manifest['Entries'] if e['Relative']==rel),None)
            if entry is None: entry={'Relative':rel,'OriginalBackup':None};manifest['Entries'].append(entry)
            entry['InstalledSHA256']=digest
    atomic(manifest_path,(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode())
    for e in manifest['Entries']: assert sha(game/e['Relative'])==e['InstalledSHA256'],e['Relative']
except BaseException:
    for p,data in before.items():
        if data is not None: atomic(p,data)
        elif p.exists():
            assert p.resolve().is_relative_to(game.resolve());p.unlink()
    shutil.copy2(backup/'deployment.before.json',manifest_path)
    raise
receipt['entries_verified']=len(manifest['Entries'])
text=json.dumps(receipt,ensure_ascii=False,indent=2)+'\n'
(backup/'installation.json').write_text(text,encoding='utf-8')
(root/'logs/prefab-block-candidate-installation.json').write_text(text,encoding='utf-8')
print(json.dumps({'backup':str(backup),'world_files':len(receipt['world']),'entries_verified':receipt['entries_verified'],'limit':1280,'live_test':'pending'},ensure_ascii=False))
