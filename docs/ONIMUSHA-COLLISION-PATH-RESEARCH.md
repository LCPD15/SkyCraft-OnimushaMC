# 鬼武者原生方块碰撞与寻路研究 / Native block collision and pathing research

更新 / Updated: 2026-10-07. **只适用于当前 OnimushaWotS 01.000.001 / TDB82**。其他 RE 游戏的物理资源格式、过滤层、组件生命周期和导航接口必须另建适配说明。

MOD制作 / Onimusha adaptation: **LCPD15/LCPD拉灯**. Upstream: **chasmlol / SkyCraft**, MIT. 保留原项目许可及归属；下面是适配研究，不代表原作者已支持 RE 引擎。

**当前结论：MC 玩家能站在 MC 方块上已实测；原生敌人被方块阻挡、原生碰撞世界注册、AI 绕路均未通过。** solid bitset 已到达原生桥接层，但不会自动生成 RE 物理对象或导航障碍。今晚只读取既有源码、日志和缓存，没有启动游戏、修改 live 配置、开启 probe 或运行曾失败的 allocator。

**English:** Minecraft-side block collision is working. Native enemy blocking, engine-world registration and AI rerouting are separate, still unverified features. The existing occupancy messages and offline RCOL readback do not prove any of them. This document specifies evidence and staged acceptance; it is not a deployment recipe for the disabled experimental allocator.

## 证据与判定级别 / Evidence levels

| 标记 / Level | 能证明什么 / What it proves |
|---|---|
| Source | 本仓库实际代码所做的操作；不自动证明运行时有效 |
| Metadata | 本地 TDB82 缓存中存在精确方法签名；不证明参数含义、线程、所有权或调用顺序 |
| Offline | 文件序列化/readback 或隔离 IPC 测试通过；不证明游戏 world 注册 |
| Live | 真游戏内观察；必须区分射线、角色接触和寻路三个单独结果 |

来源：

- [原版 DigPhysics](../skse/src/DigPhysics.cpp)、[NpcBlocks](../skse/src/NpcBlocks.cpp)、[PathAvoid](../skse/src/PathAvoid.cpp)。原版 AE 专用 hook 地址不能用于 RE 游戏。
- [当前 WorldExporter](../fabric/src/client/java/dev/skycraft/client/render/WorldExporter.java)、[RenderStore](../onimusha/native/RenderStore.cpp)、[Lua adapter](../onimusha/adapter/onimusha_mc.lua)。allocator 代码保留作失败路线参考，默认关闭。
- [绑定边界](onimusha-bindings.md)、[验收记录](ONIMUSHA-VALIDATION.md)、[引擎接入边界](ONIMUSHA-ENGINE-INTEGRATION.md)。
- 本地只读缓存 `F:\SteamLibrary\steamapps\common\OnimushaWotS\reframework\data\onimusha_mc_probe_types.json` 和 `onimusha_mc_probe_snapshot.json`、`_1` 至 `_30` 的 `discovered_types`。它们是部分类型缓存，不是完整 TDB。
- 缓存读取时 SHA256：types `BC4C21937B6BC1FC12EBC7D38493D52286EF8981112F0EBE44C237D35202B6D7`；无后缀 snapshot `231D38396487F7577C0F0C4C83156E8B72FFE024E326862F875DE6106948D70F`。这些文件会被后续 probe 更新，不能仅凭路径当作固定历史版本。
- 崩溃历史：`G:\Onimusha_MC_mod\logs\game-crash-20261006\re2_framework_log.txt` 及同目录 status；后续放置/站立/拆除证据在 `logs/live-human-handoff-20261006/status-after-build-collision-removal-pass.json`，证明范围是 MC 玩家。

## 原版有三个独立机制 / Three distinct upstream mechanisms

| 机制 | 实际实现 | RE 迁移含义 |
|---|---|---|
| Havok 角色接触与支撑 | `DigPhysics::ProcessConstraintsHook` 先调用原 solver callback，再按 MC solid cell 生成 capsule 对 block 的约束平面，受 `userPlanes` 容量限制；contact collectors 过滤挖掉的原地形；另处理原地形高度救援 | 这是约束注入，并不是通用“新增实体即可 world 注册”。RE 缓存没有已验证的自定义角色约束写入入口。原生地形拆除在本 fork 仍禁止 |
| NPC 排斥/贴墙移动 | `NpcBlocks::PushActorsOut` 读取附近高活动 actor，解 circle/cell overlap，多次推离；结合路径目标选择墙边方向，最后直接 `Actor::SetPosition` | 这是局部位置修正，不等同引擎碰撞，也不等同 AI 寻路。照搬会与 RE root motion、击退、斜坡、特殊行动冲突，不能据此宣称物理注册通过 |
| AI 寻路避让 | `PathAvoid::SetupPathHook` 为路径请求保留原 avoid nodes，再追加最多 96 个 MC block column 的高代价 cylinder；AE ID 41642 的七个 callsite 经校验后 hook；refcount 数组按原引擎释放规则管理 | 独立改变 path request，才是绕路来源。实体碰撞即使成功也可能只让敌人顶墙，必须另找到 RE 的导航障碍/路径请求生命周期 |

