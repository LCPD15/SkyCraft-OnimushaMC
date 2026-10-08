"""Explicit F10-off single-object cold-load diagnostic for Onimusha TDB82.

Creates only immutable private asset aliases, never edits original game assets.
Every visible probe is removed before the next is requested. No combat/physics.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, time, uuid

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write(path, value):
    temp=path.with_suffix('.probe.tmp')
    temp.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
    for attempt in range(20):
        try: os.replace(temp,path); return
        except PermissionError:
            if attempt==19: raise
            time.sleep(.025)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--count',type=int,default=3)
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args();assert 1<=a.count<=5
    project=Path('G:/Onimusha_MC_mod')
    game=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS')
    data=game/'reframework/data'
    control=data/'onimusha_native_object_probe_control.json'
    status=data/'onimusha_native_object_probe_status.json'
    config=read(data/'onimusha_mc_config.json')
    assert config['enable_native_section_rendering'] is False
    a.out.mkdir(parents=True,exist_ok=True)
    records=[]
    def wait(request,predicate,timeout=12):
        start=time.monotonic();samples=[]
        write(control,request)
        while time.monotonic()-start<timeout:
            time.sleep(.1)
            row=read(status)
            if row.get('id')!=request['id']:continue
            samples.append(dict(seconds=round(time.monotonic()-start,3),status=row))
            write(a.out/(request['id']+'.json'),samples)
            assert not row.get('error'),row
            if predicate(row):return samples[-1]
        raise RuntimeError('Probe timed out: '+request['id'])
    def remove():
        return wait(dict(enabled=True,action='remove',id='remove-'+uuid.uuid4().hex),
                    lambda r:r.get('destroyed') is True)
    try:
        remove()
        assets=game/'natives/stm/mod/onimusha_mc/sections'
        source=assets/'section_2de7d11826ea95bac7e0'
        for _ in range(a.count):
            asset='section_'+uuid.uuid4().hex[:20];folder=assets/asset
            folder.mkdir()
            for suffix in ('.mesh.260209350','.mdf2.51'):
                shutil.copy2(source/(source.name+suffix),folder/(asset+suffix))
            output=subprocess.run(['dotnet',str(project/'build/native-model-loader/NativeModelLoader.dll'),
                str(project/'downloads/re-collider-reference/rszoniwots_reelib_fixed.json'),asset,str(folder)],
                check=True,capture_output=True,text=True)
            request=dict(enabled=True,id='cold-'+uuid.uuid4().hex,action='render_userdata',asset_id=asset,
                         section_min=dict(x=-.5,y=-.5,z=-.5))
            result=wait(request,lambda r:r.get('ready') is True)
            record=dict(asset=asset,loader=json.loads(output.stdout),ready=result,removed=remove())
            records.append(record);write(a.out/'summary.json',records)
            print(json.dumps(dict(asset=asset,ready_seconds=result['seconds'],removed=True)),flush=True)
    finally:
        try:remove()
        finally:
            write(control,dict(enabled=False,id='cold-series-finished'))
            manifest_path=project/'runtime/deployment.json';manifest=read(manifest_path)
            for row in manifest['Entries']:
                if row['Relative']=='reframework\\data\\onimusha_native_object_probe_control.json':
                    row['InstalledSHA256']=hashlib.sha256(control.read_bytes()).hexdigest().upper()
            write(manifest_path,manifest)

if __name__=='__main__':main()
