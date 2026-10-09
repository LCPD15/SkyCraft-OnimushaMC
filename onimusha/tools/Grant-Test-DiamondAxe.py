"""One requested diamond axe; move one spare stack to Ender storage only if necessary.
Closed original test world only, exclusive lock, full backup, no discarded items.
"""
import argparse,copy,ctypes,hashlib,json,os,shutil,sys
from ctypes import wintypes
from datetime import datetime
from pathlib import Path
ROOT=Path('G:/Onimusha_MC_mod')
sys.path.insert(0,str(ROOT/'tools/nbt_packages'))
import nbtlib
WORLD=ROOT/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
RECEIPT=ROOT/'logs/dynamic-sync-soul-20261009/diamond-axe.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(apply):
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateFileW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    kernel.CreateFileW.restype=wintypes.HANDLE;kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    handle=kernel.CreateFileW(str(WORLD/'session.lock'),0xC0000000,0,None,3,0x80,None)
    assert handle!=ctypes.c_void_p(-1).value,'World is still open'
    try:
        assert not RECEIPT.exists(),'Already granted; inspect receipt instead of granting twice'
        files=list((WORLD/'players/data').glob('*.dat'));assert len(files)==1
        path=files[0];original=nbtlib.load(path);updated=copy.deepcopy(original)
        assert 'Player' not in nbtlib.load(WORLD/'level.dat')['Data']
        inv=updated['Inventory'];occupied={int(i['Slot'])for i in inv};assert len(occupied)==len(inv)
        free=[s for s in range(9,36)if s not in occupied]+[s for s in range(9)if s not in occupied]
        moved=None
        if free:slot=free[0]
        else:
            # Preserve every item: relocate one of the four spare apple stacks.
            candidates=[i for i in inv if str(i['id'])=='minecraft:enchanted_golden_apple' and int(i['Slot'])>=9]
            assert len(candidates)>=2,'No safe spare stack to relocate'
            spare=candidates[-1];slot=int(spare['Slot']);ender=nbtlib.List[nbtlib.Compound](updated['EnderItems']);updated['EnderItems']=ender
            ender_free=[s for s in range(27)if s not in {int(i['Slot'])for i in ender}];assert ender_free
            moved={'item':str(spare['id']),'count':int(spare['count']),'from_inventory_slot':slot,'to_ender_slot':ender_free[0]}
            inv.remove(spare);spare['Slot']=nbtlib.Byte(ender_free[0]);ender.append(spare)
        axe=nbtlib.Compound(Slot=nbtlib.Byte(slot),id=nbtlib.String('minecraft:diamond_axe'),count=nbtlib.Int(1),
            components=nbtlib.Compound({'minecraft:damage':nbtlib.Int(0),'minecraft:enchantments':nbtlib.Compound({'minecraft:unbreaking':nbtlib.Int(3)})}))
        inv.append(axe);inv.sort(key=lambda x:int(x['Slot']))
        # Item multiset, excluding only the explicitly added axe, must be exact.
        def items(n):
            result=[]
            for i in list(n['Inventory'])+list(n['EnderItems']):
                a=copy.deepcopy(i);a.pop('Slot');result.append(a.snbt())
            return sorted(result)
        check=copy.deepcopy(updated);check['Inventory'].remove(axe);assert items(check)==items(original)
        a,b=copy.deepcopy(original),copy.deepcopy(updated)
        for k in ('Inventory','EnderItems'):a.pop(k);b.pop(k)
        assert a==b,'Non-inventory data changed'
        result={'item':'minecraft:diamond_axe','count':1,'unbreaking':3,'inventory_slot':slot,'relocated':moved,'applied':apply}
        if apply:
            backup=ROOT/'runtime/test-backups'/('pose-soul-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
            backup.mkdir(parents=True,exist_ok=False);hashes={}
            for p in WORLD.rglob('*'):
                if not p.is_file() or p.name=='session.lock':continue
                rel=p.relative_to(WORLD);dest=backup/'world'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
                hashes[str(rel)]=sha(p);shutil.copy2(p,dest);assert sha(dest)==hashes[str(rel)]==sha(p)
            (backup/'world-sha256.json').write_text(json.dumps(hashes,indent=2),'utf-8')
            temp=path.with_suffix('.diamond-axe.tmp');assert not temp.exists();updated.save(temp)
            assert nbtlib.load(temp)==updated;os.replace(temp,path)
            assert nbtlib.load(path)==updated
            result.update(backup=str(backup),world_files=len(hashes),player_file=str(path),sha256=sha(path))
            RECEIPT.parent.mkdir(parents=True,exist_ok=True);RECEIPT.write_text(json.dumps(result,indent=2,ensure_ascii=False),'utf-8')
        print(json.dumps(result,ensure_ascii=False))
    finally:kernel.CloseHandle(handle)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');main(p.parse_args().apply)
