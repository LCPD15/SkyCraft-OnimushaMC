# 继续测试的停点 / Resume checkpoint

更新时间：2026-10-07。仅适用于本地鬼武者 OnimushaWotS 01.000.001、TDB 82，以及固定 REFramework 提交 b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。

用户已休息，今晚不请求人工操作，自动电脑输入保持停止。连续移动、MC玩家方块站立/拆除、原生攻击扣血、MC道具双向治疗及MC剑扣敌人HP已通过用户实测；原生受击反馈缺失。9164恢复血条显示/移动跟随，但转向仍固定。B274时序记录定位到app.CameraManager.lateUpdate结束时primary被覆写成原生方向/FOV41；用户随后F10关闭，原角色/操作恢复，input/draw/FOV和六项pending均为零。游戏与MC在02:50正常退出，MC记录saving worlds；03:20逐文件备份30项世界文件及原生存档。最终相机post重放及primary3失败回滚BC6A在04:00已安装，游戏未重启、尚未实测。敌人伤害配置10→100已安装；DLL/JAR仍保留已测版本。光照、碰撞/寻路、伤害平衡、处决及格挡研究已完成，见研究入口。

The user is asleep; manual testing is deferred and computer automation remains stopped. Health round trips and sword damage are confirmed; native reactions are missing. Lua9164 made bars visible and track movement, while turning still fails. B274 identified the lateUpdate overwrite. Both games exited normally, with a verified30-file world/native-save backup. BC6A camera replay/partial-write rollback and damage scale100 are installed, pending live acceptance. The tested DLL/JAR remain unchanged; newer render/Java candidates are staged separately.

## 文件和实测版本 / Files and tested versions

- 工作根目录：G:\Onimusha_MC_mod；用户指定 MC 目录中的 Onimusha_MC_mod junction 指向此处。
- 源码：source/SkyCraft，分支 onimusha-bridge；fork 为 LCPD15/SkyCraft-OnimushaMC。本轮修改保存于本地，未推送；提交身份以git log为准。
- 当前已安装、实测 DLL：5291E47D62D33D9ED8B7B95A9B285256C02E509D18115AAA0F6F104401F44931。
- 当前已安装Lua：BC6A61FA95E5714E33D55D3481D8326099DE8F3FCA088D9C1E20063F9417DB3F，outer lateUpdate post重放primary3+同owner6，失败事务恢复本帧原生XYZ/quat/FOV，失败项保留pending。15文件/126组及完整Lua54编译由root重跑通过，另有独立复核；没有实景结果。上个实测Lua为B274，103组、Reset正常、关闭pending0；历史副本均保留。
- 游戏配置：SHA256 7CF9611BC0D8BBE709FC3C593CADB705D7E128379DD3A92445833A2EBD762059；只改enemy_host_damage_per_mc_point10→100，stageC/接管关闭/实验碰撞及血量测试off保留，原玩家受伤/治疗百分比不变。源默认/A/B/C四份均100。
- 独立透明pass候选DLL：build/native-transparency/Release/OnimushaMC.dll，FC445437F870A5D09952A8F7935DFD7F9BC502336FF83F500661618DCB23ACA5；root补编译测试目标后完整CTest3/3通过无跳过，含正式mapping/API及WARP像素检查，未部署，不能继承5291的实景结果。
- 前版实测 DLL 8D9056… / Lua 1A6F… 的副本保留，不能将其游戏结论自动继承给新版。
- 已运行/安装 JAR：7BF4F2047463984252282420B9239666CA7AEC4DD685BB89E5F46D055C339851。
- 独立代理身份候选JAR：build/java-candidates/proxy-identity-20261007/skycraft-onimusha-0.1.0-dev.jar，8C823A4D00439AC9A01A6C6212AAFAEB4CF02CEDCF82ADFF3B5F818B6D3CCB1B；最终源码46项Java测试由root重跑通过，未部署。修复名称/会话旧代理，不改变伤害倍率和协议，也未解决原生事件环EV1跨epoch保护。
- 最终Java候选：build/java-candidates/guard-20261007/skycraft-onimusha-0.1.0-dev.jar，22004EBC1473787436FCD0205EE0A521133B34C8FA055FAF67815EFF40B99A5E；包含代理身份及MC剑组件/实际格挡减免观察/去重粒子。55项Java测试root独立重跑通过；可选剑能力默认false，既有盾的受控命中观察不靠该开关。未部署、未做实际Fabric客户端Mixin启动验证；可信攻击方向、原生guard反馈和结算ACK仍未接入。
- 当前独立世界：OnimushaMC-XYZ-v2；旧反射坐标世界 OnimushaMC 及其备份保留。
- 实测证据：logs/live-human-xyz-v2-20261006/；新版待测文件副本在 logs/live-human-handoff-20261006/。
- 安装追踪：runtime/deployment.json。源码或 build 输出改变不等于已经安装。

