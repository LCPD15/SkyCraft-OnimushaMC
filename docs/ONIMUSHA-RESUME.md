# 继续测试的停点 / Resume checkpoint

2026-10-08，仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
其他 RE 游戏需要独立适配。MOD制作：LCPD15/LCPD拉灯。

## 最新结果与下一步

### 01:43当前安装：预制方块实例原生绘制，protocol14，等待重启验收

用户要求接管时实际放置方块受鬼武者光照/遮挡，并指出合并模型转换0.45秒的交互延迟。
已改成**预制16种常用方块资源、复用原生碰撞GameObject**，放置时无文件转换；合并模块保留但不加载。
详情和支持范围见 [原生方块绘制](ONIMUSHA-NATIVE-BLOCK-RENDERING.md)。
已更换DLL、Fabric JAR、loader/main/native_blocks和新增第六payload `onimusha_native_instances.lua`。
`enable_native_section_rendering=true` 实际委托预制实例模块。源 `onimusha_native_sections.lua` 是停用实验，
不要同时加载它。原生碰撞1280上限保留，导航与全部物体探针保持关闭。
27个Lua脚本、63项Java测试、3/3原生CTest以及10项转换输入测试通过；77项部署哈希验证。
65文件存档完整备份 `runtime/test-backups/before-native-sections-20261008-014343`，没有改动背包/世界。

之前游戏PID122276已于01:10关闭，MC PID18704自行保存退出。当前游戏/MC都未运行。
已询问用户“请启动鬼武者、进入场景、保持F10关闭”，**等待回复**。
回复后先读新status确认新DLL协议14与场景正常，再运行
`G:/Onimusha_MC_mod/tools/MC-launch-dev.ps1 -WorldName OnimushaMC-XYZ-v2 -LogPrefix live-native-instances-20261008 -StartHidden -QuitWithHost -SwordBlocking`。
这个启动器已撤掉自动启动Blender转换器的临时补丁。不需要启动worker。
MC启动日志应有 `Onimusha prebuilt cube resources: true`，否则检查selected packs，不要强制换掉用户贴图。
连接ready后再请用户F10、少量连续放置石头/铁块；观察 `native_sections.mode=prebuilt_instances`、
ready/count、source native receipt及资源加载错误。**尚未进行这版实际游戏测试，不能宣称已完成光照验收。**

以下00:30及更早均为历史；不要按历史PID、protocol13或旧指纹重新部署。

### 00:30新增结果：原生合并区块模型实景通过

1280完整方块碰撞同步已通过下面四项用户实测，并保存本地提交8d7915b。
随后离线实现REN_SECTION/REN_ATLAS→原生合并MESH/MDF/TEX工具，
用户确认五个石头/铁块的合并测试模型“显示、光照和遮挡均正常”。
它是协议格式的人工测试几何+真实MC贴图，**不是实时MC世界区块，实时原生绘制仍未接入**。
详见 [原生区块模型原型](ONIMUSHA-NATIVE-SECTION-PROTOTYPE.md)。

试验请求 merged-mc-section-20261008-b已就绪/实景通过/撤除，destroyed=true。
第一次a请求因游戏暂停、对象Update=false而加载超时；用户回到场景后同一文件成功。
源码探针已加入暂停等待与清理ready=false，回归通过且已热加载。
唯一loader最新generation3，id `63b819d4a29a442aa77ebcbdd3a4dfd6`，phase=loaded。
游戏PID122276、MC PID18704继续运行，F10关闭，没有待回复问题；物体探针enabled=false。
部署manifest现26项已核对。此阶段只更新combat_inventory payload并添加3个显示测试资源，
没有更换DLL/JAR，也没有更改MC存档。原生导航仍停用。

下一步：有界实时section/atlas捕获与后台转换、资源生命周期和精确版本回执后切换绘制。
禁止把当前离线Blender转换器逐帧调用；禁止提前隐藏原overlay或宣称全部MC内容已受原生光照。
日志/备份 `logs/native-section-20261008/`；生成资源 `assets/native-sections/`。

