"""Deploy the tested native lighting repair only while both game and MC are stopped."""
from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,sys
root=Path('G:/Onimusha_MC_mod');repo=root/'source/SkyCraft'
game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
sys.path.insert(0,str(root/'tools/python_packages'))
from lupa.lua54 import LuaRuntime

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def atomic(path,data):
 temp=path.with_suffix(path.suffix+'.lighting.tmp');temp.write_bytes(data);os.replace(temp,path)

def main():
 result=subprocess.run(['powershell','-NoProfile','-Command',"@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or ($_.Name -in @('java.exe','javaw.exe') -and $_.CommandLine -like '*Onimusha_MC_mod*') }).Count"],capture_output=True,text=True,check=True)
 assert result.stdout.strip()=='0','Game or project Minecraft is running'
 manifest=root/'runtime/deployment.json';m=json.loads(manifest.read_text(encoding='utf-8-sig'))
 entries={e['Relative']:e for e in m['Entries']}
 for rel,e in entries.items():assert sha(game/rel)==e['InstalledSHA256'],f'Untracked installed change: {rel}'
 writes={'reframework\\plugins\\OnimushaMC.dll':root/'build/native/Release/OnimushaMC.dll',
         'reframework\\data\\onimusha_mc\\scripts\\onimusha_native_models.lua':repo/'onimusha/adapter/onimusha_native_models.lua'}
 for rel in writes:assert sha(game/rel)==entries[rel]['InstalledSHA256'],f'Untracked installed change: {rel}'
 LuaRuntime().execute('assert(load(...))',writes[next(k for k in writes if k.endswith('.lua'))].read_text(encoding='utf-8-sig'))
 config=json.loads((game/'reframework/data/onimusha_mc_config.json').read_text(encoding='utf-8-sig'))
 assert not config['enabled'],'Takeover must remain disabled on restart'
 stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
 backup=root/'runtime/test-backups'/('native-lighting-repair-'+stamp);backup.mkdir(parents=True)
 world=root/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
 shutil.copytree(world,backup/'world')
 hashes={str(p.relative_to(world)):sha(p) for p in world.rglob('*') if p.is_file()}
 assert all(sha(backup/'world'/p)==h for p,h in hashes.items())
 (backup/'world-sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
 shutil.copy2(manifest,backup/'deployment.before.json')
 installed={}
 for rel,src in writes.items():
  dst=game/rel;assert dst.resolve().is_relative_to(game.resolve())
  old=backup/'game'/rel;old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,old)
  atomic(dst,src.read_bytes());assert sha(src)==sha(dst)
  installed[rel]=entries[rel]['InstalledSHA256']=sha(dst)
 atomic(manifest,json.dumps(m,indent=2).encode())
 assert all(sha(world/p)==h for p,h in hashes.items())
 mismatches=[e['Relative'] for e in m['Entries'] if sha(game/e['Relative'])!=e['InstalledSHA256']]
 receipt=dict(installed_at=stamp,backup=str(backup),protocol=15,entries=len(m['Entries']),hashes=installed,
  world_unchanged=True,world_files=len(hashes),native_display_radius=128,collision_radius=16,
  native_display_limit=1280,live_game_verified=False,takeover_enabled=False,manifest_mismatches=mismatches)
 log=root/'logs/native-lighting-repair-20261008';log.mkdir(parents=True,exist_ok=True)
 atomic(log/'install.json',json.dumps(receipt,indent=2).encode())
 atomic(backup/'receipt.json',json.dumps(receipt,indent=2).encode())
 print(json.dumps(receipt,indent=2));assert not mismatches,mismatches

if __name__=='__main__':main()