**English:** Upstream uses solver planes, local push/slide correction and path-request avoidance separately. A port must not present NPC displacement or collision contact as proof of navigation rerouting.

## 当前 solid 消息的精度 / Occupancy precision

MC `WorldExporter` 对每个非空 `BlockState.getCollisionShape` 设置一个 bit：`x + 16*z + 256*y`。`REN_SOLIDS` 每 section 携带 4096 bits；`RenderStore` 比较新旧 bitset，生成增删 cell，clear 时产生 removal。

它只表示 cell 内有碰撞，不包含实际 AABB/面片。将所有 bit 都变成完整 unit box，会错误封死半砖、楼梯、栅栏等方块的空隙。第一阶段应只验收普通完整立方体（例如石头），后续精细碰撞需额外导出/合并实际 shape，不能从 solid bit 推断它。液体、纯装饰、渲染网格也不能直接当碰撞 shape。

现有坐标为已验证的 **identity XYZ**：MC cell 经当前 tile 与 `units_per_block` 变回原生 world；默认 1 block = 1 native unit。新对象必须绑定 scene/world/epoch/connection generation，不能复用旧反射 Z 坐标存档或别的场景的 cell 记录。

## 原生创建与注册候选 / Creation and registration candidates

以下均为 **Metadata**。缓存的方法参数名是 null，UInt32 的具体角色由自然运行观察和结果回读确认；不得猜索引、Group/RequestSet ID、偏移或默认值。

| 类型 | 精确签名 | 证据与缺口 |
|---|---|---|
| `via.GameObject` | static `create(System.String, via.Folder) -> via.GameObject`；`createComponent(System.Type) -> via.Component`；`get_Folder()/get_FolderSelf() -> via.Folder`；`get_Valid() -> Boolean`；static `destroy(via.GameObject) -> Void` | 有 folder 显式 owner 的候选路径；单参数 create 曾使用，但正确 scene/work-rate 初始化未证。不能把返回非空等同合法注册 |
| `via.Scene` | `findComponents(System.Type) -> via.Component[]`；`findFolder(System.String) -> via.Folder`；`get_Folders() -> IEnumerable<via.Folder>`；`findGameObject(System.String, via.Folder) -> via.GameObject` | 可用于未来只读检查真实 owner 和 scene 可见性。当前没有缓存到通用 `Scene.addPhysicsActor` 或 `System.registerBody` 接口 |
| `via.physics.RequestSetCollider` | `setRequestSetGroupsCount(UInt32) -> Void`；`getRequestSetGroups(UInt32) -> RequestSetGroup`；`registerRequestSet(UInt32, UInt32) -> Void`；`unregisterRequestSet(UInt32, UInt32) -> Void` | component/resource 驱动路径最接近已有引擎机制，但尚无成功 live 注册记录。返回 Void 不能当 ACK |
| 同上 | `isRegisteredRequestSet(UInt32, UInt32) -> Boolean`；`isRegisteredRequestSetFromIndex(UInt32, UInt32) -> Boolean`；`hasRequestSet(UInt32, UInt32) -> Boolean`；`getCollidableFromIndex(UInt32, UInt32, UInt32) -> Collidable`；`getCollidable(UInt32, UInt32, UInt32) -> Collidable`；`updatePose(UInt32, UInt32) -> Void` | 必须区分 ID 与 index：旧 `(0,0,0)` 是实验索引，不是已认证的通用规则。须从真实 group/resource getter 获得 ID并交叉核对 |
| `RequestSetCollider.RequestSetGroup` | `get_Id() -> UInt32`；`get_Resource()/set_Resource(RequestSetColliderResourceHolder)`；`get_Initialized() -> Boolean`；`get_NumRequestSets() -> UInt32`；`getRequestSetIdFromIndex(UInt32) -> UInt32` | 应先证 resource holder 生命周期、初始化结束和真实 request-set 数量，再注册；不能只等待固定帧数 |
| `via.physics.ColliderSet` | `get_Resource()/set_Resource(ColliderSetResourceHolder)`；`getCollider(UInt32) -> Collider`；`get_Ready() -> Boolean`；`get_Static()/set_Static(Boolean)` | 替代资源 component 候选，未做 live 实验；没有证据可以任意写 collider 数组或裸复制原组件 |
| `via.physics.Collidable` | `set_GameObject(via.GameObject)`；`set_Shape(via.physics.Shape)`；`enable()/disable()`；`get_FilterInfo() -> FilterInfo`；`get_BoundingAabb() -> AABB` | standalone allocation 实验未通过身份射线。`enable` 只可视为方法存在，不足以证明进入 broadphase |
| `via.physics.Collider` | `get_Ready() -> Boolean`；`set_UpdateShape(Boolean)`；`set_CollisionFilterResource(CollisionFilterResourceHolder)` | shape Ready、collider Ready、owner Valid 和 world hit 是不同检查 |
| `via.physics.BoxShape` | `set_Box(via.OBB)`；`set_Extent(via.vec3)`；`set_Coord(via.mat4)`；继承 `Shape.dispose() -> Void` | shape 可以表达 OBB，不代表构造/绑定/释放顺序已安全。不能在 worker 仍使用时 dispose |