### 当前候选：1280 原生完整方块碰撞同步，protocol 13

已在单独石头方块验证原生显示/光照/遮挡、玩家和普通敌人阻挡、删除清理后，
实现 MC 完整立方体的碰撞同步。**用户已确认放置阻挡敌人、拆除恢复通行、TNT清除碰撞，以及F10关闭后原角色恢复且无残留碰撞。**
当前只实测少量方块；1280上限及分批创建有离线回归，尚未进行游戏内1280密集构建压力测试。
用户指定上限1280；半径16，最近优先，最多每帧创建2个、轮流检查16个，退休中的对象也计入上限。
非完整立方体（半砖/楼梯/栅栏等）暂不接入，不能强行用整块代替。MC整体仍为叠加渲染，导航停用。

Protocol13新增 REN_FULL_CUBES=12，32字节头带world/epoch/MC PID，512字节位图全量替换section。
DLL `snapshot_full_cubes` 返回最近方块快照与截断数量。拒绝旧会话、错误尺寸、错误位计数，
连接generation变化后须先收到MC清空栅栏；Lua关闭接管/换场景/重载时清除自有碰撞。
新第五个payload `onimusha_native_blocks.lua`，唯一autorun loader文件清单已更新。
`enable_prefab_block_colliders=true`；旧 `enable_native_block_colliders` 和全部物体探针仍false。
单位尺度只支持已实测1.0；无导航和新原生渲染组件。

2026-10-07 23:22关闭游戏PID84716；MC PID85296于23:22:57正常保存退出。
最新64文件完整世界/旧DLL/JAR/Lua/config/manifest备份：
`runtime/test-backups/before-prefab-collision-20261007-233153`。
候选部署收据 `logs/prefab-block-candidate-installation.json`，23个游戏文件哈希核对通过。
安装工具 `onimusha/tools/Install-PrefabBlockCandidate.py` 只用于此次旧指纹迁移，不可不检查就反复运行。
Fabric构建与JUnit通过，25个Lua回归通过（1280密集对象测试另有复测通过），3个原生CTest全部通过。
本轮已更换DLL/JAR/loader/main；不要使用下方历史protocol12指纹作为当前安装值。

新游戏PID122276、MC PID18704，原 `OnimushaMC-XYZ-v2` 世界，
日志 `logs/live-prefab-collision-20261007.stdout.log`；协议13、相机/地形/连接ready。
用户已通过放墙阻挡敌人→拆掉后恢复通行；读取时 count=ready=retiring=desired=0、phase=empty，render_invalid=0。
TNT测试用户回复“方块被炸掉，敌人能正常经过”；F10关闭测试用户回复“恢复正常，没有残留碰撞”。
最终状态 active=false、native.enabled=false、count=ready=retiring=desired=0、phase=disabled，render_invalid=0。
当前接管关闭，游戏和MC保持运行，没有待回复问题。对应证据保存在
`logs/remaining-engine-work-20261007/prefab-block-{place-break,tnt,f10-off}-user-*`。
不要重复发道具，不要重新引爆原游戏油桶，不要开启导航实验。
同PID的长时间MC停顿/心跳恢复后，generation变化会撤销方块缓存，需要MC重新发清空与快照；
该恢复分支尚未进行实时验收，不能声称任意断连都已无缝恢复。

### 历史记录：单方块实验与此前恢复

以下记录保留事故和测试顺序。协议、部署、进程及验收状态以上方最新结果为准。

动态地形用户已实测连续走上百米，只有一次闪断；用户明确要求暂不处理这一次，继续剩余工作。
不要重新展开该闪断排查。不要模拟键鼠输入，实际游戏操作由用户完成。

本轮原生石头单方块已由用户验证：MC贴图、光照、遮挡正确，阻挡原角色，删除后碰撞清除。
重启后用户另测普通敌人追逐，确认敌人被石头方块挡住；主动绕路尚未通过。
生产MC世界仍使用叠加绘制，原生方块同步尚未接入。
详见 [原生物体实验](ONIMUSHA-NATIVE-OBJECT-PROBE.md)。

