# 继续测试的停点 / Resume checkpoint

2026-10-07，仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
其他 RE 游戏需要独立适配。MOD制作：LCPD15/LCPD拉灯。

## 最新结果与下一步

用户已确认铁傀儡能正常站立和寻路，原先13/14边界不再闪断。
另一处接管中断已定位：同一stage:0:area:13、同一epoch，没有Stage transition，
14次地形转换超过1200万次工作上限，4次角色走出旧覆盖。不要再把这次失败归因于AreaID。
已用只读原生查询捕获故障位置3494面及完整格边界5107面；旧算法离线均复现失败。
详见 ONIMUSHA-DYNAMIC-TERRAIN.md。另2次Waiting for Minecraft world短暂状态未单独定位。

新版：完整8格查询边界+0.002格halo，保留旧完整覆盖直到新批次消费确认；
表面体素转换降低无效工作量，保持原有工作上限，新增数值副本后台线程。
票据/发布/消费三阶段分开，epoch/PID/generation改变时丢弃后台旧结果。
3组原生CTest通过，23个Lua回归通过（两个旧边界断言已更新并复测）。
真实两份地形重放全部成功。游戏内跨区域路线尚待用户验收，不宣布已完全解决。
Fabric JAR未改动，不需重复铁傀儡建造道具发放或区域13/14迁移。

20:00已按既有授权关闭游戏，MC正常保存退出；64文件完整世界备份且哈希验证：
`runtime/test-backups/before-dynamic-terrain-20261007-200301`。
20:21新版DLL与主Lua已安装，14个受管文件哈希一致，存档全部64文件与备份一致。
安装收据 `logs/dynamic-area-20261007-194446/installation.json`，临时只读捕获代码已移除。
唯一autorun仍是loader，不需要手工Reset Scripts。

已请求用户启动游戏进场景，暂不F10。收到回复后：核实当前游戏PID/进程路径和新状态；
启动原世界：`G:/Onimusha_MC_mod/tools/MC-launch-dev.ps1 -WorldName OnimushaMC-XYZ-v2
-LogPrefix live-dynamic-terrain-20261007 -StartHidden -QuitWithHost -SwordBlocking`。
确认MC连接、碰撞异步job published、消费ACK/host_ready后，再让用户F10开启沿旧断联路线往返，
继续走远一点，测试后保持开启读取日志。**当前启动问题已发出，不要重复提问。**
不要模拟键鼠输入；实际游戏操作由用户完成。不要杀MC Java，关游戏后等待保存退出。

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