物理查询的已缓存精确接口：

```text
via.physics.CastRayQuery.copyFilterInfo(via.physics.FilterInfo) -> Void
via.physics.CastRayQuery.enableAllHits() -> Void
via.physics.CastRayQuery.enableNearSort() -> Void
via.physics.CastRayQuery.setRay(via.vec3, via.vec3, System.Single) -> Void
via.physics.System.castRay(via.physics.CastRayQuery) -> via.physics.CastRayResult  [static]
via.physics.CastRayResult.get_NumContactPoints() -> UInt32
via.physics.CastRayResult.getContactCollidable(UInt32) -> via.physics.Collidable
```

射线只能证明某个 filter 的查询命中新对象。必须比较返回 collidable 的身份/owner，不能把附近原地形或其他物体的命中当作新增方块。它仍不证明角色 controller 会与该对象接触。

`via.physics.System` 还存在 `get/set_MakeRequestSetColliderDependentOnGameObjectUpdate`、`get/set_RequestSetColliderInitializeOnTheFly`，但它们是全局设置；不能为了让实验“跑起来”改变全场景默认行为。已有静态资源、RCOL 和 component constructor 的合法初始化顺序应从原生正常对象中观察。

## 角色 controller 与 filter / Character contacts and filters

确证的类型链：`app.cCharacterPhysics.get_Components() -> cComponents`，`cComponents.get_CharacterController() -> via.physics.CharacterController`；后者继承 `CollidableBase : via.Component`，不是 `Collidable`，不能将 standalone Collider 的方法直接套给 controller。

| 精确方法 / Exact methods | 用途与边界 |
|---|---|
| `CharacterController.get_FilterResource() -> CollisionFilterResourceHolder`；`get_FilterInfo() -> FilterInfo`；`overwriteFilterInfo(FilterInfo)`；`restoreFilterInfo()` | 可以未来观察玩家和普通敌人的真实过滤配置；覆盖会改变原生接触，必须记录、恢复并保持默认关闭 |
| `FilterInfo.get/set_Layer(UInt32)`、`Group`、`SubGroup`、`IgnoreSubGroup`、`MaskBits` | 层号和掩码语义尚未有实值记录。不能设全 mask、复制任意 ground filter 后就宣称玩家/敌人/攻击 query 都兼容 |
| `get_Position()/get_OriginalPosition()/get_LocalOffsetPosition() -> vec3`；`get_Height()/get_Radius() -> Single` | 观察实际身体 envelope 和运动结果。height 是否含两端 capsule、offset 的应用方式仍需量测；不要改变原角色尺寸来掩盖碰撞失败 |
| `get_Ground()/get_Wall()/get_Ceiling() -> Boolean`；`get_NumGroundContactPoints()/get_NumWallContactPoints() -> Int32`；`getGroundContactPoint(Int32)/getWallContactPoint(Int32) -> ContactPoint`；`getWallGameObject(Int32) -> GameObject`；`get_FloorGameObject() -> GameObject` | 方块阻挡/站立验收需要真实 contact owner，加上连续运动记录；不能仅以画面上没穿过或 MC 的 onGround 判定原生碰撞 |
| `get_OverwritePosition()/set_OverwritePosition(Boolean)`；`warp() -> Void` | 与原生角色运动/写位置关联。不是方块注册或寻路入口，不应随意 warp 敌人来实现“碰撞” |