**随后导航扩展实验触发闪退，现已撤下。重启后的基础场景与 MC 接管/恢复已由用户确认正常。**
22:21:44日志记录 AIMapEffector.hasEffectNodes 调用异常，紧接访问违规；
尚未区分调用、注册/清理、原生更新时序问题。不要只加pcall后再次尝试。
运行脚本已删除导航创建和 hasEffectNodes 调用，navigation_cube动作拒绝。
导航PFB/USER已撤到隔离日志；资源生成器仅保留 navigation-offline-only 离线复现。
不要部署导航生成物，不要启用旧native block collider全局开关或WorkRate实验。

游戏PID107512已退出；MC PID115140检测宿主退出后22:21:51正常保存退出。
当前64文件世界备份且SHA256核对：`runtime/test-backups/after-native-probe-20261007-222930`。
未手动改世界、道具或背包。世界仍为 OnimushaMC-XYZ-v2。
MC日志 `logs/live-dynamic-terrain-20261007.stdout.log`。
事故、源码隔离副本、dump、恢复收据均在 `logs/remaining-engine-work-20261007/`。
两个探针控制 enabled=false，22个部署文件哈希一致。
24个Lua回归通过；本轮DLL/JAR/主Lua/攻击脚本没有改动。

新游戏PID84716已进入场景；原MC世界已由开发启动器恢复，PID85296。
MC日志 `logs/live-native-probe-recovery-20261007.stdout.log`。
用户确认移动、视角、背包和F10关闭恢复均正常。连接、相机、地形均ready，无渲染协议拒绝。
用户到空地关闭接管后，physics-enemy-collision-20261007-a 已成功生成。
用户确认普通敌人被挡住。随后 remove-physics-enemy-collision-20261007-a 已回报 removed/destroyed=true。
控制文件已再次 disabled，当前没有测试物体、没有待回复问题。
日志目录保存 physics-enemy-collision-a 的 ready/user-pass/user-feedback/removed 证据。
下一步将原生碰撞创建/删除接入MC实际方块同步。导航仍隔离，不能自动加载。
导航继续离线排查，纯显示+Colliders创建路径已通过，可作为后续MC方块同步基础。
RENSOLIDS只有占用位，不能把半砖/楼梯/栅栏都变成满立方体；需要精确形状或明确支持范围。
MC角色原生材质/动画和处决也仍未完成。

项目唯一autorun为loader；不需手工Reset。旧进程请求`6031a4a3de464c1fa77eead8471ffb66`
曾因退出超时；新进程启动后已处理该请求，generation2、frame32、phase=loaded。
游戏目录中的payload为无导航版本，源码与部署指纹一致。
老稳定提交df92eb8及动态地形候选包保留，不能用原生实验覆盖稳定发行包。

## 历史记录：爆炸实现与道具

只读油桶探针成功记录两个 Gm019_000 连锁爆炸（32事件、无错误）。探针在 combat_inventory payload 内，
采样已停用；不要让用户重新采样。逻辑 ID 4 → fixed ID 6 →数组索引 4 → shl_g019_000_004 主 shell。
主 shell 自动创建伤害/效果子 shell；不能把 getShellPackage 的索引误当 fixed ID。
所有生产对象重新分配/通过当前拥有者解析，不重用采样指针或修改共享资源。

爆炸协议本轮未改变。flags bit7 表示原生爆炸能力；EV3 的 formId=事件ID、weapon=epoch、flags=1。
MC 在事件确实入队时抑制该次敌人代理爆炸伤害，避免与原生 AoE 重复；MC 保留自伤与方块破坏。
原生子 shell `_EnableSelfDamage=false`，以当前玩家为 owner。跨进程最终 ACK 尚未实现；不确定原生失败不重试。
爆炸占用尾段加入 loader busy 门控，所有新 hook 继续由唯一项目重载器管理。

