"""Install the live native-section candidate only after host/MC exit. Preserve world and previous build."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys

project=Path('G:/Onimusha_MC_mod');repo=project/'source/SkyCraft'
game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
sys.path.insert(0,str(project/'tools/python_packages'))
from lupa.lua54 import LuaRuntime

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    running=subprocess.run(['powershell','-NoProfile','-Command',
        "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or ($_.Name -in @('java.exe','javaw.exe') -and $_.CommandLine -like '*Onimusha_MC_mod*') }).Count"],capture_output=True,text=True,check=True)
    assert running.stdout.strip()=='0','Host or project Minecraft still running'
    manifest=project/'runtime/deployment.json';m=json.loads(manifest.read_text(encoding='utf-8-sig'))
    for e in m['Entries']:assert sha(game/e['Relative'])==e['InstalledSHA256'],e['Relative']
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=project/'runtime/test-backups'/('before-native-sections-'+stamp);backup.mkdir(parents=True)
    world=project/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
    shutil.copytree(world,backup/'world')
    files={str(p.relative_to(world)):sha(p) for p in world.rglob('*') if p.is_file()}
    assert all(sha(backup/'world'/n)==h for n,h in files.items())
    (backup/'world-sha256.json').write_text(json.dumps(files,indent=2),encoding='utf-8')
    shutil.copy2(manifest,backup/'deployment.before.json')
    config=json.loads((game/'reframework/data/onimusha_mc_config.json').read_text(encoding='utf-8-sig'))
    assert config['runtime_stage']=='C' and config['enable_prefab_block_colliders'] and not config['enable_block_collider_tests']
    config['enable_native_section_rendering']=True
    config['enabled']=False
    writes={'reframework\\plugins\\OnimushaMC.dll':(project/'build/native/Release/OnimushaMC.dll').read_bytes(),
        'reframework\\autorun\\onimusha_loader.lua':(repo/'onimusha/adapter/onimusha_loader.lua').read_bytes(),
        'reframework\\data\\onimusha_mc_config.json':json.dumps(config,indent=2).encode()}
    names=['onimusha_mc','onimusha_enemy_hit','onimusha_guard_probe','onimusha_combat_inventory','onimusha_native_blocks','onimusha_native_instances']
    for name in names:
        data=(repo/'onimusha/adapter'/(name+'.lua')).read_bytes()
        LuaRuntime().execute('assert(load(...))',data.decode('utf-8-sig'))
        writes['reframework\\data\\onimusha_mc\\scripts\\'+name+'.lua']=data
    libroot=project/'assets/native-block-library'
    lib=json.loads((libroot/'library.json').read_text(encoding='utf-8'))
    assert len(lib['items'])==16
    writes['reframework\\data\\onimusha_mc\\native_block_library.json']=(libroot/'library.json').read_bytes()
    for row in lib['items'].values():
        for name,expected in row['files'].items():
            asset=libroot/'generated'/row['asset_id']/name
            assert sha(asset).lower()==expected
            writes['natives\\stm\\mod\\onimusha_mc\\sections\\'+row['asset_id']+'\\'+name]=asset.read_bytes()
    jar=project/'runtime/minecraft/.minecraft/mods/skycraft-onimusha-0.1.0-dev.jar'
    shutil.copy2(jar,backup/'minecraft.jar')
    newjar=repo/'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar'
    assert newjar.is_file()
    entries={e['Relative']:e for e in m['Entries']}
    for rel,data in writes.items():
        dst=game/rel;assert dst.resolve().is_relative_to(game.resolve())
        if rel not in entries:assert not dst.exists(),str(dst)
        if dst.exists():
            old=backup/'game'/rel;old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,old)
    shutil.copy2(newjar,jar)
    for rel,data in writes.items():
        dst=game/rel;dst.parent.mkdir(parents=True,exist_ok=True);tmp=dst.with_suffix(dst.suffix+'.candidate.tmp');tmp.write_bytes(data);os.replace(tmp,dst)
        e=entries.get(rel)
        if e is None:e={'Relative':rel,'OriginalBackup':None};m['Entries'].append(e)
        e['InstalledSHA256']=sha(dst)
    temp=manifest.with_suffix('.native.tmp');temp.write_text(json.dumps(m,indent=2),encoding='utf-8');os.replace(temp,manifest)
    launcher=project/'tools/MC-launch-dev.ps1';shutil.copy2(launcher,backup/'MC-launch-dev.ps1')
    text=launcher.read_text(encoding='utf-8-sig')
    marker='# OMC_NATIVE_SECTIONS_WORKER'
    oldhook=marker+"\nif ($MappingName -eq 'Local\\OnimushaMC_v1') {\n    & (Join-Path $ProjectRoot 'source\\SkyCraft\\onimusha\\tools\\Start-NativeSectionWorker.ps1')\n}\n"
    if oldhook in text:
        text=text.replace(oldhook,'');launcher.write_text(text,encoding='utf-8-sig')
    for e in m['Entries']:assert sha(game/e['Relative'])==e['InstalledSHA256']
    receipt=dict(installed_at=stamp,backup=str(backup),world_files=len(files),world_unchanged=True,entries=len(m['Entries']),
        dll_sha256=sha(game/'reframework/plugins/OnimushaMC.dll'),launcher_sha256=sha(launcher),
        original_collision_cap=1280,native_section_rendering=True,mode="prebuilt_instances",protocol=14,jar_sha256=sha(jar),live_game_tested=False)
    (backup/'receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    (project/'logs/live-native-sections-20261008/install.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
