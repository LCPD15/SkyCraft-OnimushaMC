# 继续测试的停点 / Resume checkpoint

2026-10-07，仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
其他 RE 游戏需要独立适配。MOD制作：LCPD15/LCPD拉灯。

## 最新结果与下一步

MC 爆炸桥接已实现。用户确认：“爆炸能正常影响敌人，也能正常销毁方块”。
已保存第一轮 4 次 TNT 原生生成记录，MC→RE 坐标完全对应；Em104_00、Em106_00 原生受击入口、
特效、声音调用均有记录，普通命中原生伤害 1500，剩余 HP 不足时正常归零。
来源 `logs/explosion-probe-20261007/tnt-first-live-*`，完整实现与限制见 ONIMUSHA-EXPLOSION.md。
当前能力只标记油桶资源/工厂就绪，不把所有战斗边界当作通过。MC 爆炸强度暂不缩放原生范围/伤害。

铁傀儡首轮用户结果：近处敌人能被攻击并扣血，但不移动。记录 golem-user-confirmed-*。
根因：路径查询仍看虚空世界空气块，未读 SkyCollision 地形；已补 MC 路径类型/地面高度/
目标表面扫描/稳定落脚点，新增3个Java测试，build成功。当前运行E176 JAR仍是旧寻路版本。

当前待用户回复：已请用户回安全位置、F10关闭并确认原角色恢复，保持游戏运行。
用户确认安全后可按既有授权关闭准确验证路径的鬼武者进程，让 MC 保存退出；
备份世界，再安装 fabric/build/libs 中的寻路候选。不重复发放测试道具。
然后请用户重启进入场景，连接同一世界复测铁傀儡移动。不要重复提出已经挂起的问题。

当前游戏 PID 76224，MC PID 114676（操作前核实路径，不可仅用旧 PID）。
MC 世界 OnimushaMC-XYZ-v2，启动 StartHidden/QuitWithHost/SwordBlocking。
电脑自动输入保持停止，真实游戏操作由用户完成。Shell/文件/已授权进程管理可用。

## 本轮实现与道具

只读油桶探针成功记录两个 Gm019_000 连锁爆炸（32事件、无错误）。探针在 combat_inventory payload 内，
采样已停用；不要让用户重新采样。逻辑 ID 4 → fixed ID 6 →数组索引 4 → shl_g019_000_004 主 shell。
主 shell 自动创建伤害/效果子 shell；不能把 getShellPackage 的索引误当 fixed ID。
所有生产对象重新分配/通过当前拥有者解析，不重用采样指针或修改共享资源。

现有 DLL 无需改变。flags bit7 表示原生爆炸能力；EV3 的 formId=事件ID、weapon=epoch、flags=1。
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
DLL 和 loader 均未改动，不需手工 Reset。

安装工厂开关 reframework/data/onimusha_explosion_control.json；日志 onimusha_explosion_status.json。
能力位没有就绪时 MC 保留原代理爆炸命中路线（HIT_EXPLOSION=16），不会假称原生生成成功。
fire bit=8（此前误4，4是sweep）已经修复。近战10米、projectile/fire/explosion/mob命中128米。
上一轮弓箭远距离修复仍未独立实测；用户转向爆炸任务，不要宣称已通过。

## 验证与剩余范围

Fabric build 通过，58 个 Java 测试通过；22 个 Lua 回归脚本全部通过。
新增3个Java作用域测试覆盖嵌套爆炸、异常清理、未入队本地结算；Lua覆盖去重、旧会话/非法输入拒绝、
多个同时TNT、原生不确定结果不重试。真实 TNT/方块破坏已由用户确认。
末地水晶、密集连锁、自伤精确去重、换场景资源独立加载、铁傀儡结果仍待覆盖。

既有：MC普通/特殊两套全局攻击模板由当前玩家资产ID1/41解析，所有敌人共用，不要求逐敌/逐招采样。
RSC活动受击范围聚合AABB，默认BODY部位；不能称已完成逐部位、装甲弱点或所有Boss阶段。
3C、F5、背包、相机UI跟随、持续移动、F10恢复、方块站立/拆除、百分比HP与治疗已通过。
MC格挡无扣血并有声音已确认；红闪/击退/火花未逐项确认。

原生NPC对MC方块的碰撞/寻路、真实RE深度/光照、处决仍未实现；实验碰撞对象创建保持禁用。
致死奖励、破甲、特殊弹反与跨会话事务 ACK 尚未覆盖。当前 MC 仍用叠加渲染私有深度。

项目 G:/Onimusha_MC_mod/source/SkyCraft，分支 onimusha-bridge，fork LCPD15/SkyCraft-OnimushaMC，未推送。
源码、下载、编译和备份均在用户指定 MC 工作根；保存本地提交，禁止未经授权向外发送。

## 当前文件指纹

- DLL: `5291E47D62D33D9ED8B7B95A9B285256C02E509D18115AAA0F6F104401F44931`
- JAR: `E1763417CF84A215613BDB76FCB1E3E1E00E11E39833FA8B7D3CCE6D48D2FC62`
- main Lua: `32CCAC46BDD0DB399EC63E9351AAED309B80B2ADC25326A66E10BADED55E6E39`
- enemy Lua: `7D0B6BB04D8A3DED75FE2FDE3110CBFF0F90B343190846EEC4EBB7B74C11F279`
