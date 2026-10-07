# 继续测试的停点 / Resume checkpoint

2026-10-07，仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
其他 RE 游戏需要独立适配。MOD制作：LCPD15/LCPD拉灯。

## 最新结果与下一步

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

## 本轮实现与道具

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

## 部署与继续工作

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

## 验证与剩余范围

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

## 当前文件指纹

- DLL: `D60C30148D0CBEE6B1727483500EC9AF1D366C15C3E3170AF5CFA6CC66EFD57F`
- JAR: `5A64BF0D97B2CB8CDD6534E33C642A3C601431C8CE42817B5B865EB07EBD43C7`
- main Lua: `A42D3AD1DE4A34037CDE82FC807B44A0AE17E1028A9AC003EC4F7BE21D814281`
- enemy Lua: `7D0B6BB04D8A3DED75FE2FDE3110CBFF0F90B343190846EEC4EBB7B74C11F279`
