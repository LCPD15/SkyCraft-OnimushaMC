# 继续测试的停点 / Resume checkpoint

2026-10-07。仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。其他RE游戏另行适配。

## 当前操作与要求

MC格挡正常且有音效、正常受击扣血、F10关闭恢复已由用户确认。现处理敌人原生受击反馈。所有敌人共用逻辑，不逐敌人／招式适配；最新要求采用两套全局模板（普通轻击、用户演示的特殊攻击），MC命中时随机选择。敌人格挡由原生判定，特殊不可防御攻击对MC的弹反处理仍暂缓。

双模板补录已成功：用户确认两次均命中，报告native-enemy-two-capture-08.json，initialized=true、零错误、两个独立模板。已提出、等待回复的操作：无需Reset，F10开启，用MC剑只打一次普通小怪，观察动作/声音/特效/HP，停手5秒并保持开启。不要重复提问。上一轮用户三次攻击未取得模板：新增模块初始化时误用不存在的REField.get_offset，已改为固定SDK的get_offset_from_base并增加执行初始化的测试。不能把旧日志地址复活为临时参数。

当前游戏PID34456，MC PID94796；使用前再次验证实际路径。MC启动含-SwordBlocking -StartHidden -QuitWithHost，世界OnimushaMC-XYZ-v2。自动电脑输入仍停止，游戏操作由用户执行。用户已授权结束游戏进程；必须验证身份，不能杀复用旧PID的无关进程。

## 文件与边界

| 文件 | SHA256前缀 | 状态 |
|---|---|---|
| 游戏DLL | 5291E47D62D3 | 当前实测，不改 |
| MC JAR | 22004EBC1473 | 真实Fabric启动通过，格挡声音和受击扣血通过 |
| 前版生产Lua | 466822F798B2 | 精确同击来源已实景通过，备份保留 |
| 当前磁盘生产Lua | DFA40187E9CA | 新增可选原生队列分派，已随双模板补录Reset加载 |
| 敌人试验模块 | 7B671B0A815A | 双模板已捕获，单击试验armed，尚无MC命中 |
| 只读guard/flow探针 | DA60A701BA4E | 默认disarmed，metadata06已读取 |
| 启动脚本源码及副本 | 2F30A6A69FFA | 剑开关和旧PID实际Java身份检查 |

完整hash见runtime/deployment.json及实物。磁盘更新不等于加载或验收。配置stageC、接管关闭、伤害倍率100、实验原生Collider和血量试验off。候选透明DLL FC445未安装；旧candidate-20261007包不含本轮新Lua。

onimusha_enemy_hit_control.json当前mode=trial，id=generic-native-hit-20261007-04，templates=[1,2]，remaining=1。最多捕获8个自然玩家命中，使用引擎duplicate创建独立runtime，Lua保有引用；不改原资产，不记录敌方攻击为模板，不主动请求伤害。试验模板仅本次Lua会话有效，重载/重启后需要重建；还不是正式可发布方案。

18个Lua回归脚本通过；此后增补的combat_telemetry为14组、native_enemy_hit为10组，均通过。日志logs/lua-regression-native-hit-20261007.txt是增补前那轮18脚本记录。Java55项已有证据，DLL未变。离线测试不等于游戏验收。

## 下一步

1. 收到单次MC剑击回复后立即保存onimusha_enemy_hit_status.json和主适配器status、MC日志。普通模板index1（Attack100/Rikido150/Break75），特殊index2（300/450/300），uid14/15，用户顺序已确认。首次MC原生命中尚未发生。
2. 该报告metadata含calcDamage、collectAttackParamData等真实方法地址和字段偏移。只读反汇编已证明目标实体stockDirectDamage长重载自行生成并入队；禁止再调用StockDamage模块重复入队。两个GO为attacker与attack object，receiver来自目标实体。
3. calcDamage反汇编已验证FixedDamageAttack参与最终结算，加上原生倍率/防御；clone设Attack=0、FixedAttack=MC伤害×100。须核对实际stock和HP，不能同时setHealth。新原生接口尚未实际调用。
4. 控制文件新id、mode=trial、templates=[两个确认索引]允许一次MC命中，随机选择模板；预算耗尽拒绝额外命中。入队结果不明不重试、不回退手动扣血。请用户只打一次，核对声音/特效/动作/HP和native_pre/post记录，再继续。
5. 原生双模板试验通过后仍需资产来源与场景变更重建、持久配置、伤害事务ACK；不要把每次靠人工播种的试验版当成完成。

## 已有证据和未完成项

- 本轮6次实际vanilla格挡blocked=incoming、HP不变、blockingCalls=1。两次未格挡hurt=true，后一击EV6使HP1756→1615。同击来源actor4/18，9次匹配无错。用户确认格挡、声音、扣血，红闪/击退/火花未逐项确认；第一人称受击相机倾斜未传输。
- logs/live-camera-bc6a-20261007/combat-source-guard-active-05.json及combat-source-user-restored-05.json。后者active=false、Bridge disabled、last_error=null。MC日志live-guard-feedback-20261007.stdout.log。
- BC6A转向任务图标/血条跟随、F10恢复已用户通过；当前相机算法未变。7MC→700原生HP已实测，致死奖励/破甲未验收。
- 3C、F5、背包鼠标、持续移动不闪回、MC方块站立/拆除通过。原生NPC碰撞/寻路、真实RE深度/光照、处决、完整敌人反馈及跨会话伤害ACK未完成。私有碰撞几何深度不等于RE主深度；实验物理创建器保持off。
- 自然guard03、flow04、combat-types-live-06和stock/duplicate只读反汇编在上述logs目录。Inspect-Native-Code.py只用查询及VM_READ权限，不写内存或调用远程函数。

## 目录与备份

项目G:/Onimusha_MC_mod/source/SkyCraft，分支onimusha-bridge，fork LCPD15/SkyCraft-OnimushaMC，未推送。用户MC目录的junction指向工作根目录。游戏F:/SteamLibrary/steamapps/common/OnimushaWotS。

4×64普通金苹果已添加并获用户确认，不重复发放。logs/golden-apples-grant-20261007.json；完整世界备份before-golden-apples-20261007-135228。安装前世界29文件及旧文件备份before-combat-feedback-20261007-143930；Lua466822回滚副本runtime/test-backups/before-native-hit-trial-20261007。运行中不直接改存档。

研究入口[ONIMUSHA-OVERNIGHT-RESEARCH.md](ONIMUSHA-OVERNIGHT-RESEARCH.md)。此前完整停点存于logs/resume-before-native-hit-20261007.md。保留旧PCL、账号、游戏存档、MC世界与旧包。

Generic MC block sound and incoming hurt passed live testing. Native enemy feedback is a bounded experiment with two shared random attack profiles. No native enqueue has been tested. Preserve no-double-damage behavior and distinguish installed, loaded and verified versions.

MOD制作：LCPD15/LCPD拉灯
