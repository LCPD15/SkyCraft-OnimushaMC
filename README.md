# OnimushaMC / 鬼武者 × Minecraft

**MOD制作：LCPD15/LCPD拉灯** · 基于 [chasmlol/SkyCraft](https://github.com/chasmlol/SkyCraft) 的鬼武者专用移植。

在 **Onimusha: Way of the Sword / 鬼武者（OnimushaWotS）** 场景中使用 Minecraft 的角色控制、战斗、界面、物品和建造。F10 开关接管；原角色在接管期间隐藏。当前版本 **0.2.0**，Windows x64，单人本地桥接。

Use Minecraft controls, combat, UI, items and building inside **OnimushaWotS**. F10 toggles takeover and restores the original character when disabled. Version **0.2.0**, Windows x64, local single-player bridge.

**只适用于本项目验证过的鬼武者版本；不是通用 RE 引擎插件。** 生化危机、怪物猎人等游戏需要独立的接口、资源格式和参数适配。
**Onimusha only.** Other RE Engine games need separate API, format and parameter adapters.

## 下载与文档 / Download and documentation

- [发布包 / Releases](https://github.com/LCPD15/SkyCraft-OnimushaMC/releases) — 下载 `OnimushaMC-v0.2.0-win64.zip`，包含插件、转换器、第三方转换依赖及 MC 实例导入包。
- [安装与使用 / Install and play](docs/ONIMUSHA-INSTALL.md)
- [源码构建 / Build from source](docs/ONIMUSHA-BUILD.md)
- [版本说明 / Release notes](docs/ONIMUSHA-RELEASE-NOTES.md)
- [第三方许可 / Third-party notices](docs/ONIMUSHA-THIRD-PARTY.md)

The Windows package contains the native plugin, Lua adapter, conversion worker and importable Minecraft instance. Minecraft, Java, Blender and REFramework are external prerequisites; no commercial game files, accounts or personal saves are bundled.

## 功能 / Features

| 功能 / Feature | 当前行为 / Behavior |
|---|---|
| 操作与界面 / Controls and UI | MC 第一、第三人称、背包、聊天命令；聊天时屏蔽鬼武者按键。First/third person, inventory and chat with host input isolation. |
| 血量与护甲 / Health and armor | 原游戏血量按百分比映射到 MC 爱心；MC 护甲参与减伤。Native HP mapped to hearts; MC armor reduces incoming damage. |
| 战斗 / Combat | 根据 MC 手持武器伤害结算原生攻击，有通用受击反馈；支持举盾／举剑格挡。Weapon damage, native hit feedback and shield/sword blocking. |
| 伤害设置 / Damage tuning | REFramework 面板提供 100 / 500 / 1000 / 2000 / 5000 档，默认 100。Configurable native HP damage per MC damage point. |
| 建造 / Building | 放置、拆除 MC 方块；完整方块可阻挡鬼武者玩家及敌人。Place/break MC blocks; solid cubes block native characters. |
| 显示 / Rendering | 受支持的方块、人物、手持物、NPC、活动 TNT 转入 RE 原生光照和遮挡；转换结果本地缓存。Eligible geometry uses native lighting/occlusion and disk caching. |
| 爆炸 / Explosions | MC 爆炸触发鬼武者油桶爆炸流程，影响敌人并破坏 MC 方块。Native explosion effects/damage with MC block destruction. |
| MC 生物 / Mobs | 铁傀儡可在原生地形移动、攻击敌人；原生敌人的攻击体积可伤害 MC 生物。Golems navigate terrain and fight; native attack volumes damage MC mobs. |
| 吸魂 / Souls | 按住 C 或右键吸魂，保留原奖励，额外随机回血、修耐久、加物品或经验。C/right mouse absorbs souls with an extra randomized MC reward. |
| 恢复 / Restoration | F10 关闭后恢复原角色、输入并撤除 MOD 的活动碰撞／显示；死亡交回原游戏重试。Native retry owns death; takeover objects are cleaned up on release. |

这是两端运行的桥接：Minecraft 负责 MC 规则，REFramework 插件负责鬼武者接口；可转换几何交给 RE 原生绘制，HUD 和尚不支持的内容保留 MC 合成回退。**并非所有内容都只是画面叠加，也不是任意 MC 模组的通用移植器。**
Minecraft runs the MC simulation; the REFramework plugin handles host interaction. Converted geometry is drawn natively by RE, while HUD and unsupported content retain compositing fallback.

## 兼容边界 / Compatibility limits

验证组合：鬼武者 01.000.001 / TDB82；Minecraft 26.3；Fabric Loader 0.19.5；Fabric API 0.161.0+26.3；Java 25；Blender 5.2；RE Mesh Editor 0.66（随转换器附带）。REFramework API 固定修订见构建说明。
Tested versions are listed above; use them for the first installation.

- 只拆除 MC 方块，不拆原游戏场景。Native terrain cannot be mined.
- 原生碰撞上限 1280，当前在玩家附近约 16 米维护；静态原生绘制半径约 128 米。不同形状、透明／动画材质、自定义渲染器可能回退到 MC 绘制。Native collision is bounded; unsupported geometry/materials may fall back.
- 首次遇到新外观需要转换，之后复用磁盘缓存；硬件和模型复杂度影响首次延迟。New appearances need an initial conversion.
- 原生敌人能被方块挡住，但尚未完成原生 AI 动态导航网格重建。Blocking is supported; full native navigation rebuild is not.
- 处决动画接管、任意敌人的近镜头渐隐、所有 Boss 阶段／场景切换仍未做全面兼容保证。Executions, all camera-fade cases and every boss/scene transition are not universally validated.
- 添加其他 MC 模组需匹配同一 MC/Fabric 版本。机械动力等复杂机器、专有渲染器／实体及联网玩法未验证。Other mods and multiplayer are not guaranteed compatible.

## 许可 / License

项目主体沿用 [MIT](LICENSE)，原作者 chasmlol。独立 Blender 转换进程使用的 RE Mesh Editor 保留 GPL 许可和完整对应源码；并不改写为 MIT。第三方许可随包提供。Minecraft/Mojang/Microsoft、Capcom 与本项目无隶属或背书关系。
The project retains the upstream MIT license. The separate Blender worker uses RE Mesh Editor under its own GPL terms with source and notices included. This is an unofficial project.
