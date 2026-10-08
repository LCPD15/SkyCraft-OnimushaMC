"""Persistent Blender converter for Onimusha complete block appearances. Never calls running-game SDK.
Host-scoped immutable requests, atomic result publication, bounded resource cache.
MOD制作：LCPD15/LCPD拉灯
"""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).parent))
from native_model_input import convert_model

from native_worker_io import atomic_json,completed_result,queued_requests
from native_model_loader import add_loader,LOADER_VERSION

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--game',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--addon',type=Path,required=True);ap.add_argument('--host-pid',type=int,required=True)
    a=ap.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert a.host_pid>0 and (a.game/'OnimushaWotS.exe').exists()
    k=ctypes.WinDLL('kernel32',use_last_error=True)
    k.OpenProcess.restype=ctypes.c_void_p;k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32]
    k.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32];k.CloseHandle.argtypes=[ctypes.c_void_p]
    handle=k.OpenProcess(0x100000,False,a.host_pid);assert handle,'Cannot observe host lifetime'
    root=a.game/'reframework/data/onimusha_mc/native_models';root.mkdir(parents=True,exist_ok=True)
    # One converter per host, held for lifetime. No second worker races result/asset publication.
    import msvcrt
    lock=(root/(str(a.host_pid)+'.lock')).open('a+b');lock.seek(0);lock.write(b'1');lock.flush();lock.seek(0)
    msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    spec=importlib.util.spec_from_file_location('native_section_builder',Path(__file__).with_name('Build-Native-Section.py'))
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    template=a.game/'natives/stm/mod/onimusha_mc/probe'
    opts=SimpleNamespace(addon=a.addon,material_template=template/'mc_stone_cube.mdf2.51',
        tex_template=template/'mc_stone_ALBD.tex.251111100',out=a.out,source_kind='runtime-capture',texel_scale=4)
    builder.initialize(opts)
    done=set();unpublished={};metadata={};started=time.time();built=0;last_heartbeat=0
    known_assets={p.name for p in a.out.glob('section_*') if p.is_dir()} if a.out.exists() else set()
    cache_bytes=sum(p.stat().st_size for p in a.out.glob('section_*/*') if p.is_file()) if a.out.exists() else 0
    def heartbeat():
        nonlocal last_heartbeat
        if time.monotonic()-last_heartbeat<1:return
        last_heartbeat=time.monotonic()
        atomic_json(root/'worker.json',dict(host_pid=a.host_pid,pid=os.getpid(),state='ready',jobs=len(done),built=built,
            publishing=len(unpublished),alive_at=time.time(),started=started))
    def publish(job,result):
        if not atomic_json(job/'result.json',result):
            unpublished[job.name]=result;return
        unpublished.pop(job.name,None);done.add(job.name)
        p=job/'section.bin'
        try:p.unlink(missing_ok=True)
        except PermissionError:pass
        print(json.dumps(result,ensure_ascii=False),flush=True)
    while k.WaitForSingleObject(handle,0)==258:
        heartbeat()
        processed=0
        for path in queued_requests(root,a.host_pid,done,metadata):
            if k.WaitForSingleObject(handle,0)!=258:break
            if path.parent.name in done:continue
            heartbeat();job=path.parent
            if job.name in unpublished:
                publish(job,unpublished[job.name]);continue
            if processed>=4:break  # discover newly placed blocks before draining old entity faces
            result=dict(id=job.name,ok=False)
            try:
                assert re.fullmatch(r'\d+_\d+_\d+',job.name) and len(done)<=8192
                req=json.loads(path.read_text(encoding='utf-8'));assert req['id']==job.name and req['host_pid']==a.host_pid
                previous=completed_result(job,req)
                if previous is not None:
                    # Upgrade old conversion receipts without raw inputs, re-export,
                    # or mutation of an already loaded Mesh/MDF/TEX.
                    if previous['ok'] and not previous.get('empty'):
                        previous['files']=add_loader(a.game,previous['asset_id'],previous['files'])
                        previous['loader_version']=LOADER_VERSION
                        publish(job,previous)
                    else:done.add(job.name)
                    continue
                processed+=1
                result.update(model=req['model'],world=req['world'],epoch=req['epoch'],mc_pid=req['mc_pid'],generation=req['generation'])
                raw=(job/'section.bin').read_bytes()
                assert re.fullmatch(r'atlas_\d+_\d+_\d+_\d+\.bin',req['atlas'])
                atlas=(root/req['atlas']).read_bytes()
                result.update(model=req['model'],world=req['world'],epoch=req['epoch'],
                    mc_pid=req['mc_pid'],generation=req['generation'],source_sha256=hashlib.sha256(raw).hexdigest())
                begin=time.perf_counter()
                section,compact,details=convert_model(raw,atlas,req['animated'])
                result.update(details=details)
                if section is None:result.update(ok=True,empty=True)
                else:
                    opts.section=job/'compact-section.bin';opts.atlas=job/'compact-atlas.bin'
                    opts.section.write_bytes(section);opts.atlas.write_bytes(compact)
                    # Bound accumulated immutable resources; no overwrite of potentially cached assets.
                    assert cache_bytes<1024**3,'Native section resource cache reached 1 GiB; overlay retained'
                    report=builder.build(opts);stem=Path(report['mesh_path']).stem
                    assert re.fullmatch('section_[a-f0-9]{20}',stem)
                    if stem not in known_assets:
                        cache_bytes+=sum(p.stat().st_size for p in (a.out/stem).iterdir() if p.is_file());known_assets.add(stem)
                    dst=a.game/'natives/stm/mod/onimusha_mc/sections'/stem;dst.mkdir(parents=True,exist_ok=True)
                    for name,sha in report['files'].items():
                        src=a.out/stem/name;data=src.read_bytes();assert hashlib.sha256(data).hexdigest()==sha
                        target=dst/name
                        if target.exists():assert hashlib.sha256(target.read_bytes()).hexdigest()==sha
                        else:
                            temp=target.with_suffix(target.suffix+'.tmp');temp.write_bytes(data);os.replace(temp,target)
                    files=add_loader(a.game,stem,report['files'])
                    result.update(ok=True,asset_id=stem,triangles=report['triangles'],files=files,loader_version=LOADER_VERSION);built+=1
                result['seconds']=round(time.perf_counter()-begin,3)
            except Exception as e:
                if str(e)=='fully_transparent_model':result.update(ok=True,empty=True)
                else:result['error']=str(e);print('Native model failed: '+str(e),flush=True)
            # Result is the readiness fence, after every asset is completely written.
            publish(job,result)
        time.sleep(.05 if processed else .25)
    atomic_json(root/'worker.json',dict(host_pid=a.host_pid,pid=os.getpid(),state='host_exited',jobs=len(done),built=built))
    k.CloseHandle(handle)

if __name__=='__main__':main()