测试道具已发放，不要再添加：TNT 3×64、末地水晶64、黑曜石64、打火石1、铁块4×64、雕刻南瓜2×64。
旧有金苹果4×64也已经发过。新增物品只占空格，原物品和其他 NBT 全部验证不变。
完整世界备份 runtime/test-backups/before-explosion-golem-20261007-181455（60文件），
收据 logs/explosion-golem-grant-20261007.json。

## 历史记录：此前部署

唯一项目 autorun：reframework/autorun/onimusha_loader.lua。
四个 payload 在 reframework/data/onimusha_mc/scripts/：main/enemy_hit/guard_probe/combat_inventory。
禁止重建旧同名 autorun。爆炸生产逻辑封装在 enemy_hit 末尾独立 scope，探针在 combat_inventory 末尾。
重载工具 G:/Onimusha_MC_mod/tools/Reload-OnimushaScripts.ps1 自动关闭接管、等待恢复和 native busy 清空。
当前进程是新启动；上个进程最后自动重载 gen11 / 302b3179577c4990a261936684539ebf。
DLL与主Lua本轮已更新，loader未改动，不需手工 Reset。

安装工厂开关 reframework/data/onimusha_explosion_control.json；日志 onimusha_explosion_status.json。
能力位没有就绪时 MC 保留原代理爆炸命中路线（HIT_EXPLOSION=16），不会假称原生生成成功。
fire bit=8（此前误4，4是sweep）已经修复。近战10米、projectile/fire/explosion/mob命中128米。
上一轮弓箭远距离修复仍未独立实测；用户转向爆炸任务，不要宣称已通过。

## 历史记录：此前验证与剩余范围

Fabric build 通过，61 个 Java 测试通过（含3个新增寻路测试）；23 个 Lua 回归脚本全部通过。
新增3个Java作用域测试覆盖嵌套爆炸、异常清理、未入队本地结算；Lua覆盖去重、旧会话/非法输入拒绝、
多个同时TNT、原生不确定结果不重试。真实 TNT/方块破坏已由用户确认。
末地水晶、密集连锁、自伤精确去重、换场景资源独立加载、铁傀儡站立/寻路/近处攻击已由用户确认通过；更远区域待本轮复测。

既有：MC普通/特殊两套全局攻击模板由当前玩家资产ID1/41解析，所有敌人共用，不要求逐敌/逐招采样。
RSC活动受击范围聚合AABB，默认BODY部位；不能称已完成逐部位、装甲弱点或所有Boss阶段。
3C、F5、背包、相机UI跟随、持续移动、F10恢复、方块站立/拆除、百分比HP与治疗已通过。
MC格挡无扣血并有声音已确认；红闪/击退/火花未逐项确认。

原生NPC对MC方块的碰撞/寻路、真实RE深度/光照、处决仍未实现；实验碰撞对象创建保持禁用。
致死奖励、破甲、特殊弹反与跨会话事务 ACK 尚未覆盖。当前 MC 仍用叠加渲染私有深度。

项目 G:/Onimusha_MC_mod/source/SkyCraft，分支 onimusha-bridge，fork LCPD15/SkyCraft-OnimushaMC，未推送。
源码、下载、编译和备份均在用户指定 MC 工作根；保存本地提交，禁止未经授权向外发送。

## 历史文件指纹（protocol12，不是当前部署）

- DLL: `D60C30148D0CBEE6B1727483500EC9AF1D366C15C3E3170AF5CFA6CC66EFD57F`
- JAR: `5A64BF0D97B2CB8CDD6534E33C642A3C601431C8CE42817B5B865EB07EBD43C7`
- main Lua: `A42D3AD1DE4A34037CDE82FC807B44A0AE17E1028A9AC003EC4F7BE21D814281`
- enemy Lua: `7D0B6BB04D8A3DED75FE2FDE3110CBFF0F90B343190846EEC4EBB7B74C11F279`
