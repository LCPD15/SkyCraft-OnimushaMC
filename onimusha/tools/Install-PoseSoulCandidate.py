"""Install the verified pose/soul candidate after normal game + MC shutdown."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys
root=Path('G:/Onimusha_MC_mod');repo=root/'source/SkyCraft'
game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
sys.path.insert(0,str(root/'tools/python_packages'))
from lupa.lua54 import LuaRuntime
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def atomic(p,data):
    p.parent.mkdir(parents=True,exist_ok=True);t=p.with_suffix(p.suffix+'.pose-soul.tmp');assert not t.exists();t.write_bytes(data);os.replace(t,p)
def main():
    running=subprocess.check_output(['powershell','-NoProfile','-Command',"@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or ($_.Name -in @('java.exe','javaw.exe') -and $_.CommandLine -like '*Onimusha_MC_mod*') }).Count"],text=True)
    assert running.strip()=='0','Game or project MC still running'
    evidence=root/'logs/dynamic-sync-soul-20261009'
    assert json.loads((evidence/'isolated/verified.json').read_text())['passed']
    assert json.loads((evidence/'animation/result.json').read_text())['passed']
    grant=json.loads((evidence/'diamond-axe.json').read_text('utf-8'));backup=Path(grant['backup'])
    manifest=root/'runtime/deployment.json';m=json.loads(manifest.read_text('utf-8-sig'));entries={e['Relative']:e for e in m['Entries']}
    allowed={
      'reframework\\data\\onimusha_combat_inventory_control.json':'0C7D8346C2B9C26C9371E0008557A968130EAD195332D65A968B65982E6470B6',
      'reframework\\data\\onimusha_mc\\scripts\\onimusha_combat_inventory.lua':'10DC511AB890C5438DD6D5B62502503A5A7A3E846528FC64C91B836A3726B9F9'}
    for rel,e in entries.items():assert sha(game/rel) in {e['InstalledSHA256'],allowed.get(rel)},rel
    assert not json.loads((game/'reframework/data/onimusha_mc_config.json').read_text('utf-8-sig'))['enabled']
    names=['onimusha_mc','onimusha_enemy_hit','onimusha_guard_probe','onimusha_combat_inventory','onimusha_native_blocks','onimusha_native_models','onimusha_soul']
    writes={'reframework\\plugins\\OnimushaMC.dll':root/'build/native/Release/OnimushaMC.dll',
            'reframework\\autorun\\onimusha_loader.lua':repo/'onimusha/adapter/onimusha_loader.lua'}
    for name in names:writes['reframework\\data\\onimusha_mc\\scripts\\'+name+'.lua']=repo/'onimusha/adapter'/(name+'.lua')
    for rel,src in writes.items():
        if rel.endswith('.lua'):LuaRuntime().execute('assert(load(...))',src.read_text('utf-8-sig'))
        dst=game/rel;assert dst.resolve().is_relative_to(game.resolve())
        if rel not in entries:assert not dst.exists(),rel
        if dst.exists():
            old=backup/'game'/rel;assert not old.exists();old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,old)
    world=root/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
    before={str(p.relative_to(world)):sha(p) for p in world.rglob('*') if p.is_file()}
    jar=root/'runtime/minecraft/.minecraft/mods/skycraft-onimusha-0.1.0-dev.jar';srcjar=repo/'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar'
    assert (backup/'minecraft.before.jar').exists();atomic(jar,srcjar.read_bytes())
    for rel,src in writes.items():
        dst=game/rel;atomic(dst,src.read_bytes());assert sha(dst)==sha(src)
        if rel not in entries:entries[rel]={'Relative':rel,'OriginalBackup':None};m['Entries'].append(entries[rel])
        entries[rel]['InstalledSHA256']=sha(dst)
    for rel in allowed:entries[rel]['InstalledSHA256']=sha(game/rel)
    # Probe remains explicitly off after its successful natural four-colour capture.
    rel='reframework\\data\\onimusha_soul_probe_control.json';control=game/rel
    assert json.loads(control.read_text('utf-8-sig'))['enabled']==False
    if rel not in entries:entries[rel]={'Relative':rel,'OriginalBackup':None};m['Entries'].append(entries[rel])
    entries[rel]['InstalledSHA256']=sha(control)
    atomic(manifest,json.dumps(m,indent=2).encode())
    assert all(sha(game/e['Relative'])==e['InstalledSHA256']for e in m['Entries'])
    assert all(sha(world/p)==h for p,h in before.items())
    result={'installed':True,'backup':str(backup),'entries':len(entries),'dll':sha(game/'reframework/plugins/OnimushaMC.dll'),
            'jar':sha(jar),'original_world_unchanged_during_tests_and_install':True,'world_files':len(before),
            'takeover_enabled':False,'gameplay_verified':False,'diamond_axe':grant}
    atomic(evidence/'installed.json',json.dumps(result,indent=2).encode());print(json.dumps(result,indent=2))
if __name__=='__main__':main()
