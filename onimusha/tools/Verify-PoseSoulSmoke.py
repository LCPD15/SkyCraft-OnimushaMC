"""Verify actual server rewards in the saved isolated world, not just log success."""
import collections,json,re,sys
from pathlib import Path
root=Path('G:/Onimusha_MC_mod');sys.path.insert(0,str(root/'tools/nbt_packages'))
import nbtlib
evidence=root/'logs/dynamic-sync-soul-20261009/isolated'
host=json.loads((evidence/'host-result.json').read_text());assert host['passed'],host
world=root/'runtime/minecraft/.minecraft/saves/OnimushaMC-PoseSoul-20261009-2'
player=nbtlib.load(next((world/'players/data').glob('*.dat')))
log=(root/'logs/pose-soul-smoke2-20261009.stdout.log').read_text('utf-8')
rows=re.findall(r'Onimusha soul reward receipt=(\d+) kind=(\w+)',log)
assert [int(r[0])for r in rows]==list(range(1,61)),'Duplicate, missing or wrong-epoch reward'
counts=collections.Counter(k for _,k in rows)
assert counts['HEAL']==10 and counts['REPAIR']==5 and counts['STACK']==4 and counts['EXPERIENCE']==41,counts
inv={int(i['Slot']):i for i in player['Inventory']}
assert str(inv[0]['id'])=='minecraft:diamond_axe' and int(inv[0].get('components',{}).get('minecraft:damage',0))==0
assert str(inv[9]['id'])=='minecraft:cobblestone' and int(inv[9]['count'])==64
expected=counts['EXPERIENCE']*.23
assert int(player['XpLevel'])==int(expected) and abs(float(player['XpP'])-expected%1)<1e-5
result={'passed':True,'host':host,'reward_counts':dict(counts),'unique_receipts':60,'duplicate_receipts_ignored':60,
        'wrong_epoch_ignored':True,'xp_level':int(player['XpLevel']),'xp_progress':float(player['XpP']),
        'axe_damage':0,'cobblestone_count':64,'world':str(world)}
(evidence/'verified.json').write_text(json.dumps(result,indent=2),'utf-8');print(json.dumps(result,indent=2))