`app.cCharacterPhysics` 的 `applyVelocity()`、`adjustMotionRootDelta(vec3, Quaternion)`、`onWorldOffset(vec3)` 等存在；`app.mcCharacterResizeTerrainCollision` 也能重设角色尺寸。它们都不是新增障碍或 path request API。接管中的玩家由 MC 运动驱动，原生玩家关闭接管后又回到 RE controller；两种状态需分别验收。

## 导航缓存能证明到哪里 / What navigation metadata actually establishes

在 types 及全部 31 个既有 snapshot 的静态搜索中，找到 `via.navigation.AIMap`、`AIMapEffector[]`、`AIMapSection[]` 及对应 generic List；没有得到 effector/section 基类完整方法、navigation manager handle 生命周期或敌人 path request 类型。

`via.navigation.AIMap : via.Component` 的确切方法：

```text
findMapHandleBase(System.String) -> via.navigation.MapHandleBase
getManagers(System.UInt32) -> via.navigation.SectionManagerHandle
getManagersCount() -> System.UInt32
hasLoadingMap(System.UInt32) -> System.Boolean
get_Managers() -> via.navigation.AIMap.WrappedArrayContainer_Managers
get_SectionMatrixType() -> via.navigation.map.VerticesMatrixType
set_SectionMatrixType(via.navigation.map.VerticesMatrixType) -> System.Void
```

这说明场景有分区地图/manager 查询，不说明能够创建可移动障碍、重建地图或修改 path cost。数组/List 的 `Add/Remove/Clear` 是集合元数据，不是合法导航注册；也不能用 `set_SectionMatrixType` 试图添加方块。

`app.cPlayerNavigationSupporter` 的 `shootNavigationShell`、`getPinInfo`、`getBeaconInfo`、`isUsableNavigation` 与其 `_Shell`、beacon/pin 字段表明这是玩家指引系统。`app.user_data.cNaviParam` 仅有 `_MaxRequestNum`/`get_MaxRequestNum`；它们不是已经找到的敌人路径避障接口。

**尚缺 / Still required:** `AIMapEffector`、`AIMapSection`、`MapHandleBase`、`SectionManagerHandle` 的实际类型与 owner、动态障碍注册/更新/移除入口、敌人实际请求器和目标/返回路径、actor radius 与 traversal flags、地图异步加载/卸载/worker barrier。当前缓存没有这些完整签名，不能虚构 `addObstacle` 或将其他 RE 游戏的地址/枚举照搬。

**English:** Metadata search found map-manager lookup only. Collection mutators and player navigation beacons are not obstacle-registration APIs. Physical blocking and AI rerouting must pass independent acceptance tests.

## 已失败路线与历史崩溃 / Failed routes and crash boundary

1. standalone `GameObject + BoxShape + Collider`、复制 ground filter、enable 的第一次实景实验 **未通过 exact-identity castRay**。原因未确定：world/scene owner、组件初始化、filter、shape transform 或生命周期都仍可能有关。
2. `unit_box.rcol.37` 为 602 bytes；offline readback 是 1 group / 1 request / 1 Box。SHA256 `EF960A2FA390D564E3A1CBFCC0FC393D4D9D810D316916B544054B5D2EE065AC`。CRC/readback 只证文件结构，不证明 resource holder 初始化或物理 world 注册。
3. resource-holder/RequestSetCollider fallback 没有成功 live 注册记录。等待 `get_Initialized`、调用 register、再取 collidable 的旧代码仍是实验路线。
4. 2026-10-06 00:55:07 combined build 在加载期间崩溃：游戏 exe `+0xFC00B1B`、RCX=0，既有 dump 分析为 null+0x70；stack 涉及 WorkRate 与 Raycast。那时 MC 未连接、接管/renderer 未开启，但开启了新增 collider 测试。**不能唯一归因 RCOL 或某个 constructor**；回滚关闭后恢复进场景，也不证明是哪一个参数错误。
5. 后来 GetAreaPrimitiveQuery/Result 的 add_ref 与碰撞 export 生命周期修复，仅证明已有查询对象路径，不能当作新 resource-holder/collider 的 lifetime 认证。

两种 allocator 和 collider tests 继续 off。不得直接重新开启旧代码，也不得加 global ignore/filter/force-update 来绕过失败。

## 对象生命周期要求 / Ownership and lifetime requirements

以下是待验证的设计约束，不是已认证调用顺序：

