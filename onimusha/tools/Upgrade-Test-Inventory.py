"""Fill stacks, replace golden apples, repair and enchant gear to the isolated test world while it is closed.

Default: read-only plan. --apply takes an exclusive Windows session.lock handle,
backs up and hash-verifies the whole world, then atomically changes only player NBT.
Dependency: G:/Onimusha_MC_mod/tools/nbt_packages (nbtlib 2.0.4).
"""
import argparse
import copy
import ctypes
from ctypes import wintypes
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path("G:/Onimusha_MC_mod")
sys.path.insert(0, str(ROOT / "tools/nbt_packages"))
import nbtlib

WORLD = ROOT / "runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2"
RECEIPT = ROOT / "logs/inventory-upgrade-20261008.json"
SUPPLIES = [('minecraft:lava_bucket', 1)]
RULES = json.loads((ROOT/'source/SkyCraft/fabric/build/test-artifacts/inventory-rules.json').read_text())

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()

def upgrade(item):
    if str(item['id'])=='minecraft:golden_apple':item['id']=nbtlib.String('minecraft:enchanted_golden_apple')
    rule=RULES['items'][str(item['id'])]
    item['count']=nbtlib.Int(rule['max_count'])
    if rule['damageable'] or rule['enchantments']:
        components=item.setdefault('components',nbtlib.Compound())
        if rule['damageable']:components['minecraft:damage']=nbtlib.Int(0)
        ench=components.setdefault('minecraft:enchantments',nbtlib.Compound())
        for name,level in rule['enchantments'].items():ench[name]=nbtlib.Int(level)
        # Infinity and Mending are mutually exclusive in the actual vanilla definition.
        if 'minecraft:infinity' in ench:ench.pop('minecraft:mending',None)

def plan():
    files=list((WORLD/'players/data').glob('*.dat'));assert len(files)==1
    path=files[0];original=nbtlib.load(path);updated=copy.deepcopy(original)
    assert 'Player' not in nbtlib.load(WORLD/'level.dat')['Data']
    inv=updated['Inventory'];slots=[int(i['Slot']) for i in inv]
    assert len(slots)==len(set(slots)) and all(0<=s<36 for s in slots)
    for i in inv:upgrade(i)
    for i in updated.get('equipment',{}).values():upgrade(i)
    for slot in range(36):
        if slot not in slots:
            item=nbtlib.Compound(Slot=nbtlib.Byte(slot),id=nbtlib.String('minecraft:lava_bucket'),count=nbtlib.Int(1))
            upgrade(item);inv.append(item)
    inv.sort(key=lambda i:int(i['Slot']))
    return path,original,updated,[s for s in range(36) if s not in slots]

def verify(original,updated,slots):
    inv=updated['Inventory'];assert [int(i['Slot']) for i in inv]==list(range(36))
    old={int(i['Slot']):i for i in original['Inventory']}
    for i in inv:
        slot=int(i['Slot']);expected=copy.deepcopy(old[slot]) if slot in old else nbtlib.Compound(Slot=nbtlib.Byte(slot),id=nbtlib.String('minecraft:lava_bucket'),count=nbtlib.Int(1))
        upgrade(expected);assert i==expected
    for name,i in original.get('equipment',{}).items():
        expected=copy.deepcopy(i);upgrade(expected);assert updated['equipment'][name]==expected
    a,b=copy.deepcopy(original),copy.deepcopy(updated)
    for key in ('Inventory','equipment'):a.pop(key,None);b.pop(key,None)
    assert a==b,'Non-inventory player data changed'


def apply():
    if RECEIPT.exists():
        raise RuntimeError("This grant already has a receipt; refusing to add it twice")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                  wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    # Share mode zero prevents taking the save while Minecraft holds its lock file.
    handle = kernel.CreateFileW(str(WORLD / "session.lock"), 0xC0000000, 0, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise RuntimeError(f"World is open or cannot be locked (Windows {ctypes.get_last_error()}); close MC normally first")
    try:
        path, original, updated, slots = plan()
        verify(original, updated, slots)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = ROOT / "runtime/test-backups" / ("before-inventory-upgrade-" + stamp)
        backup.mkdir(parents=True, exist_ok=False)
        manifest = []
        for item in sorted(WORLD.rglob("*")):
            if not item.is_file() or item == WORLD / "session.lock":
                continue
            relative = item.relative_to(WORLD)
            dest = backup / "world" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            before = sha(item)
            shutil.copy2(item, dest)
            assert sha(dest) == before == sha(item), "World changed during backup"
            manifest.append({"path": relative.as_posix(), "sha256": before})
        (backup / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        temporary = path.with_name(path.name + ".inventory-upgrade.tmp")
        assert not temporary.exists(), "Unexpected old temporary file"
        before_hash = sha(path)
        updated.save(temporary)
        verify(original, nbtlib.load(temporary), slots)
        os.replace(temporary, path)
        verify(original, nbtlib.load(path), slots)
        receipt = {"world": str(WORLD), "player_file": str(path), "backup": str(backup), "supplies": SUPPLIES,
                   "slots": slots, "before_sha256": before_hash,
                   "after_sha256": sha(path), "backup_files": len(manifest)}
        RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False))
    finally:
        kernel.CloseHandle(handle)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply:
        apply()
    else:
        path, original, updated, slots = plan()
        verify(original, updated, slots)
        print(json.dumps({"dry_run": True, "world": str(WORLD), "supplies": SUPPLIES,
                          "slots": slots, "all_36_slots_filled": True, "enchanted_apples": True, "unbreaking": 3, "bow_infinity": 1}))
