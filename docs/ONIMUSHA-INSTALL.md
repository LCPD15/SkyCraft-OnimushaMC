# 安装与使用 / Installation and usage

**MOD制作：LCPD15/LCPD拉灯** · OnimushaMC 0.2.0 · 仅限 OnimushaWotS。

## 1. 准备 / Prerequisites

- Windows x64，已安装并能运行鬼武者及适配它的 [REFramework](https://github.com/praydog/REFramework/releases)。游戏目录应有 `OnimushaWotS.exe` 和 `dinput8.dll`。本包不覆盖 REFramework 本体。
- 安装 [Blender 5.2](https://www.blender.org/download/)；后台转换器使用其 Python、NumPy 和图形资源写入能力。不必打开 Blender 界面，RE Mesh Editor 0.66 已随包放在 `third-party/RE-Mesh-Editor`。
- [Prism Launcher](https://prismlauncher.org/download/) 和有 Minecraft Java 版权限的账户，或自行配置 PCL 等启动器。Minecraft 26.3、Fabric 0.19.5、Java 25。首启由启动器下载游戏和 Java。
- 解压到有写权限、空间足够的目录，例如 `G:\OnimushaMC`；路径可含空格。包内 `cache`、`logs` 会在运行后建立，不要把整个包只复制到游戏目录后删除原目录。

Install the tested versions above. The package does not include Minecraft, Blender, Java, REFramework or an account. Keep the extracted package in a writable permanent directory; its worker and cache are used at runtime.

## 2. 首次安装 / First installation

1. 退出鬼武者。双击 `Install-OnimushaMC.cmd`，输入游戏目录及 `blender.exe` 完整路径。安装器核对 SHA-256，并备份要覆盖的文件。现有测试版的同名配置会保存后换成发布默认值；再次安装本发布包会保留设置。
2. 在 Prism 选择“添加实例 → 导入”，选择包内 `Minecraft-instance.zip`，实例名使用 `OnimushaMC`。登录自己的账户，Java 选择 25。实例内已带本 MOD、对应 Fabric API、中文语言设置和 JVM 参数。
3. 启动鬼武者并进入可操作场景，保持 F10 关闭。
4. 双击 `Connect-OnimushaMC.cmd`。看到 `Native-lighting converter is ready` 后，在 Prism 启动 `OnimushaMC` 实例。MC 会自动创建／打开 `OnimushaMC` 镜像世界，不需手动建普通世界。
5. 等 MC 完成进场，切回鬼武者窗口按 F10。再按 F10 关闭接管。首次模型转换需要稍等；后续使用本地缓存。

Exit the game, run the installer, import the bundled instance into Prism and sign in. Enter a playable Onimusha scene, run the connection script, launch the imported MC instance, then focus Onimusha and press F10. The mirror world opens automatically. The Minecraft window remains visible.

可选：配置 Prism 自动启动，下一次只需运行连接脚本：
Optional one-command startup after the host enters its scene:

```powershell
.\Manage-OnimushaMC.ps1 -Action Configure -GameRoot 'F:\Games\OnimushaWotS' -Blender 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' -PrismLauncher 'C:\PrismLauncher\prismlauncher.exe' -Instance 'OnimushaMC'
```

`Instance` 是 Prism 的实例目录 ID；若导入后被命名为 `OnimushaMC 1`，请填实际 ID。连接脚本不会关闭游戏、修改存档或重复启动已检测到的客户端。它只连接已运行的鬼武者，不启动鬼武者本体。
`Instance` must match Prism's actual instance folder ID. The connection script starts the worker and optionally Prism; it does not start Onimusha itself.

## 3. PCL / 自行启动 / Other launchers

创建独立 Minecraft 26.3 + Fabric Loader 0.19.5 实例，使用 Java 25。把导入 ZIP 中 `.minecraft/mods` 的两个 JAR 放到该实例 `mods`。复制 `Minecraft-JVM-arguments.txt` 内容到 JVM 参数（不是游戏参数）。不要加 `-Dskycraft.startHidden=true`。
Create an isolated profile using the versions above, copy both JARs from the instance ZIP and paste `Minecraft-JVM-arguments.txt` into JVM arguments. Run the connection script before launching that profile.

日常顺序：鬼武者进场景 → 连接脚本（转换器）→ 启动 MC → 回鬼武者 F10。关闭鬼武者后 MC 默认保存退出，转换器跟随退出。先关接管再退出游戏更便于观察恢复。
Order: host scene → converter → MC → F10. By default MC saves/quits and the worker exits when the host closes.

## 4. 按键与伤害 / Controls and damage

| 按键 / Key | 功能 / Action |
|---|---|
| F10 | 开关接管 / Toggle takeover |
| WASD、空格 / Space、Shift | 移动、跳跃、潜行 / Move, jump, sneak |
| 鼠标左键 / Left mouse | 攻击、拆 MC 方块 / Attack, break MC blocks |
| 鼠标右键 / Right mouse | 放置／使用、举盾或举剑，并吸魂 / Place/use, block, absorb souls |
| C（按住 / hold） | 吸魂 / Absorb souls |
| E、F5 | 背包、三种视角 / Inventory, camera modes |
| T 或 / | 聊天、命令 / Chat, commands |

命令：`/gamemode creative` 开创造；`/gamemode survival` 回生存。`adventure` 是冒险模式，会限制普通放置／拆除，不代表桥接损坏。
Use creative or survival for building; adventure mode intentionally restricts building.

伤害：打开 REFramework → Script Generated UI → Onimusha MC / 鬼武者 MC → Damage / 伤害设置。100 / 500 / 1000 / 2000 / 5000 是每个 MC 伤害点对应的原游戏伤害系数（不是 UI 百分号）；先根据武器伤害算 MC 攻击，再用选定系数结算原生伤害。默认 100，设置会保存。
Damage presets scale MC weapon damage into native HP damage. They are not percentages. Default is 100.

吸魂保留原色奖励，另随机追加：回 5% 最大血量、随机可修装备恢复 1 耐久、随机未满物品堆 +1、增加一级经验进度 23%。无效选项重新随机。
Souls keep native rewards plus one eligible random MC reward: 5% healing, one durability point, one stack item, or 23% of a level's XP progress.

## 5. 存档、缓存与升级 / Saves, cache and updates

- 存档在启动器实例 `.minecraft/saves/OnimushaMC`。升级前退出两游戏并备份此目录。旧测试存档可复制过来，并在 JVM 参数中修改 `onimusha.worldName` 为它的文件夹名；不要同时运行两个实例读写它。
- 转换缓存：包目录 `cache/native-models`。游戏资源副本：游戏目录 `natives/stm/mod/onimusha_mc/sections`。首次新外观慢、之后复用是正常行为。转换器／贴图模板变更会自动区分缓存身份。
- 升级：退出游戏，使用新包运行安装器；更新 MC 实例中的本 MOD JAR，移除旧版本 JAR，保留 `saves`。不要把两个版本同时放进 `mods`。
- 卸载：退出游戏，运行 `Uninstall-OnimushaMC.cmd`，再从 MC 实例移除本 MOD JAR。安装器恢复安装前文件并保留存档、缓存和其他 MOD；如安装前已有开发版，卸载会恢复该开发版。

Back up the MC world before upgrading. The disk cache stays local; generated game resources are private to `mod/onimusha_mc`. Uninstall restores files present before installation and keeps saves, cache and other mods. An older development version is restored if it was present before installing this release.

## 6. 常见问题 / Troubleshooting

- 无原生光照：确认连接脚本显示转换器 ready，查看包目录 `logs` 和游戏 `reframework/data/onimusha_mc/native_models/worker.json`。不要只启动 MC 而漏掉转换器。
- 不接管：检查版本组合、REFramework 是否加载 `OnimushaMC.dll`、唯一项目 autorun 是否为 `onimusha_loader.lua`，关闭暂停菜单再试。
- 方块不能放：确认存活且处于 survival/creative，右键目标在可达范围内；冒险模式限制建造。
- 黑屏／启动异常：退出游戏，先移出 `reframework/plugins/OnimushaMC.dll` 和 `reframework/autorun/onimusha_loader.lua` 以隔离本 MOD；保留日志，避免反复叠装多个版本。
- 添加 MC 模组：必须适配 MC 26.3 + Fabric。先复制实例单独测试；自定义渲染、机械动力结构、流体、光影和联网均不保证兼容。无需为了试其他模组替换正在用的存档。

For lighting issues, check the converter status/logs. For startup issues, isolate this DLL and loader after closing the game. For building issues, check health and game mode. Test additional mods in a copied instance.