- cell 对象记录应含 `scene identity + stage/world + host epoch + native/MC generation + cell key + revision`。创建、pose 更新、删除只能处理自己创建的对象，不能修改原地形的 group/resource。
- MC 放置：只在已认证 owner、加载完成且允许的引擎阶段建立对象；保留 GO/component/holder 的有效引用；等初始化结束、实际注册状态、身份射线成功后才标记原生碰撞可用。
- MC 拆除：先撤销注册/参与过滤，等待引擎完成相应更新，再销毁自有 GO/释放自有 shape/holder；验证新射线无该 owner，原生角色可通过。Void setter 不是销毁完成 ACK，不能随后继续解引用已释放对象。
- 切场景、world offset、Reset、断连：停止旧 worker/提交，撤销本 session 的 collider/nav obstacle；有正式解除/更新完成证据后清理引用。不要把已卸载 scene 的 holder 指针放进永久 global。
- 关闭接管：决定自有 world 方块是否仍应存在，分别保持碰撞/导航一致。不能只隐藏 renderer 而遗留无形墙，或仅取消碰撞却留下 AI 障碍。离开/重连必须重建可认证的对象清单。
- 部分创建/初始化失败：整条新增碰撞功能保持 unavailable，显式报告对象/阶段/错误；不要将部分注册叫作完整成功。限制对象数、每帧创建/删除数以及重试次数，先验单个完整立方体。

## 最小分阶段原型与明日步骤 / Staged prototype and next supervised tests

| 阶段 | 实现前必须取得的证据 | 后续验收，不在今晚执行 |
|---|---|---|
| P0 只读自然对象 | 一件普通场景静态碰撞物的完整 GO/folder/component/group/holder/filter 身份与初始化/销毁调用顺序；玩家和一只普通敌人的真实 controller/filter；AIMap 实际 manager/effector 类型 | 独立 bounded probe 自动停止，不跳过原函数、不改 filter。先取得 getter/方法签名和参数语义；不能用读取地址推导裸结构 |
| P1 一个自有物理立方体 | 选择经自然对象证明的 scene-owned component/resource 创建路线与安全引擎阶段；有效 owner、Ready/Initialized、注册状态和完整 cleanup | 离玩家/敌人不接触的加载区域放一块石头；使用真实 controller filter 的 raycast 命中**自有 collidable 身份**；拆除后无该身份命中；切场景/Reset 后无残留。失败即停，不扩展到整 section |
| P2 原生角色身体碰撞 | P1 完整通过，再确认玩家/敌人的 collision pair rules、连续运动和 contact owner | 关闭 MC 接管，以原生玩家走向/站上方块，再让普通敌人走向一堵短墙；读取 wall/floor owner、位置/速度。挡住但持续顶墙只算碰撞，不算绕路。拆方块后正常通过 |
| P3 动态导航避障 | 实际敌人请求器与 path/goal getter、地图 manager、动态障碍注册/更新/取消签名、worker/lifetime 规则已补齐；不能仅凭名字创建 AIMapEffector | 短墙留一条可通行路，保持目标在墙后；敌人自行规划并绕到目标；记录返回路径/请求及行为。拆除后路径恢复，换场景后无旧障碍。位置推离/强制转向不算通过 |
| P4 多方块与精细 shape | P1–P3 全部通过，再导出真实 MC shape、合并重复/内部面，加入动态放置/删除 revision | 楼梯/半砖/门开关、窄门、堆叠/桥面、多个敌人、载入卸载和较多方块的性能与恢复。每一类单独列结果，不因石头测试通过就视作全部支持 |

明日最少的人工动作：先选择安全场景和一只普通近战敌人，完成一块石头的创建/拆除；再以原生玩家测试接触；最后短墙追踪测试。P0 尚未补齐时只观察原场景对象，不运行旧 allocator。每一步保留版本/hash、scene/epoch、对象身份和结果；用户可以随时停止，默认恢复所有自有修改。

**English acceptance:** A ray hit, a controller contact and a rerouted path are three separate milestones. Pass registration/removal first, native body blocking second, navigation rerouting third. Do not activate the old allocator before its ownership and initialization gaps are resolved.

## 纯离线形状协议扩展设计 / Offline shape-channel proposal

**设计草案，尚未实现。** 本节没有修改 `protocol/skycraft_protocol.h`、`Proto.java`、DLL/JAR、mapping 或配置，也没有创建原生对象。其目标是完整表达 MC 方块碰撞形状与增删状态；它不能解决上述尚未认证的 RE world 注册和导航入口。

