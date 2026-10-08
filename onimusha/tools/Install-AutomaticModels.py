"""Install one coherent protocol-15 candidate, preserving the last game-tested build and save."""
from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,sys
project=Path('G:/Onimusha_MC_mod');repo=project/'source/SkyCraft'
game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
sys.path.insert(0,str(project/'tools/python_packages'))
from lupa.lua54 import LuaRuntime
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def atomic(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);temp=path.with_suffix(path.suffix+'.automatic.tmp');temp.write_bytes(data);os.replace(temp,path)
def main():
 running=subprocess.run(['powershell','-NoProfile','-Command',"@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or ($_.Name -in @('java.exe','javaw.exe') -and $_.CommandLine -like '*Onimusha_MC_mod*') }).Count"],capture_output=True,text=True,check=True)
 assert running.stdout.strip()=='0','Game or project Minecraft is still running'
 manifest=project/'runtime/deployment.json';m=json.loads(manifest.read_text(encoding='utf-8-sig'))
 for e in m['Entries']:assert sha(game/e['Relative'])==e['InstalledSHA256'],e['Relative']
 stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');backup=project/'runtime/test-backups'/('before-automatic-models-'+stamp);backup.mkdir(parents=True)
 world=project/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2';shutil.copytree(world,backup/'world')
 hashes={str(p.relative_to(world)):sha(p) for p in world.rglob('*') if p.is_file()}
 assert all(sha(backup/'world'/p)==h for p,h in hashes.items())
 (backup/'world-sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8');shutil.copy2(manifest,backup/'deployment.before.json')
 config=json.loads((game/'reframework/data/onimusha_mc_config.json').read_text(encoding='utf-8-sig'))
 assert config['runtime_stage']=='C' and config['enable_prefab_block_colliders'] and not config['enable_block_collider_tests']
 config['enable_native_section_rendering']=True;config['enabled']=False
 writes={'reframework\\plugins\\OnimushaMC.dll':(project/'build/native/Release/OnimushaMC.dll').read_bytes(),
  'reframework\\autorun\\onimusha_loader.lua':(repo/'onimusha/adapter/onimusha_loader.lua').read_bytes(),
  'reframework\\data\\onimusha_mc_config.json':json.dumps(config,indent=2).encode()}
 names=['onimusha_mc','onimusha_enemy_hit','onimusha_guard_probe','onimusha_combat_inventory','onimusha_native_blocks','onimusha_native_models']
 for name in names:
  data=(repo/'onimusha/adapter'/(name+'.lua')).read_bytes();LuaRuntime().execute('assert(load(...))',data.decode('utf-8-sig'))
  writes['reframework\\data\\onimusha_mc\\scripts\\'+name+'.lua']=data
 LuaRuntime().execute('assert(load(...))',writes['reframework\\autorun\\onimusha_loader.lua'].decode('utf-8-sig'))
 entries={e['Relative']:e for e in m['Entries']}
 for rel,data in writes.items():
  dst=game/rel;assert dst.resolve().is_relative_to(game.resolve())
  if rel not in entries:assert not dst.exists(),str(dst)
  if dst.exists():old=backup/'game'/rel;old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,old)
 jar=project/'runtime/minecraft/.minecraft/mods/skycraft-onimusha-0.1.0-dev.jar';shutil.copy2(jar,backup/'minecraft.before.jar')
 # The inventory/model test JAR has already run in an isolated world. Retain the
 # last human-tested protocol-14 JAR as well, for a coherent rollback.
 stable=project/'runtime/test-backups/automatic-models-20261008/skycraft-onimusha-0.1.0-dev.jar'
 assert stable.exists();shutil.copy2(stable,backup/'minecraft.protocol14.jar')
 launcher=project/'tools/MC-launch-dev.ps1';shutil.copy2(launcher,backup/'MC-launch-dev.ps1')
 launcher_text=launcher.read_text(encoding='utf-8-sig')
 marker='# OMC_AUTOMATIC_MODELS_WORKER'
 hook=marker+"\nif ($MappingName -eq 'Local\\OnimushaMC_v1') {\n    & (Join-Path $ProjectRoot 'source\\SkyCraft\\onimusha\\tools\\Start-NativeModelWorker.ps1')\n}\n"
 assert marker not in launcher_text,'Already installed automatic worker hook'
 insertion='$taskProcess = Start-Process -FilePath $taskJava'
 assert insertion in launcher_text;launcher_text=launcher_text.replace(insertion,hook+insertion,1)
 atomic(jar,(repo/'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar').read_bytes())
 for rel,data in writes.items():
  dst=game/rel;atomic(dst,data);entry=entries.get(rel)
  if entry is None:entry={'Relative':rel,'OriginalBackup':None};m['Entries'].append(entry)
  entry['InstalledSHA256']=sha(dst)
 atomic(launcher,b'\xef\xbb\xbf'+launcher_text.encode('utf-8'))
 atomic(manifest,json.dumps(m,indent=2).encode())
 for e in m['Entries']:assert sha(game/e['Relative'])==e['InstalledSHA256']
 assert all(sha(world/p)==h for p,h in hashes.items())
 result=dict(installed_at=stamp,backup=str(backup),protocol=15,entries=len(m['Entries']),world_unchanged=True,world_files=len(hashes),
  dll_sha256=sha(game/'reframework/plugins/OnimushaMC.dll'),jar_sha256=sha(jar),lua_sha256=sha(game/'reframework/data/onimusha_mc/scripts/onimusha_native_models.lua'),
  native_block_limit=1280,dynamic_faces_per_stream=512,native_lights=64,live_game_verified=False,takeover_enabled=False)
 atomic(backup/'receipt.json',json.dumps(result,indent=2).encode());atomic(project/'logs/automatic-models-20261008/install.json',json.dumps(result,indent=2).encode())
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
