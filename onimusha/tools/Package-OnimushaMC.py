"""Create local development archives without game binaries, schemas or account data."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--project-root', type=Path, default=Path(r'G:\Onimusha_MC_mod'))
p.add_argument('--native-dll', type=Path, help='Explicit frozen native candidate; does not install it.')
p.add_argument('--fabric-jar', type=Path, help='Explicit frozen Fabric candidate; does not install it.')
p.add_argument('--archive-tag', default='', help='Separate candidate archives; preserve previous packages.')
a = p.parse_args()
if a.archive_tag and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,63}', a.archive_tag):
    p.error('archive-tag must contain only letters, digits and hyphens, up to 64 characters')
root = a.project_root.resolve()
repo = root / 'source' / 'SkyCraft'
dist = root / 'dist'
dist.mkdir(parents=True, exist_ok=True)
suffix = '-' + a.archive_tag if a.archive_tag else ''
archive_stem = 'OnimushaMC-0.1.0-dev' + suffix
release = {
    'reframework/plugins/OnimushaMC.dll': a.native_dll or root / 'build/native/Release/OnimushaMC.dll',
    'reframework/autorun/onimusha_loader.lua': repo / 'onimusha/adapter/onimusha_loader.lua',
    **{'reframework/data/onimusha_mc/scripts/' + name: repo / 'onimusha/adapter' / name
       for name in ('onimusha_mc.lua','onimusha_enemy_hit.lua','onimusha_guard_probe.lua','onimusha_combat_inventory.lua','onimusha_native_blocks.lua','onimusha_native_models.lua','onimusha_soul.lua')},
    'reframework/data/onimusha_enemy_hit_control.json': repo / 'onimusha/config/onimusha_enemy_hit_control.json',
    'reframework/data/onimusha_explosion_control.json': repo / 'onimusha/config/onimusha_explosion_control.json',
    'reframework/data/onimusha_mc_config.json': repo / 'onimusha/config/onimusha_mc_config.json',
    'minecraft-mods/skycraft-onimusha-0.1.0-dev.jar': a.fabric_jar or repo / 'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar',
    'README.md': repo / 'README.md',
    'LICENSE': repo / 'LICENSE',
    'THIRD-PARTY-NOTICES.txt': repo / 'onimusha/native/THIRD-PARTY-NOTICES.txt',
    'docs/ONIMUSHA-VALIDATION.md': repo / 'docs/ONIMUSHA-VALIDATION.md',
    'docs/ONIMUSHA-RESUME.md': repo / 'docs/ONIMUSHA-RESUME.md',
    'docs/ONIMUSHA-ENGINE-INTEGRATION.md': repo / 'docs/ONIMUSHA-ENGINE-INTEGRATION.md',
    'docs/ONIMUSHA-OVERNIGHT-RESEARCH.md': repo / 'docs/ONIMUSHA-OVERNIGHT-RESEARCH.md',
    'docs/ONIMUSHA-RENDER-RESEARCH.md': repo / 'docs/ONIMUSHA-RENDER-RESEARCH.md',
    'docs/ONIMUSHA-COLLISION-PATH-RESEARCH.md': repo / 'docs/ONIMUSHA-COLLISION-PATH-RESEARCH.md',
    'docs/ONIMUSHA-DAMAGE-BALANCE.md': repo / 'docs/ONIMUSHA-DAMAGE-BALANCE.md',
    'docs/ONIMUSHA-EXECUTION-RESEARCH.md': repo / 'docs/ONIMUSHA-EXECUTION-RESEARCH.md',
    'docs/ONIMUSHA-COMBAT-RESEARCH.md': repo / 'docs/ONIMUSHA-COMBAT-RESEARCH.md',
    'docs/ONIMUSHA-GUARD-RESEARCH.md': repo / 'docs/ONIMUSHA-GUARD-RESEARCH.md',
    'docs/ONIMUSHA-EXPLOSION.md': repo / 'docs/ONIMUSHA-EXPLOSION.md',
    'docs/ONIMUSHA-MOB-TERRAIN.md': repo / 'docs/ONIMUSHA-MOB-TERRAIN.md',
    'docs/ONIMUSHA-DYNAMIC-TERRAIN.md': repo / 'docs/ONIMUSHA-DYNAMIC-TERRAIN.md',
    'docs/ONIMUSHA-HOT-RELOAD.md': repo / 'docs/ONIMUSHA-HOT-RELOAD.md',
    'docs/onimusha-bindings.md': repo / 'docs/onimusha-bindings.md',
    'docs/NATIVE_API.md': repo / 'onimusha/native/NATIVE_API.md',
    'docs/RESTORATION.md': repo / 'onimusha/adapter/RESTORATION.md',
    'docs/MINECRAFT-LAUNCH.md': repo / 'onimusha/launcher/README.md',
    'diagnostic-presets/onimusha_mc_config.stage-A.json': repo / 'onimusha/config/onimusha_mc_config.stage-A.json',
    'diagnostic-presets/onimusha_mc_config.stage-B.json': repo / 'onimusha/config/onimusha_mc_config.stage-B.json',
    'diagnostic-presets/onimusha_mc_config.stage-C.json': repo / 'onimusha/config/onimusha_mc_config.stage-C.json',
}
for name, path in release.items():
    if not path.is_file(): raise FileNotFoundError(f'{name}: {path}')
hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in release.items()}
source_identity = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'worktree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True).strip()),
    'archive_tag': a.archive_tag,
    'packaging_installs_files': False,
}
notice = '''OnimushaMC 0.1.0-dev — 开发测试包 / Development package

MOD制作：LCPD15/LCPD拉灯
Original SkyCraft: chasmlol (MIT).

仅适用于鬼武者 OnimushaWotS / ONIMUSHA_WOTS。其他 RE 游戏需要单独适配。
3C、背包、相机UI跟随、F10恢复、百分比血量、治疗、格挡声音和通用敌人受击已通过阶段实测。
MC爆炸桥接与铁傀儡选敌已加入，当前实测状态见 docs/ONIMUSHA-EXPLOSION.md。
爆炸使用原版油桶资源与原始参数；MC负责方块破坏和玩家自伤，避免重复结算。
原生NPC的MC方块碰撞/寻路、真实RE深度/光照、处决仍未完成。
3C, inventory, camera UI tracking, F10 restoration, percentage HP, healing,
guard sounds and generic native enemy hit feedback passed staged live tests.
Native oil-barrel explosions and iron-golem proxy targeting are implemented;
consult docs/ONIMUSHA-EXPLOSION.md for the exact validation boundary.
Native explosions retain stock oil-barrel tuning; MC owns block destruction and self damage.
Native NPC block collision/navigation, real RE depth/lighting and executions remain unfinished.
Read docs/ONIMUSHA-VALIDATION.md before enabling takeover.

退出鬼武者后，将 reframework/ 复制到游戏目录。JAR 放入隔离 Minecraft
配置的 mods/，不要将 minecraft-mods/ 解压进鬼武者目录。
Copy reframework/ into OnimushaWotS after exiting the game.
When upgrading old packages, move old OnimushaMC payload autorun files out first;
onimusha_loader.lua must be the only project autorun (see hot-reload notes).
Install the JAR from minecraft-mods/ into the isolated Minecraft profile's mods/.
Do not extract minecraft-mods/ into the Onimusha game directory.
配置默认使用关闭接管的只读阶段 A，新增原生碰撞对象和血量修改测试均停用。
按照分阶段验证记录恢复功能。本包不含实验 RCOL、原版游戏文件、MC安装或账号信息。
Configuration defaults to read-only stage A. Preserve tuning preferences, but
disable native collider allocation and health mutation tests. Follow the staged
validation record; this package does not include experimental RCOL assets.
This archive contains no original game files, Minecraft installation or credentials.
'''
if a.archive_tag:
    notice += '\n本包为独立候选快照，打包不会部署或继承旧版本游戏验收。\nSeparate candidate snapshot; packaging does not install it or inherit earlier live acceptance.\n'
with zipfile.ZipFile(dist / (archive_stem + '.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
    for name, path in release.items(): z.write(path, name)
    z.writestr('INSTALL.txt', notice)
    z.writestr('SHA256.json', json.dumps(hashes, ensure_ascii=False, indent=2) + '\n')
    z.writestr('SOURCE-IDENTITY.json', json.dumps(source_identity, indent=2) + '\n')

tracked = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=repo)
files = sorted(set(x.decode('utf-8') for x in tracked.split(b'\0') if x))
game_resource = re.compile(r'\.(?:pak|tex|mesh|scn|pfb|mdf2|mot|motlist|chain|chain2|rcol|user|vfx|efx)(?:\.\d+)?$', re.IGNORECASE)
owned_assets = {'onimusha/assets/natives/stm/mod/onimusha_mc/unit_box.rcol.37'}
with zipfile.ZipFile(dist / (archive_stem + '-source.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
    for name in files:
        path = (repo / name).resolve()
        if not path.is_relative_to(repo) or not path.is_file(): continue
        if any(x in path.parts for x in ('.git', 'bin', 'obj', 'build', '.gradle', '.minecraft', 'logs')): continue
        if name.endswith(('.pid', '.log')): continue
        if path.suffix.lower() == '.dmp': continue
        if game_resource.search(name) and name not in owned_assets: continue
        if path.name.startswith(('onimusha_mc_status', 'onimusha_mc_worlds', 'onimusha_mc_session', 'onimusha_mc_probe')) and path.suffix.lower()=='.json': continue
        if path.suffix.lower() == '.json' and (path.name.lower().startswith('rsz') or path.name.lower() == 'oniws.json' or any(part.lower() in ('schemas', 'rsz-schema', 'rsz-schemas') for part in path.parts)): continue
        z.write(path, 'SkyCraft-OnimushaMC/' + name)
    z.writestr('SOURCE-IDENTITY.json', json.dumps(source_identity, indent=2) + '\n')

(dist / ('MOD介绍_Introduction' + suffix + '.txt')).write_text(notice, encoding='utf-8')
(dist / ('build-hashes' + suffix + '.json')).write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
for path in (dist / (archive_stem + '.zip'), dist / (archive_stem + '-source.zip')):
    print(json.dumps({'file': str(path), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}))
