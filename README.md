# SkyCraft — OnimushaMC

**开发中的鬼武者适配 / Experimental Onimusha adapter.**

本分支基于 [chasmlol/SkyCraft](https://github.com/chasmlol/SkyCraft)，把原有的 Minecraft Fabric 客户端、共享内存协议、方块网格和 HUD 输出接到鬼武者的 REFramework 插件。Minecraft 执行移动、视角、物品和战斗逻辑；鬼武者保留场景、敌人、任务和存档。

This fork connects SkyCraft's Minecraft Fabric client, shared-memory protocol, block meshes and HUD to an Onimusha REFramework plugin. Minecraft owns movement, camera, items and combat; Onimusha retains its world, enemies, quests and saves.

**当前范围仅限 `OnimushaWotS` / Target: `ONIMUSHA_WOTS` only.** 生化危机、怪物猎人以及其他 RE 引擎游戏需要独立的角色、相机、碰撞和伤害绑定，不能直接使用本适配。

## 组件 / Components

| 路径 / Path | 用途 / Purpose |
|---|---|
| `fabric/` | MC 26.3 Fabric 分支：输入、角色、HUD、物品、MC 战斗与健康百分比 / Minecraft client bridge |
| `protocol/skycraft_protocol.h` | 协议 v12；独立映射 `Local\OnimushaMC_v1` / Versioned shared-memory contract |
| `onimusha/native/` | Windows x64 REFramework DLL、D3D11-on-12 绘制、通信与验证 / Native plugin and renderer |
| `onimusha/adapter/` | 鬼武者 Lua 对象绑定和只读场景探针 / Game-specific adapter and diagnostic probe |
| `onimusha/launcher/` | 隔离 Minecraft 安装及启动脚本 / Isolated launcher scripts |
| `docs/onimusha-bindings.md` | 本地 TDB 与运行场景绑定证据 / Binding evidence |
| `docs/README-Skyrim-upstream.md` | 上游 Skyrim 项目的原说明，仅作为来源记录 / Original upstream README |

## 行为 / Behavior

- MC 3C、背包、手持物品和 HUD 通过插件绘制到鬼武者。成功接管后隐藏原玩家绘制；连接、绑定、地形、相机或 GPU 未就绪时保持原游戏可见。
- MC 输入及 MC 武器伤害通过协议传递。原游戏实际血量仍是权威值：`MC 血量 = clamp(原血量 / 原最大血量, 0, 1) × 20`。例如原游戏 75/100 血量显示为 7.5 颗心。收到尚未结算的原游戏伤害时，由 MC 护甲和盾牌计算，再按最大血量比例回写。
- 原游戏地形作为 MC 碰撞来源。原地形不能被挖掉；MC 放置的方块可放置和拆除。鬼武者实体方块碰撞需要通过游戏适配器的注册检查。
- 场景切换使用 epoch 清空旧地形和事件。传送确认、菜单、过场、MC 断开或禁用时停止接管；失焦时释放 MC 输入。

MC character, camera, inventory, held items and HUD are rendered inside the host. Host HP is authoritative and mapped proportionally to ten Minecraft hearts. Original terrain is protected; placed MC blocks can be built and removed. Takeover requires verified game bindings, collision, camera, renderer and teleport acknowledgement. Scene changes and disconnects release control.

上述内容是代码设计；实际游戏验证状态见 [验证记录](docs/ONIMUSHA-VALIDATION.md)。不要把独立通信或 GPU 测试当作鬼武者完整玩法测试。

2026-10-07：MC 对敌伤害倍率从10改为100，即之前的十倍，玩家受伤／治疗百分比不变。相机时序修正与额外候选的实测边界见[停点记录](docs/ONIMUSHA-RESUME.md)。光照、遮挡、碰撞、寻路、伤害平衡、处决与格挡的证据和实施路线集中在[研究入口](docs/ONIMUSHA-OVERNIGHT-RESEARCH.md)；这些原生机制尚未全部实现。

These are implementation goals and code paths. See the [validation record](docs/ONIMUSHA-VALIDATION.md) for the current evidence; IPC and GPU smoke tests do not establish full in-game functionality.

## 版本与构建 / Versions and build

开发环境：Windows x64、Minecraft 26.3、Fabric Loader 0.19.5、Fabric API 0.161.0+26.3、JDK 25、Gradle 9.7.1、Visual Studio 2026。

REFramework 的头文件和 Lua 固定于本机已安装版本对应提交 `b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。升级框架必须重新检查 ABI 和游戏 TDB 绑定。

```powershell
# Run from this repository, with JAVA_HOME pointing to JDK 25.
cd fabric
.\gradlew.bat test build

# Native plugin: Windows x64 Visual Studio toolchain.
cmake -S onimusha -B build/onimusha -A x64
cmake --build build/onimusha --config Release
ctest --test-dir build/onimusha -C Release --output-on-failure
```

Minecraft 正式运行通过隔离 PCL 配置登录。`MC-launch-dev.ps1` 是不读取用户凭据的本地开发测试入口；不提供线上身份验证。MC 安装、资产、登录状态、构建产物和游戏探针快照都不提交到源码库。

Use the isolated PCL profile for normal authenticated play. `MC-launch-dev.ps1` is a local developer test entry point without account credentials or online authentication. Minecraft binaries, assets, credentials, build products and live probe snapshots are excluded from this repository.

## 控制 / Controls

| 键 / Key | 行为 / Action |
|---|---|
| F10 | 开启或关闭接管 / Toggle takeover |
| WASD、空格、Shift | MC 移动、跳跃、潜行 / Movement, jump, crouch |
| 鼠标、左右键、滚轮 | MC 视角、攻击、放置及物品栏 / Look, attack, place, hotbar |
| E / F5 / O | MC 背包 / 视角切换 / 菜单 / Inventory / camera mode / menu |
| Insert | REFramework 界面 / REFramework UI |
| Escape、G（未打开 MC 界面时） | 保留原游戏菜单与交互通路 / Host menu and interaction pass-through |

## 作者与许可 / Credits and license

MOD制作：LCPD15/LCPD拉灯

Original SkyCraft: **chasmlol**. MIT license and upstream copyright are retained in [LICENSE](LICENSE). REFramework headers and vendored Lua retain their original notices. Minecraft and Fabric dependencies are downloaded from their official distribution metadata and are not included in Git source.
