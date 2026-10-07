"""Merge the observed continuous stage-0 areas 14 -> 13. Offline, backed up, collision-safe.

This deliberately refuses nonempty target chunks, entities/POIs, structure data or external
chunk streams instead of guessing how to merge arbitrary worlds. Dry run is the default.
The earlier complete-world backup is required and verified before --apply.
"""
import argparse, copy, ctypes, hashlib, io, json, os, struct, sys, zlib
from ctypes import wintypes
from pathlib import Path

ROOT=Path('G:/Onimusha_MC_mod')
sys.path.insert(0,str(ROOT/'tools/nbt_packages'))
import nbtlib
WORLD=ROOT/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
DATA=WORLD/'dimensions/minecraft/overworld'
GAME=Path('F:/SteamLibrary/steamapps/common/OnimushaWotS/reframework/data')
LOG=ROOT/'logs/golem-fall-stream-20261007-185910'

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def read_region(p):
    data=p.read_bytes() if p.exists() else bytes(8192)
    records={}
    for i in range(1024):
        loc=int.from_bytes(data[i*4:i*4+4],'big');off=loc>>8
        if not off:continue
        size=int.from_bytes(data[off*4096:off*4096+4],'big')
        assert data[off*4096+4]==2,'Only ordinary zlib chunks supported'
        records[i]=(data[off*4096+5:off*4096+4+size],data[4096+i*4:4100+i*4])
    return records

def parse(record):return nbtlib.File.parse(io.BytesIO(zlib.decompress(record[0])))
def populated(n):
    for s in n.get('sections',[]):
        for p in s.get('block_states',{}).get('palette',[]):
            name=str(p['Name']) if isinstance(p,dict) else str(p)
            if name not in ('minecraft:air','minecraft:cave_air','minecraft:void_air'):return True
    return bool(n.get('block_entities',[]))

def encode(records):
    header=bytearray(8192);body=bytearray();sector=2
    for i,(compressed,stamp) in sorted(records.items()):
        payload=struct.pack('>I',len(compressed)+1)+b'\x02'+compressed
        count=(len(payload)+4095)//4096;assert count<256
        header[i*4:i*4+4]=((sector<<8)|count).to_bytes(4,'big')
        header[4096+i*4:4100+i*4]=stamp
        body+=payload+bytes(count*4096-len(payload));sector+=count
    return bytes(header+body)

def main(apply):
    assert not (GAME/'onimusha_mc_world_aliases.json').exists(),'Alias already installed; refusing repeat'
    backup=Path(json.loads((LOG/'backup.json').read_text(encoding='utf-8'))['backup'])
    for row in json.loads((backup/'manifest.json').read_text(encoding='utf-8')):
        assert sha(WORLD/row['path'])==row['sha256']==sha(backup/'world'/row['path']),'World differs from verified backup'
    tiles=json.loads((GAME/'onimusha_mc_worlds.json').read_text(encoding='utf-8-sig'))
    assert tiles['stage:0:area:14']['x']-tiles['stage:0:area:13']['x']==8192
    assert tiles['stage:0:area:14']['z']==tiles['stage:0:area:13']['z']==0
    changes={};moves=[]
    # The verified source tile occupies MC chunks 3840..4351. No arbitrary dimension rewriting.
    for kind in ('entities','poi'):
        for p in (DATA/kind).glob('*.mca'):
            rx=int(p.name.split('.')[1])
            if not 120<=rx<136:continue
            for record in read_region(p).values():
                n=parse(record)
                assert not n.get('Entities',[]) and not n.get('Sections',{}),f'Nonempty {kind} requires explicit migration: {p}'
    for src in (DATA/'region').glob('*.mca'):
        rx=int(src.name.split('.')[1])
        if not 120<=rx<136:continue
        source=read_region(src)
        for i,record in list(source.items()):
            n=parse(record)
            if not populated(n):continue
            assert not n.get('structures',{}).get('starts',{}) and not n.get('structures',{}).get('References',{}),'Unexpected structures'
            assert not n.get('block_entities',[]) and not n.get('block_ticks',[]) and not n.get('fluid_ticks',[]),'Complex blocks/ticks require migration'
            cx,cz=int(n['xPos']),int(n['zPos']);tx=cx-512
            dst=DATA/'region'/f'r.{tx//32}.{cz//32}.mca'
            target=changes.setdefault(dst,read_region(dst));slot=tx%32+32*(cz%32)
            assert slot not in target or not populated(parse(target[slot])),'Nonempty target chunk; refusing overwrite'
            moved=copy.deepcopy(n);moved['xPos']=nbtlib.Int(tx)
            out=io.BytesIO();moved.write(out)
            target[slot]=(zlib.compress(out.getvalue()),record[1]);del source[i]
            moves.append({'source_chunk':[cx,cz],'target_chunk':[tx,cz]})
        changes[src]=source
    receipt={'backup':str(backup),'moves':moves,'alias':{'stage:0:area:14':'stage:0:area:13'},'inventory_unchanged':True}
    print(json.dumps(receipt))
    if not apply:return
    assert moves,'No chunks to migrate; refusing ambiguous repeat'
    # Backups were verified; prepare every complete replacement before changing any file.
    replacements={p:encode(records) for p,records in changes.items()}
    for p,blob in replacements.items():
        temp=p.with_suffix('.merge.tmp');assert not temp.exists();temp.write_bytes(blob)
        assert read_region(temp)==changes[p]
    for p in replacements:os.replace(p.with_suffix('.merge.tmp'),p)
    alias=GAME/'onimusha_mc_world_aliases.json';assert not alias.exists()
    temp=alias.with_suffix('.tmp');temp.write_text(json.dumps(receipt['alias'],indent=2),encoding='utf-8');os.replace(temp,alias)
    receipt['after_sha256']={str(p):sha(p) for p in replacements}
    (LOG/'area-merge.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--apply',action='store_true');args=ap.parse_args()
    k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE];k.CreateFileW.restype=wintypes.HANDLE;k.CloseHandle.argtypes=[wintypes.HANDLE]
    h=k.CreateFileW(str(WORLD/'session.lock'),0xC0000000,0,None,3,0x80,None)
    if h==ctypes.c_void_p(-1).value:raise RuntimeError('World must be closed')
    try:main(args.apply)
    finally:k.CloseHandle(h)