### 为什么选择可选旁路 / Why an optional side channel

当前主协议版本是 **12**，`SkyLink` 要求 magic/version 精确匹配；当前 `RenderStore::consume` 对未知 render type 计 invalid。`REN_SOLIDS` 只有 section 坐标、count 和 bitset，没有 session、section revision 或应用结果。`REN_SECTION`、`REN_SOLIDS` 分开写入，单个 `writeRender` 成功仅表示消息已入 ring。因此不能给现有 solids 尾部直接加字段、占用未知 type、复用 `REN_DUG`，或声称旧端可自动忽略扩展。

最小兼容建议是独立、默认关闭的 sidecar，例如 **`Local\OnimushaMC_Shapes_v1`**（仅候选名称）：独立 magic、major/minor、mappingBytes、双向能力握手和有界 ring。保留主 mapping 的 v12 字节布局与行为；两端确认仍连接到同一个主 mapping、进程和 host session 后才启用。只有一端支持或 major 不匹配时，只关闭新增原生碰撞/导航功能，原有 MC 碰撞、网格、HUD 和输入继续按现协议运行。**不要把 legacy solid bits 降级解释成精确 unit boxes。**

若将来选择合并进主协议，应同时更新 native/Java 与所有隔离测试并 bump 主版本；这意味着旧 v12 端将明确拒绝连接，不是本草案的后向兼容路线。minor 只能增加已协商的可选能力，必需字段/语义改变必须 major 升级，未知必需能力不得接受。

### 形状来源与最小范围 / Shape source and first supported profile

形状来自 **集成 MC server 的已提交 BlockState + 相邻世界状态 + 明确的 CollisionContext**，在 server 线程构建纯数字 snapshot；不得让渲染线程、atlas/mesh 是否成功或 client 预测状态决定原生物理。可复用 dirty 通知，但 shape export 需独立重试、scope 和 revision。源方块被放置/拆除、门开关、邻居变化和 section 边界变化时，重新计算受影响 section。chunk 卸载要发送明确 scope removal，不沿用现有 renderer 的“unloaded: keep what it has”。

首个 profile 建议只接受经离线测试确认的 **静态、与具体 actor 无关的 AABB union**：完整方块、普通半砖/楼梯、当前开关状态的门、按邻居确定的栅栏。它们仍需逐类验证，名称白名单不等于已经实现。使用真实 `VoxelShape` 的 box 列表，而不是渲染 triangle、opaque 标记或单个包围盒；保留多个 box 的并集空隙。栅栏可高于一个 cell，shape 可有 cell 外坐标，**不得强制 clamp 到 [0,1]**。选择 float32 编码前核对与源 double 的误差；超出已协商精度或 extent 限制就拒绝该 snapshot，不扩大成完整方块或静默截断。

粉雪/脚手架、与鞋/下落/行走上下文有关的 shape、实体推动的活塞或 moving-block collision、modded 无限/超预算 shape，初版应明确 unsupported。液体和纯装饰不自动变成 solid；MC 流体、危害、原地形保护继续属于各自已有机制。后续 actor-context profile 需要单独版本/能力及原生 actor 对应关系，不能用一次 `CollisionContext.empty()` 假称对所有原生角色精确。

### 会话、坐标和序列 / Context and ordering

sidecar host context 使用 seqlock 发布 `hostPid + mcPid + worldId + hostEpoch + spaceRevision + hostSession`，以及经验证的 identity XYZ、`units_per_block` 和 tile XYZ。`hostSession` 是 host 生成、跨 Reset/reopen/重连不可复用的非零 64-bit token；实现时必须定义生成与持久边界，不能只用可能重用的 PID、epoch=1、teleportSeq=1 或粗粒度秒时间。MC 回显 host token，并提供 `producerSession`，在 MC 进程/绑定 level、dimension 或保存世界改变时更新。两个 token 与 world/epoch/spaceRevision 必须同时匹配，才接受消息。native 场景身份只留在本地 owner 记录，不传指针。

双方各自现有的 native `bridge.status().collision_generation` 与 Java `SkyLink.generation()` 不是已共享的同一个整数，不能直接比较或写成彼此等价。sidecar 会话握手明确建立上述 token；host 原生场景、scale/tile/world-offset 或连接边界变化会撤销旧 token/ACK 并清理旧自有对象，重新同步。前文旧反射 Z 世界不能借同一个 world 名称混入。

