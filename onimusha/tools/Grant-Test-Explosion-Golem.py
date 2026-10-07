"""Add explosion and iron-golem test supplies to the isolated test world while it is closed.

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
RECEIPT = ROOT / "logs/explosion-golem-grant-20261007.json"
SUPPLIES = ([('minecraft:tnt', 64)] * 3 + [('minecraft:end_crystal', 64), ('minecraft:obsidian', 64),
            ('minecraft:flint_and_steel', 1)] + [('minecraft:iron_block', 64)] * 4
            + [('minecraft:carved_pumpkin', 64)] * 2)

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()

def plan():
    files = list((WORLD / "players/data").glob("*.dat"))
    if len(files) != 1:
        raise RuntimeError("Expected exactly one player in this isolated test world")
    path = files[0]
    nbt = nbtlib.load(path)
    inv = nbt["Inventory"]
    occupied = [int(item["Slot"]) for item in inv]
    if len(occupied) != len(set(occupied)):
        raise RuntimeError("Duplicate inventory slots; refusing modification")
    free = [slot for slot in range(9, 36) if slot not in occupied]
    if len(free) < len(SUPPLIES):
        raise RuntimeError(f"Need {len(SUPPLIES)} empty main inventory slots, found {len(free)}; existing items will not be replaced")
    level = nbtlib.load(WORLD / "level.dat")
    if "Player" in level["Data"]:
        raise RuntimeError("Embedded player data also exists; must resolve authoritative save first")
    updated = copy.deepcopy(nbt)
    for slot, (item, count) in zip(free, SUPPLIES):
        updated["Inventory"].append(nbtlib.Compound({
            "Slot": nbtlib.Byte(slot), "id": nbtlib.String(item), "count": nbtlib.Int(count),
        }))
    return path, nbt, updated, free[:len(SUPPLIES)]

def verify(original, updated, slots):
    previous = {int(i["Slot"]): i.snbt() for i in original["Inventory"]}
    after = {int(i["Slot"]): i for i in updated["Inventory"]}
    assert set(after) == set(previous) | set(slots)
    assert all(after[s].snbt() == item for s, item in previous.items())
    assert all(str(after[s]["id"]) == item and int(after[s]["count"]) == count for s, (item, count) in zip(slots, SUPPLIES))
    a, b = copy.deepcopy(original), copy.deepcopy(updated)
    del a["Inventory"], b["Inventory"]
    assert a.snbt() == b.snbt(), "Non-inventory player data changed"

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
        backup = ROOT / "runtime/test-backups" / ("before-explosion-golem-" + stamp)
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
        temporary = path.with_name(path.name + ".explosion-golem.tmp")
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
                          "slots": slots, "existing_items_unchanged": True}))