## 通过及未通过 / Evidence boundary

用户确认新版左右/上下视角、四向移动、跳跃、墙体/台阶碰撞、F5 三视角、两格背包点击正常，另确认物品放置正常。旧 GUI 修复版本的普通 F10 关闭后，原角色、移动和菜单恢复正常，input/draw/FOV 无待恢复项。Fabric 43 项测试、三项 native CTest 及坐标版45组 Lua 回归已有独立证据；这些结果不能自动继承给后续编译版本。

本轮已修复并实测：前版移动约8格刷新地形时立即清掉碰撞就绪，3178三角形按每帧1600导出需多帧，触发原绘制恢复。新版保留同epoch旧/新查询交集、整批原子排队并等待MC消费确认，用户连续移动不再闪回。24次刷新全部完成、失败/拒包0，无地形或连接退出；退出记录只有菜单和关闭桥接。62组Lua与三项CTest实际通过无跳过。非默认单位比例在native身体尺寸实测前暂拒绝接管。

新增原生方块Collider/RCOL创建与合成血量测试继续停用。方块站立仅证明MC玩家碰撞；用户确认原生敌人不能被方块阻挡。原游戏深度/光照尚未接入。剑击HP下降已确认；受击、死亡/破甲及世界UI更新仍未完成。当前敌人只枚举CurrentScene；输入owner替换、菜单/过场/场景切换继续待验收。

The tested binaries passed terrain handoff and MC-player block support/removal. Lua9164 passed91 cases and restored bars/movement, but turning failed. BC6A passed126 offline groups and is installed; its live UI result is pending. Sword damage, incoming native damage and healing are confirmed. Native hit reactions, guard/finisher integration, actual depth/lighting, NPC collision/pathing and scene/menu boundaries remain incomplete. Experimental collider creation stays disabled.

## 下一步 / Next steps

1. 明日先保持已测DLL/JAR，启动游戏、连接原XYZ-v2世界，再测BC6A转向UI及F10恢复。B274中update/late/preprocess各5399次；reflect_component虽5399但exact owned0，四投影方法0，不能声称已找到具体UI入口。BC6A只在fresh epoch/seq/frame/owner/ready/link/renderer/collision/MCworld认证后重放，不重复tick/player/input/HP/terrain。primary3事务全部成功即discard，失败保存本帧原生姿态并回滚；永久失效旧owner保留pending、需干净重启，详见RESTORATION.md。相机可写正确不保证UI最终投影时序已通过。
2. 修正已证实的代理名称残留与会话边界，独立JAR构建不替换正在运行的7BF4版本；受击效果需要验证原生伤害/反应入口，不能用setHealth冒充完整战斗。
3. 透明pass仅改善MC内部遮挡。真实RE主depth/HDR/light及NPC物理注册路线见ONIMUSHA-ENGINE-INTEGRATION.md，不开启已出现加载崩溃的实验allocator。
4. 倍率100先测一次同武器普通敌人实际HP变化，再核对致死/奖励；不用HP下降代替受击反馈。继续菜单/切场景验证。独立candidate-20261007包含BC6A/FC445/22004，打包不会安装DLL/JAR，也不继承旧实测；原dev包保留。
5. 格挡仍缺同次真实attacker方向，不能用最近敌人ID或hurt=false当成功。自然guard/普通hit、用户所指处决需要在F10关闭时有限只读样本；今晚不请求操作。候选剑默认没有启用，不给未知命中强制正面。接受伤害跨暂停/会话切换的settlementACK尚缺，不能简单放行旧EV6或以没有回执认定全挡。
6. 光照/遮挡、碰撞/寻路、伤害平衡、处决及格挡完整方案见[研究入口](ONIMUSHA-OVERNIGHT-RESEARCH.md)。导航完整障碍生命周期与真实GPU资源尚无证据，不能根据metadata直接启用旧allocator或猜descriptor/state。

原游戏存档及MC备份位于runtime/test-backups/和runtime/minecraft/test-world-backups/。最新before-camera-damage100-20261007-032056有30项XYZ-v2世界文件及原生存档，逐文件SHA256校验；save SHA2569A2493633540D8979CF02C0320688342CC4EF09B56AE5AD3C2C24F18C1C1EC6B。adapter-rollback-20261007-040022保留安装BC6A前的Lua/manifest，日志camera-damage100-installation-20261007.json及camera-final-installation-20261007.json记录实际安装。旧PCL、账号、MOD、旧世界和旧dev包保留。

MOD制作：LCPD15/LCPD拉灯