`txSeq` 是同一 token 对内全局严格递增的 u64；`sectionRevision` 是该 section 在同一会话内递增的 u64。重发保留同一 seq/revision 与相同 payload；同一 seq 不同 payload 是协议错误。初版最多一个在途事务，降低有界重试/ACK 丢失处理复杂度；重启或即将 wrap 时新建 session。收到旧会话、过期 revision 或重复已完成事务不能再次创建 collider，重复可重发原结果。更新积压可合并为最新完整 desired snapshot，但不能让尚未完成的旧创建在较新的 removal 后复活。

### 候选字节格式 / Candidate wire format

以下为设计布局，**未分配当前协议 enum 或 offset**。所有多字节值 little-endian，显式序列化，不依赖 C++ ABI padding；packet 8-byte 对齐，固定字段和 length/count 做溢出检查。

| 草案字段 | 布局 / Meaning |
|---|---|
| Common header，64 bytes | `u16 formatVersion, u16 headerBytes, u32 kind, u32 payloadBytes, u32 flags`；`u64 hostSession, u64 producerSession, u64 txSeq`；`u32 worldId, u32 hostEpoch, u32 spaceRevision, u32 payloadCRC32C`；`u64 reserved=0` |
| `SectionReplace` payload header，32 bytes | `i32 sx, sy, sz; u32 cellCount; u64 sectionRevision; u32 boxCount, profile`；其后完整 `Cell[cellCount] + Box[boxCount]`。明确替换 section 的全部自有 shape，而不是 delta |
| `Cell`，16 bytes | `u16 cellIndex, u16 flags; u32 firstBox, u32 boxCount, u32 reserved=0`；cellIndex 仍为 `x + 16*z + 256*y`，唯一且排序，box range 有界不重叠 |
| `Box`，24 bytes | `f32 minX, minY, minZ, maxX, maxY, maxZ`，相对该 cell 原点，以 MC blocks 表示；finite、min<max、已协商 extent/精度，允许合法的 cell 外坐标 |
| section removal | `SectionReplace(cellCount=0, boxCount=0, revision更大)` 为明确 tombstone。没有收到 section、export 失败、shape unsupported 或 render 顶点为零都**不是** removal |
| `ClearSession` | 同一会话的显式清空事务，作用于该 token 对下所有自有 collider/nav 对象；不可触碰原地形或其他 session 的对象。新 session 握手同样要求旧 owner 清理确认 |
| `Ack` | 回显 context 与 txSeq，带 section key/revision 或 ClearSession scope、结果状态、错误码；应用阶段独立记录，不能只用一个 success bit |

完整快照暂不做 box 字典、跨 cell 合并或任意三角网格，避免错引用/索引和内部面规则扩大首轮范围。之后可在不改变 shape 语义的前提下增加经过验证的 dedup/合并；数据来源仍需追溯到 section revision。CRC32C 只用于损坏/重发内容核对，不是权限认证；本机 sidecar 不能因此接受陌生进程或旧会话。

握手需协商 `STATIC_AABB_UNION`、`EXPLICIT_REMOVAL`、应用 ACK 能力、最大 payload/cells/boxes、可缓存 section 数和 native 对象/每帧处理预算。可选离线初始上限为每 section 最多 4096 cells、16384 boxes、单 packet 不超过 1 MiB；这只是 serializer/IPC 夹具预算，**不是提高当前 native 对象限制的许可**。allocator 仍关闭，未来原型先一块石头。超限、未知 profile/flag、NaN、退化 box、重复 cell、错长度、错误 CRC、错 context 或整数溢出均拒绝整包，不能截断后 ACK 为完整。

### 消费不等于应用 / ACK stages and removal completion

建议最少区分以下语义，并按事务缓存终态用于幂等重发：

| ACK/状态 | 真正需要的证据 |
|---|---|
| `DECODED` | 整个 packet 已消费、context/length/CRC/boxes 全部验证并放入受限 desired-state 队列；只证明传输成功 |
| `PHYSICS_APPLIED` | 所有自有 shape 完成已认证初始化/注册，属于当前 scene/session，按相应方法读回；不能由 render ring tail、holder 非空、Void setter 或 renderer mesh revision 推导 |
| `PHYSICS_REMOVED` | 被 tombstone/ClearSession 覆盖的旧自有对象已完成合法撤销且不再参与新查询/角色接触；安全 worker/生命周期屏障完成，引用才可释放。身份射线无命中是验收之一，不独自证明线程已不持有引用 |
| `NAV_APPLIED` / `NAV_REMOVED` | 若明确协商导航能力，真实导航障碍/路径请求更新完成并经过其认证生命周期；物理应用不会自动设置此状态 |
| `FAILED` / `PENDING_UNSUPPORTED` | 具体 context、seq、revision、阶段与有界错误码；不会推进相关 applied/removed revision。已部分创建须进入经认证 cleanup，不得把部分成功算完整 |

