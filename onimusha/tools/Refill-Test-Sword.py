"""Requested 2026-10-10: top up existing stacks and add one compatible enchanted diamond sword.

Closed-world operation; exclusive session lock, whole-world backup and atomic player replacement.
Default is a read-only plan; --apply is idempotent through its receipt.
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
import zipfile

ROOT = Path('G:/Onimusha_MC_mod')
WORLD = ROOT/'runtime/minecraft/.minecraft/saves/OnimushaMC-XYZ-v2'
RECEIPT = ROOT/'logs/death-dither-20261010/inventory-sword.json'
sys.path.insert(0, str(ROOT/'tools/nbt_packages'))
import nbtlib

ENCHANTMENTS = {'minecraft:sharpness': 5, 'minecraft:sweeping_edge': 3,
                'minecraft:fire_aspect': 2, 'minecraft:unbreaking': 3, 'minecraft:mending': 1}

def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def validate_enchantments():
    with zipfile.ZipFile(ROOT/'build/gradle-cache/caches/fabric-loom/26.3/minecraft-common.jar') as z:
        def expand(value, kind):
            if isinstance(value, list):
                return set().union(*(expand(v, kind) for v in value))
            if isinstance(value, dict):
                value = value['id']
            if not value.startswith('#'):
                return {value}
            namespace, name = value[1:].split(':')
            return expand(json.loads(z.read(f'data/{namespace}/tags/{kind}/{name}.json'))['values'], kind)
        for name, level in ENCHANTMENTS.items():
            namespace, leaf = name.split(':')
            d = json.loads(z.read(f'data/{namespace}/enchantment/{leaf}.json'))
            assert level == d['max_level']
            assert 'minecraft:diamond_sword' in expand(d['supported_items'], 'item')
            conflicts = expand(d.get('exclusive_set', []), 'enchantment') & ENCHANTMENTS.keys()
            assert not (conflicts - {name}), (name, conflicts)

def main(apply):
    validate_enchantments()
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
        ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(WORLD/'session.lock'), 0xC0000000, 0, None, 3, 0x80, None)
    assert handle != ctypes.c_void_p(-1).value, 'Minecraft world is still open'
    try:
        assert not RECEIPT.exists(), 'Already applied; inspect existing receipt'
        paths = list((WORLD/'players/data').glob('*.dat')); assert len(paths) == 1
        path = paths[0]; original = nbtlib.load(path); updated = copy.deepcopy(original)
        assert 'Player' not in nbtlib.load(WORLD/'level.dat')['Data']
        rules = json.loads((ROOT/'source/SkyCraft/fabric/build/test-artifacts/inventory-rules.json').read_text())['items']
        inv = updated['Inventory']; slots = {int(i['Slot']) for i in inv}
        assert len(slots) == len(inv) and all(0 <= s < 36 for s in slots)
        free = [s for s in range(36) if s not in slots]
        assert free, 'No free slot; preserve all existing items'
        changes = []
        for item in inv:
            item_id = str(item['id']); before = int(item['count'])
            maximum = int(item.get('components', {}).get('minecraft:max_stack_size', rules[item_id]['max_count']))
            assert 1 <= before <= maximum <= 99
            item['count'] = nbtlib.Int(maximum)
            if before != maximum:
                changes.append({'slot': int(item['Slot']), 'id': item_id, 'before': before, 'after': maximum})
        sword = nbtlib.Compound(Slot=nbtlib.Byte(free[0]), id=nbtlib.String('minecraft:diamond_sword'),
            count=nbtlib.Int(1), components=nbtlib.Compound({'minecraft:damage': nbtlib.Int(0),
                'minecraft:enchantments': nbtlib.Compound({k: nbtlib.Int(v) for k,v in ENCHANTMENTS.items()})}))
        inv.append(sword); inv.sort(key=lambda i: int(i['Slot']))
        # No non-inventory state or existing item components may change.
        a, b = copy.deepcopy(original), copy.deepcopy(updated)
        a.pop('Inventory'); b.pop('Inventory'); assert a == b
        old = {int(i['Slot']): i for i in original['Inventory']}
        for item in inv:
            slot = int(item['Slot'])
            if slot in old:
                a, b = copy.deepcopy(item), copy.deepcopy(old[slot]); a.pop('count'); b.pop('count'); assert a == b
        receipt = {'applied': apply, 'refilled_stacks': changes, 'new_sword_slot': free[0],
                   'enchantments': ENCHANTMENTS, 'world': str(WORLD)}
        if apply:
            backup = ROOT/'runtime/test-backups'/('inventory-sword-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
            backup.mkdir(parents=True, exist_ok=False); hashes = {}
            for p in WORLD.rglob('*'):
                if not p.is_file() or p.name == 'session.lock': continue
                rel = p.relative_to(WORLD); dest = backup/'world'/rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                hashes[str(rel)] = sha(p); shutil.copy2(p, dest); assert sha(dest) == hashes[str(rel)] == sha(p)
            (backup/'world-sha256.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
            temp = path.with_suffix('.refill-sword.tmp'); assert not temp.exists()
            updated.save(temp); assert nbtlib.load(temp) == updated
            os.replace(temp, path); assert nbtlib.load(path) == updated
            receipt.update(backup=str(backup), world_files=len(hashes), player_sha256=sha(path))
            RECEIPT.write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding='utf-8')
        print(json.dumps(receipt, ensure_ascii=False))
    finally:
        kernel.CloseHandle(handle)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    main(parser.parse_args().apply)
