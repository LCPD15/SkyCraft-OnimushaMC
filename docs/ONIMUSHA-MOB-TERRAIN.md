# MC 生物地形与连续区域修复 / Mob terrain and continuous areas

2026-10-07。仅限 OnimushaWotS 01.000.001 / TDB82。MOD制作：LCPD15/LCPD拉灯。

后续实测：用户确认铁傀儡站立和寻路正常、原13/14边界不再闪断。
另一位置的接管中断已确认是地形转换上限，见 ONIMUSHA-DYNAMIC-TERRAIN.md；
以下“待复测”为本次候选首次交接时的历史记录。

## 失败证据

寻路候选 799536 的游戏实测失败：地面直接生成铁傀儡会掉落；拆掉垫块后有悬空；
区域间移动会闪回原角色。不能把该候选的编译/路径单元测试当作游戏通过。
`logs/golem-fall-stream-20261007-185910/` 保存原始日志和只读碰撞环快照。

实体 188/189 等持续下降到 Y=-1700 以下。对应碰撞数据存在，但脚底位于原生地面内部：
例如 MC (65438,0,244) 的地面占体素层 1/2，(65438,0,238) 占层 3/4。
普通 MC 方块碰撞不会将已嵌入的实体推出；此前只有本地玩家使用精确三角面并校正生成高度。

八次失去接管中七次是 Stage transition，区域 13/14 在同一走廊坐标边界反复变化，导致
MC X 在 57344/65536 两个平移区间间切换、epoch 递增、资源清空重传；一次是地形刷新尚未
消费时身体/下方支持探针越出已确认查询区域。没有证据表明是助手计算预算造成。

## 修正

服务器端普通 MC Mob 使用 NativeMobPhysics/TriCollider，对接与玩家相同的原生三角面，
保留 MC 的速度、重力、跳跃和伤害；三角面修正后再次检查真实 MC 方块，避免台阶修正穿入方块。
首次加载/生成时，仅向上校正最多 1 米内的可站立地面；不会每帧向上吸附。
原生地形尚未知、会话不匹配、加载中或连接断开时暂停相关 Mob 模拟，恢复地形后再继续。
这里的暂缓不是关闭实体重力或写入 NoAI。原生敌人代理 noPhysics 不进入该处理。

相邻区域的坐标合并必须先离线迁移已有数据，不能直接将所有 AreaID 删除或忽略。
`Merge-Verified-Areas.py` 只处理有实测连续性证据的 stage:0:area:14 -> stage:0:area:13，
拒绝复杂方块、实体/POI、结构和非空目标区块冲突，先验证完整备份，再原子写入区域文件。
当前世界仅一个有方块的区块由 (4089,16) 迁至 (3577,16)；迁移前后逻辑记录仅两处差异，
其他区块 NBT、玩家背包及已有铁傀儡保持一致。别名保存在游戏 data/onimusha_mc_world_aliases.json。
该文件是此存档的迁移结果，不是适用于所有用户的默认配置，不打包分发。
其他区域、其他关卡仍独立处理；不能未经坐标验证或迁移就继续添加别名。

## 验证与范围

- Fabric build / 61 个现有 Java 单元测试通过；23 个 Lua 回归脚本通过。
- 新增连续区域回归执行实际 choose_world：13/14 连续交替 50 次不改 epoch/传送序号，真实
  stage 变化仍重置；跨 stage/不存在目标/链式别名被拒绝。
- 实际 MC 26.3 / Fabric 隔离世界 `OnimushaMC-MobSmoke-20261007b`，独立 IPC
  `Local\OnimushaMC_MobSmoke`，没有键鼠自动输入，没有触碰用户游戏存档。
- 嵌入地面生成：Y=65 -> 65.375，稳定站立。
- 先放真实 MC 石块支撑于 Y=67，删除后落至原生地面 Y=65.375，不悬空。
- 铁傀儡从 X=0 寻路至 X≈8，主动攻击代理；独立原生主机收到多次 EV_HIT_ACTOR。
- 三项结果日志均 true；主机退出后 MC 正常保存退出。
- 第一轮 smoke-a 用 NoAI 固定测试体，误停了 vanilla travel/gravity，垫块测试无效。
  smoke-b 改为只清除测试体 goals，保留真实物理；保留两轮日志，不抹去失败记录。

日志 `logs/mob-smoke-b.stdout.log` 和 `.host.log`。这证明真实 MC 路径/碰撞钩子运行，
并不替代鬼武者复杂地形、墙壁、楼梯与区域边界的用户实测。后者尚待复测。
地形查询真实越界仍会安全归还原游戏控制；本次没有关闭这一保护或无条件延长断连时间。

English: MC mobs now use authoritative server-side triangle collision and bounded spawn
depenetration. Unknown streamed ground suspends simulation instead of allowing void falls.
An isolated real Fabric runtime passed spawn support, removal of a real support block, and
walking toward/attacking an enemy proxy. Only verified seamless areas 13/14 were merged after
an offline, hash-verified backup. Native-game terrain and boundary retests are still pending.

仍未实现：鬼武者 NPC 对 MC 方块的原生碰撞/寻路、原生光照/深度整合及处决。
