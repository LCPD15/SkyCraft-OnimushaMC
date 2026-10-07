# MC → 鬼武者爆炸（开发测试）

仅适用于 OnimushaWotS 01.000.001 / TDB82，REFramework b6baf6b。
MOD制作：LCPD15/LCPD拉灯。其他 RE 游戏必须重新采样和适配，不能套用 ID 或参数。

## 已取得的证据

2026-10-07 用户原角色引爆油桶，探针记录了两个 `Gm019_000` 的连锁爆炸，
32 条前后置事件，无探针错误。原始记录在项目根目录
`logs/explosion-probe-20261007/barrel-user-capture-01-onimusha_explosion_probe_status.json`。
不得把记录里的进程地址作为新一轮游戏对象重用。

路径前缀：`GameDesign/Gimmick/Gm019/Gm019_000/Shell/`。
状态 `EXPLOSION=5` → `getExplosionShellID()=4` →
`mcGimmickCreateShell.createShell(4, info, callback)` →下一帧
`ace.cShellCreateController.shootShell(6, info, callback)` →
`shl_g019_000_004` →子弹体 `shl_g019_000_000` / `shl_g019_000_001`。
主 shell hash `3230905416`，主生命周期 1 秒。两个伤害子弹体生命周期各 0.4 秒，
使用 `Gm019_000_ShellAttackParamList.user` 中 0 / 1 号参数，禁止伤及所有者。

注意 `ShellCreatorInfo` 的 unique ID 4、fixed ID 6、数组下标 4 是三件不同的事。
本版本 `ShellList.getShellPackage(int)` 接收下标，不是 fixed ID。
实现通过 `_DataList` 查 `_FixedID` 获取资源包，并检查资源路径和 hash。

## 当前实现

- 复用 `ServerExplosion.explode`，覆盖 TNT、末地水晶等走标准 MC 爆炸流程的来源。
- `EV_EXPLOSION=3`：a/b/c 是 MC 中心、d 是原 MC 强度；formId 是事件号，weapon 是场景 epoch，flags=1。
- `SkyFlags` bit 7 表示本 epoch 的原生工厂就绪。现有 DLL 已支持原样转发 flags，无需更新 DLL 或改变 IPC 布局。
- Lua 用当前场景 tile 和单位换算还原原生坐标，拒绝旧 epoch、非有限数、非法强度、重复事件和远离玩家 128 单位的请求。
- 独立新建 `ace.cShellCreateController`，所有者是当前玩家；注册采样的资源列表。
  不移动、引爆或修改场景中已有的油桶。不修改共用 UserData。
- 每次创建全新的 shooting info，`OwnerAttachType=SHOOT_ONLY`，显式绝对位置和单位四元数。
- 原生 shell 负责鬼武者敌人、机关伤害与原生效果；MC 负责自伤、真实 MC 生物和方块破坏。
  子弹体已核对 `_EnableSelfDamage=false`，避免原生玩家与 MC 自伤重复。
- MC 只有在能力位有效且事件真正入队时才屏蔽该次爆炸的敌人代理伤害。
  嵌套爆炸使用独立作用域，异常退出会清理；队列满/能力未开放时保留 MC 代理伤害路线。
- 原生调用可能已执行却返回错误时，不重试、不再补一次扣血；关闭能力并记录 `unknown_no_retry`。
  这意味着不确定失败可能漏掉一次伤害，优先防止重复爆炸。查看记录后再重载。
- 本版保留油桶原始原生伤害、范围、效果；没有按 d 缩放子效果。MC 方块破坏仍用其原始强度。
- 原场景墙地不作为 MC 可破坏方块；机关是否会被炸坏仍遵守原游戏规则。

运行控制：`reframework/data/onimusha_explosion_control.json`；
结果：`onimusha_explosion_status.json`。爆炸代码和现有 `onimusha_enemy_hit.lua` 一起加载，
由同一个项目重载器管理。重载会等待当前原生攻击/爆炸尾段，不另建旧版 autorun。

## 铁傀儡与道具

新增通用目标 goal，让铁傀儡识别当前会话的鬼武者敌人代理（代理不可见是渲染策略，
目标识别仍检查视线）。沿用 MC 铁傀儡近战与通用原生受击入口，
`HIT_MC_MOB=32` 避免错误套用玩家 10 米近战距离；爆炸降级命中为 bit 16。
既有 fire bit 修正为 8，sweep 是 4，不能混用。
不代表鬼武者敌人能反向识别或攻击铁傀儡，也不代表原生寻路和 MC 方块已互通。

测试世界 `OnimushaMC-XYZ-v2` 已在 MC 正常保存退出后备份并新增：
TNT 3×64、末地水晶 64、黑曜石 64、打火石 1、铁块 4×64、雕刻南瓜 2×64。
只用空格，原 NBT 其他数据及原物品逐项验证不变；收据
`logs/explosion-golem-grant-20261007.json`。脚本带收据防重入，不要再次发放。

## 验证界限

已通过：真实油桶只读采样；原生工厂/资源/构造参数游戏内预检查；Fabric 编译和测试；
22 个 Lua 回归脚本（包括队列去重、旧会话拒绝、失败不重试、同时不同 TNT）；
3 个 Java 嵌套爆炸与异常清理测试。
待实测：MC TNT 原生生成位置、声光/原生伤害、自伤去重、末地水晶、TNT 连锁、
MC 方块破坏、铁傀儡主动选敌和命中。不得把工厂预检查报告成这些项目已通过。

2026-10-07 首轮实测补充：用户确认“爆炸能正常影响敌人，也能正常销毁方块”。
4 次 TNT 的原生主 shell 生成位置与换算位置完全一致；记录 Em104_00、Em106_00 原生伤害与 effect/sound 调用，
完整 HP 敌人每次收到原版爆炸的1500伤害。测试记录已保存在 `tnt-first-live-*`。
该确认覆盖 TNT 对原生敌人与 MC 方块；末地水晶、密集连锁、自伤去重及铁傀儡仍分别待验证。

铁傀儡首轮：用户确认近处敌人能被攻击、扣血，但铁傀儡不走动。
已定位 MC 路径查询只读实际空气块，未读原生地形碰撞，因此新增路径类型、地面高度、
目标表面扫描、稳定落脚点的原生几何查询。仅覆盖 MC 寻路，不改变鬼武者 NPC 导航。
薄地面和脚底可在同一 voxel，不能把所有非空形状都标为 BLOCKED。
候选新增 NativePathingTest 3 项通过；当前运行的 E176 JAR 尚不含这次寻路改动，待安装验证。
