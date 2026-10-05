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
a = p.parse_args()
root = a.project_root.resolve()
repo = root / 'source' / 'SkyCraft'
dist = root / 'dist'
dist.mkdir(parents=True, exist_ok=True)
release = {
    'reframework/plugins/OnimushaMC.dll': root / 'build/native/Release/OnimushaMC.dll',
    'reframework/autorun/onimusha_mc.lua': repo / 'onimusha/adapter/onimusha_mc.lua',
    'reframework/data/onimusha_mc_config.json': repo / 'onimusha/config/onimusha_mc_config.json',
    'minecraft-mods/skycraft-onimusha-0.1.0-dev.jar': repo / 'fabric/build/libs/skycraft-onimusha-0.1.0-dev.jar',
    'README.md': repo / 'README.md',
    'LICENSE': repo / 'LICENSE',
    'THIRD-PARTY-NOTICES.txt': repo / 'onimusha/native/THIRD-PARTY-NOTICES.txt',
    'docs/ONIMUSHA-VALIDATION.md': repo / 'docs/ONIMUSHA-VALIDATION.md',
    'docs/ONIMUSHA-RESUME.md': repo / 'docs/ONIMUSHA-RESUME.md',
    'docs/onimusha-bindings.md': repo / 'docs/onimusha-bindings.md',
    'docs/NATIVE_API.md': repo / 'onimusha/native/NATIVE_API.md',
    'docs/MINECRAFT-LAUNCH.md': repo / 'onimusha/launcher/README.md',
    'diagnostic-presets/onimusha_mc_config.stage-A.json': repo / 'onimusha/config/onimusha_mc_config.stage-A.json',
    'diagnostic-presets/onimusha_mc_config.stage-B.json': repo / 'onimusha/config/onimusha_mc_config.stage-B.json',
    'diagnostic-presets/onimusha_mc_config.stage-C.json': repo / 'onimusha/config/onimusha_mc_config.stage-C.json',
}
for name, path in release.items():
    if not path.is_file(): raise FileNotFoundError(f'{name}: {path}')
hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in release.items()}
notice = '''OnimushaMC 0.1.0-dev — 开发测试包 / Development package

MOD制作：LCPD15/LCPD拉灯
Original SkyCraft: chasmlol (MIT).

仅适用于鬼武者 OnimushaWotS / ONIMUSHA_WOTS。其他 RE 游戏需要单独适配。
本版本仍在开发中：HUD、角色绘制、首次朝向同步和普通接管恢复已有实景证据；
背包点击仍有居中问题，完整3C、战斗、血量往返及建造碰撞尚未完成实景验收。
请先阅读 docs/ONIMUSHA-VALIDATION.md，独立 IPC/MC/GPU 测试不能替代游戏验收。
Only OnimushaWotS / ONIMUSHA_WOTS is targeted. Other RE games require separate
adapters. HUD/character rendering, initial rotation and ordinary takeover release
have live evidence. Inventory clicks remain unresolved; full 3C, combat, health
round trips and building collision still require in-game acceptance. Read
docs/ONIMUSHA-VALIDATION.md before enabling takeover.

退出鬼武者后，将 reframework/ 复制到游戏目录。JAR 放入隔离 Minecraft
配置的 mods/，不要将 minecraft-mods/ 解压进鬼武者目录。
Copy reframework/ into OnimushaWotS after exiting the game.
Install the JAR from minecraft-mods/ into the isolated Minecraft profile's mods/.
Do not extract minecraft-mods/ into the Onimusha game directory.
配置默认使用关闭接管的只读阶段 A，新增原生碰撞对象和血量修改测试均停用。
按照分阶段验证记录恢复功能。本包不含实验 RCOL、原版游戏文件、MC安装或账号信息。
Configuration defaults to read-only stage A. Preserve tuning preferences, but
disable native collider allocation and health mutation tests. Follow the staged
validation record; this package does not include experimental RCOL assets.
This archive contains no original game files, Minecraft installation or credentials.
'''
with zipfile.ZipFile(dist / 'OnimushaMC-0.1.0-dev.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for name, path in release.items(): z.write(path, name)
    z.writestr('INSTALL.txt', notice)
    z.writestr('SHA256.json', json.dumps(hashes, ensure_ascii=False, indent=2) + '\n')

tracked = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=repo)
files = sorted(set(x.decode('utf-8') for x in tracked.split(b'\0') if x))
game_resource = re.compile(r'\.(?:pak|tex|mesh|scn|pfb|mdf2|mot|motlist|chain|chain2|rcol|user|vfx|efx)(?:\.\d+)?$', re.IGNORECASE)
owned_assets = {'onimusha/assets/natives/stm/mod/onimusha_mc/unit_box.rcol.37'}
with zipfile.ZipFile(dist / 'OnimushaMC-0.1.0-dev-source.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for name in files:
        path = (repo / name).resolve()
        if not path.is_relative_to(repo) or not path.is_file(): continue
        if any(x in path.parts for x in ('.git', 'bin', 'obj', 'build', '.gradle', '.minecraft')): continue
        if name.endswith(('.pid', '.log')): continue
        if path.suffix.lower() == '.dmp': continue
        if game_resource.search(name) and name not in owned_assets: continue
        if path.name.startswith(('onimusha_mc_status', 'onimusha_mc_worlds', 'onimusha_mc_session', 'onimusha_mc_probe')) and path.suffix.lower()=='.json': continue
        if path.suffix.lower() == '.json' and (path.name.lower().startswith('rsz') or path.name.lower() == 'oniws.json' or any(part.lower() in ('schemas', 'rsz-schema', 'rsz-schemas') for part in path.parts)): continue
        z.write(path, 'SkyCraft-OnimushaMC/' + name)

(dist / 'MOD介绍_Introduction.txt').write_text(notice, encoding='utf-8')
(dist / 'build-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
for path in sorted(dist.glob('OnimushaMC-0.1.0-dev*.zip')):
    print(json.dumps({'file': str(path), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}))