若协商导航，事务最终 complete 要求物理与导航都达到同一 desired revision；若只协商物理，nav 显式 `NOT_REQUESTED`，不得把它显示为 passed。placing、update 与 removal 分别保留 desired/decoded/applied revision，支持日志核对。native 并非已证明有原子批量物理提交；只能在真实安全引擎阶段以认证路线应用，ACK 在全部完成后发，pending/部分失败期间不能宣称已有完整障碍。

ring head/tail 只证明 bytes 发布/读取，本 fork 已有 terrain `collision_consumed_seq` 是 **host→MC 地形流** 的 Java 消费确认，方向相反；它不能用于 MC→native 方块注册 ACK。sidecar 使用独立双向 SPSC ring、release/acquire 和有界 staged 队列；ACK ring 满时保留终态待重发，不能丢掉拆除结果。超时或重发上限触发新增碰撞功能 unavailable 和明确诊断；**不擅自 free 正被原生 worker 使用的对象**，不自动重开旧 allocator。未有安全 cleanup/barrier 时停止扩容，记录待清理 owner，遵循已验证的场景卸载机制。

MC 放置/拆除仍先在 MC server 执行；renderer 可先显示变化，native ACK 不能回滚或重放 MC 物品/方块动作。正式精细碰撞功能未通过前，界面/文档只称 MC 建造；未来若需“拆除后原生角色立即能通过”的强保证，应定义等待应用提示与输入/碰撞 feature gate，不能静默保留无形墙。game/MC 崩溃时 ACK 不会到达，恢复必须以新的 session 和全量 desired snapshot 对账，而不是重放旧成功状态。

### 与渲染研究的交界 / Renderer boundary and offline acceptance

[渲染研究](ONIMUSHA-RENDER-RESEARCH.md) 中 mesh/MDF 注册、真实 depth/HDR、灯光和 shape 注册是独立流程。形状与 mesh 可携带对应的 block/section revision 供诊断，但形状 ACK 不证明网格已在 RE world renderer 中注册；render ACK 也不证明 collider/nav 生效。AABB union 不能当成真实主相机 depth：无碰撞装饰不会出现，半透明视觉/动态 actor 不在此形状流中。若 native chunk 渲染与物理以后共用自有 GO owner，仍要分别保存资源 holder、注册状态与安全移除屏障。不要为 transport 设计预先制造一方块一个 GO 的无界增长。

以下先在纯 Java/C++ 数字夹具和隔离 mapping 测试，**不调用任何 RE allocator**：

- little-endian/长度/CRC roundtrip；full cube、bottom/top slab、四向 stairs 的 AABB union；门打开/关闭和跨 section 邻居变化；fence 高度 1.5 不被裁剪。验证源 shape union 与解码结果的空间占用，不只检查 serializer 自我相等。
- 完整替换、空 section tombstone、ClearSession、重复包幂等、同 seq 内容不同、乱序/旧 revision；placement 后立即 removal，ACK 丢失/重发、ring 满/断连。确认 removal 不会被旧 placement 复活。
- 相同 PID 下 Lua Reset、两个不同 PID 重用 epoch/seq=1、MC 重连/换 level、非零 tile/scale 与坐标 revision 变化；旧 token 数据/ACK 必须拒绝。没有 fresh full snapshot 不能继承“已应用”。
- 整包超限/截断/未知 profile/context-sensitive shape/NaN/退化与越界 box 全拒绝；没有伪造完整 section、没有应用 ACK 自动成功。物理 decoder 模拟成功不等于 native 注册。
- 一个 mock consumer 分别延迟/失败 decoded、physics 和 nav 阶段，验证状态不会由 tail 或 mesh 成功跳级；removal pending 不释放被 mock worker 引用的资源。实际 RE worker barrier 仍需 P0/P1 证据，数字夹具不能替代。

**English:** Keep protocol v12 unchanged and propose an optional, negotiated Shapes v1 sidecar. Export authoritative static AABB unions with explicit session/world/epoch/coordinate context, full section revisions and removal tombstones. Distinguish decode acknowledgement from actual physics and navigation application/removal; transport consumption is not engine registration. Preserve the disabled allocator until legal ownership, registration and cleanup are independently verified. This proposal implements no transport or native collision feature.

MOD制作：LCPD15/LCPD拉灯 / Based on chasmlol's SkyCraft (MIT).
