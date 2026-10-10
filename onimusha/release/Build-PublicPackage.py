"""Build a portable Onimusha-only release; never install into the running game.
Requires explicit compiled artifacts and a hash-pinned Fabric API JAR.
Source archive must be made with git archive after the release commit.
"""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, zipfile

API_NAME='fabric-api-0.161.0+26.3.jar'
API_SHA512='ed6b2586d6fde11fde8472f5a527c51e99b67026e46f94d4bfd85e7e28ce5ee299173ee16ad576ceb51f39f98d30a811086a6deb1a86a524859cc16e12da109d'
LUA=('onimusha_mc','onimusha_enemy_hit','onimusha_guard_probe','onimusha_combat_inventory','onimusha_native_blocks','onimusha_native_models','onimusha_soul','onimusha_npc_damage')
WORKER=('Native-Model-Worker.py','Build-Native-Section.py','native_model_input.py','native_section_input.py','native_worker_io.py','native_model_loader.py','native_model_cache.py','onimusha_raw_tex.py')
JVM_ARGS='--enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED -XX:StackShadowPages=32 -Donimusha.link=Local\\OnimushaMC_v1 -Donimusha.worldName=OnimushaMC -Donimusha.unitsPerBlock=1.0 -Dskycraft.showWindow=true -Dskycraft.quitWithSkyrim=true -Donimusha.swordBlocking=true'

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write_json(p,value):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def copy(src,dst):
    if not src.is_file():raise FileNotFoundError(src)
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def archive(folder,path):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for f in sorted(folder.rglob('*')):
            if f.is_file():z.write(f,f.relative_to(folder).as_posix())

def build(a):
    repo=Path(__file__).resolve().parents[2]
    version=dict(line.split('=',1) for line in (repo/'fabric/gradle.properties').read_text().splitlines() if '=' in line)['version']
    if hashlib.sha512(a.fabric_api.read_bytes()).hexdigest()!=API_SHA512:raise ValueError('Fabric API hash differs from the tested dependency')
    with zipfile.ZipFile(a.fabric_jar) as z:
        if json.loads(z.read('fabric.mod.json'))['version']!=version:raise ValueError('JAR version does not match source version')
    a.output.mkdir(parents=True,exist_ok=True)
    package=a.output/('OnimushaMC-v'+version+'-win64')
    package.mkdir(exist_ok=False)  # no accidental mixing with an older release
    copy(a.native_dll,package/'game/reframework/plugins/OnimushaMC.dll')
    copy(repo/'onimusha/adapter/onimusha_loader.lua',package/'game/reframework/autorun/onimusha_loader.lua')
    for n in LUA:copy(repo/'onimusha/adapter'/(n+'.lua'),package/'game/reframework/data/onimusha_mc/scripts'/(n+'.lua'))
    for p in (repo/'onimusha/release-config').glob('*.json'):copy(p,package/'game/reframework/data'/p.name)
    for p in (repo/'onimusha/assets/natives').rglob('*'):
        if p.is_file():copy(p,package/'game/natives'/p.relative_to(repo/'onimusha/assets/natives'))
    for n in WORKER:copy(repo/'onimusha/tools'/n,package/'worker'/n)
    for p in (repo/'onimusha/tools/assets').glob('*_loader.user.3'):copy(p,package/'worker/assets'/p.name)
    for p in (repo/'onimusha/release').iterdir():
        if p.suffix in ('.ps1','.cmd'):copy(p,package/p.name)
    for p in (repo/'onimusha/release-deps/RE-Mesh-Editor').rglob('*'):
        if p.is_file() and '__pycache__' not in p.parts:copy(p,package/'third-party/RE-Mesh-Editor'/p.relative_to(repo/'onimusha/release-deps/RE-Mesh-Editor'))
    for n in ('README.md','LICENSE'):copy(repo/n,package/n)
    for n in ('ONIMUSHA-INSTALL.md','ONIMUSHA-BUILD.md','ONIMUSHA-RELEASE-NOTES.md','ONIMUSHA-THIRD-PARTY.md'):
        copy(repo/'docs'/n,package/'docs'/n)
    copy(repo/'onimusha/native/THIRD-PARTY-NOTICES.txt',package/'third-party/native-NOTICES.txt')
    with zipfile.ZipFile(a.fabric_api) as z:
        notices=[n for n in z.namelist() if 'license' in n.lower() and not n.endswith('/')]
        for i,n in enumerate(notices):
            target=package/'third-party'/('Fabric-API-'+str(i)+'-'+Path(n).name);target.write_bytes(z.read(n))
        if not notices:raise ValueError('Fabric API license missing')
    instance=a.output/'minecraft-instance';instance.mkdir(exist_ok=False)
    write_json(instance/'mmc-pack.json',{'formatVersion':1,'components':[
        {'uid':'net.minecraft','version':'26.3','important':True},
        {'uid':'net.fabricmc.fabric-loader','version':'0.19.5'}]})
    # Qt INI treats backslashes as escapes; quote and double them in JvmArgs.
    ini_args=JVM_ARGS.replace('\\','\\\\')
    (instance/'instance.cfg').write_text('[General]\nInstanceType=OneSix\nname=OnimushaMC\niconKey=default\nOverrideJavaArgs=true\nJvmArgs="'+ini_args+'"\nOverrideMemory=true\nMinMemAlloc=512\nMaxMemAlloc=4096\nOverrideConsole=true\nShowConsole=false\nAutoCloseConsole=false\nShowConsoleOnError=true\n',encoding='utf-8')
    mods=instance/'.minecraft/mods'
    copy(a.fabric_jar,mods/('skycraft-onimusha-'+version+'.jar'));copy(a.fabric_api,mods/API_NAME)
    (instance/'.minecraft/options.txt').write_text('lang:zh_cn\npauseOnLostFocus:false\n',encoding='utf-8')
    archive(instance,package/'Minecraft-instance.zip')
    copy(package/'Minecraft-instance.zip',a.output/('OnimushaMC-v'+version+'-Minecraft-instance.zip'))
    (package/'Minecraft-JVM-arguments.txt').write_text(JVM_ARGS+'\n',encoding='utf-8')
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
    dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip())
    if dirty and not a.allow_dirty:raise ValueError('Commit release changes before final packaging (or use --allow-dirty for validation only).')
    write_json(package/'SOURCE-IDENTITY.json',{'commit':head,'version':version,'dirty':dirty,'protocol':16,'game':'OnimushaWotS 01.000.001 / TDB82','native_dll_sha256':digest(a.native_dll),'fabric_jar_sha256':digest(a.fabric_jar)})
    write_json(package/'package-manifest.json',{'version':version,'files':[{'path':p.relative_to(package).as_posix(),'sha256':digest(p)} for p in sorted(package.rglob('*')) if p.is_file()]})
    result=package.parent/(package.name+'.zip');archive(package,result)
    print(json.dumps({'zip':str(result),'sha256':digest(result),'bytes':result.stat().st_size,'source':head,'dirty':dirty}))
    return package

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('native-dll','fabric-jar','fabric-api','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--allow-dirty',action='store_true');build(p.parse_args())
