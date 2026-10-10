"""Install the protocol-16 NPC damage update without resetting live tuning/configuration.

Run only after both the game and its Minecraft instance have saved and exited.
Keeps a rollback copy and verifies the existing world against this session's backup.
"""
import hashlib
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

root = Path(r'G:\Onimusha_MC_mod')
repo = root / 'source/SkyCraft'
game = Path(r'F:\SteamLibrary\steamapps\common\OnimushaWotS')
logs = root / 'logs/npc-incoming-20261010'
manifest_path = root / 'runtime/deployment.json'
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()

live = subprocess.check_output(['powershell', '-NoProfile', '-Command',
    "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'OnimushaWotS.exe' -or "
    "($_.Name -eq 'java.exe' -and $_.CommandLine -like '*Onimusha_MC_mod*runtime*minecraft*launch-dev.args*') } "
    "| Select-Object -ExpandProperty ProcessId"], text=True).strip()
if live:
    raise SystemExit('Close Onimusha and its MC instance before installing: ' + live)
manifest = json.loads(manifest_path.read_text('utf-8-sig'))
assert Path(manifest['GameRoot']) == game
world = json.loads((logs / 'world-backup.json').read_text('utf-8-sig'))
for entry in world['files']:
    assert hash_file(Path(world['source']) / entry['path']) == entry['sha256'], 'World changed after backup'

names = ['onimusha_mc.lua', 'onimusha_enemy_hit.lua', 'onimusha_guard_probe.lua',
    'onimusha_combat_inventory.lua', 'onimusha_native_blocks.lua', 'onimusha_native_models.lua',
    'onimusha_soul.lua', 'onimusha_npc_damage.lua']
entries = {
    'reframework/plugins/OnimushaMC.dll': root / 'build/native/Release/OnimushaMC.dll',
    'reframework/autorun/onimusha_loader.lua': repo / 'onimusha/adapter/onimusha_loader.lua',
    **{'reframework/data/onimusha_mc/scripts/' + n: repo / 'onimusha/adapter' / n for n in names},
}
jar = repo / 'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar'
jar_target = root / 'runtime/minecraft/.minecraft/mods' / jar.name
for source in [*entries.values(), jar]:
    assert source.is_file(), str(source)

stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
backup = root / 'runtime/test-backups' / ('npc-incoming-install-' + stamp)
backup.mkdir()
shutil.copy2(manifest_path, backup / 'deployment.json')
config = game / 'reframework/data/onimusha_mc_config.json'
config_hash = hash_file(config)
shutil.copy2(config, backup / config.name)
replacements = [(src, game / relative, backup / 'game' / relative) for relative, src in entries.items()]
replacements.append((jar, jar_target, backup / 'minecraft-mods' / jar.name))
for src, dst, old in replacements:
    if dst.exists():
        old.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dst, old)
installed = []
try:
    for src, dst, old in replacements:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        installed.append((dst, old))
        assert hash_file(src) == hash_file(dst), str(dst)
    for relative in entries:
        relative = relative.replace('/', '\\')
        record = next((e for e in manifest['Entries'] if e['Relative'] == relative), None)
        if record is None:
            record = dict(Relative=relative, OriginalBackup=None)
            manifest['Entries'].append(record)
        record['InstalledSHA256'] = hash_file(game / relative)
    # These read-only probes were explicitly disarmed after collection; record that state.
    for name in ['onimusha_combat_inventory_control.json', 'onimusha_npc_hit_probe_control.json']:
        relative = 'reframework\\data\\' + name
        assert json.loads((game / relative).read_text('utf-8-sig'))['enabled'] is False
        next(e for e in manifest['Entries'] if e['Relative'] == relative)['InstalledSHA256'] = hash_file(game / relative)
    assert hash_file(config) == config_hash, 'Tuning must be preserved'
    for e in manifest['Entries']:
        assert hash_file(game / e['Relative']) == e['InstalledSHA256'], e['Relative']
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), 'utf-8')
except Exception:
    for dst, old in reversed(installed):
        if old.exists():
            shutil.copy2(old, dst)
    shutil.copy2(backup / 'deployment.json', manifest_path)
    raise
receipt = dict(installed_at=stamp, protocol=16, backup=str(backup), game_manifest_files=len(manifest['Entries']),
    config_unchanged=True, world_files=len(world['files']), processes_closed=True,
    files=[dict(path=str(dst), sha256=hash_file(dst)) for _, dst, _ in replacements])
(logs / 'installation.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
print(json.dumps({k: v for k, v in receipt.items() if k != 'files'}, ensure_ascii=False))
