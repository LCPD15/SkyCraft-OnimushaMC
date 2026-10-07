# 原生物体实验 / Native object probe

仅适用 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
2026-10-07。MOD制作：LCPD15/LCPD拉灯。SkyCraft 原作 chasmlol，保留其 MIT 许可。
其他 RE 游戏必须重新核对格式、反射签名、过滤层和创建时序。

## 当前证据与边界

- 用户已确认原生木纹测试立方体可以看到，明暗与遮挡正确。它使用鬼武者材质，目的只是验证原生绘制入口。
- 第二版改用本机 MC 26.3 JAR 的 `assets/minecraft/textures/block/stone.png`。
  六面分别覆盖完整 UV，16×16 原图按最近邻放大至 256×256，再生成 BC7 sRGB 与完整 mip 链。
  原生 MESH 24 顶点、12 三角形，尺寸 1×1×1；TEX 每层压缩数据回读一致。
- `physics-cube-20261007-e` 已获得原生射线的精确身份命中：命中 collider 地址
  `164997082944`，所属对象地址 `164997072256` 与新建方块一致；1 个接触点。
  射线起点 `(-20.86049, 0.668816, 113.45491)`、方向 `(1,0,0)`、长度 4。
  Mesh、材质与碰撞均 ready，包围盒一致，Collider Layer=1。
- **用户确认 MC 石头贴图、光照和遮挡正确，能阻挡原角色；删除后碰撞也已清除。**
  重启后另一次 `physics-enemy-collision-20261007-a` 测试，用户确认普通敌人被方块挡住。
  已撤除，状态 removed/destroyed=true；主动绕路没有验证通过。
- 导航扩展实验随后触发游戏闪退，已隔离并从运行脚本、安装目录撤下。敌人寻路未通过。
- 这只是一个隔离方块。生产 MC 世界仍主要使用叠加绘制；尚未把玩家放置的全部方块接入原生渲染、碰撞和导航。

测试证据保存在 `G:/Onimusha_MC_mod/logs/remaining-engine-work-20261007/`：
`render-cube-e-user-pass.json`、`render-cube-e-user-feedback.txt`、
`physics-cube-e-identity-ray-pass.json`、`physics-cube-e-user-pass.json`、
`physics-cube-e-user-feedback.txt`、`physics-cube-e-removed-user-pass.json`、
`physics-cube-e-removal-user-feedback.txt`、`adapter-regression-results.json`，以及
`physics-enemy-collision-a-ready.json`、`physics-enemy-collision-a-user-pass.json`、
`physics-enemy-collision-a-user-feedback.txt`、`physics-enemy-collision-a-removed.json`。

## 创建路径与踩坑

使用唯一项目 loader 的 combat_inventory payload，不增加 autorun。
控制文件 `reframework/data/onimusha_native_object_probe_control.json`，显式新 id 才创建对象。
动作 `render_cube`、`physics_cube`、`inspect_ground`、`remove`。
仅 F10 关闭、玩家就绪、TDB82、上一对象已销毁时允许创建。
切换场景、开启接管、超时或脚本重载时禁用碰撞并销毁自有对象，保留资源引用到延迟销毁结束。

1. `GameObject.create(String, Folder)` 加 `via.render.Mesh` 已通过游戏内显示测试。
   MeshResource / MeshMaterialResource 必须使用对应 holder，等待 MeshReady 和 MaterialReady。
   显式资源引用交给 holder 后释放，holder 与对象保留引用，遵循
   [REFramework 资源 API](https://cursey.github.io/reframework-book/api/types/REResource.html)。
2. 鬼武者 TDB82 的 `via.Prefab` 没有 `set_Path`，不可照搬其他游戏脚本。
   `sdk.deserialize` 虽有公开 API，但当前框架日志 `Failed to find first step`，调用抛出异常。
   **禁止在本版本重试该入口或把异常误认成 PFB 内容验证通过。**
3. 改为独立 USER3 资源，类型 `app.user_data.AmuletPrefabHolder`，仅保存自己的 `_BeadsPrefab`。
   不替换游戏护符，不挂到原角色，不执行护符逻辑。
   用 [sdk.create_userdata](https://cursey.github.io/reframework-book/api/sdk.html) 加载后，
   **字段可能暂为 nil，必须跨帧等待**；然后 prefab Standby=true，等待 Ready，再 instantiate。
4. PFB18 中只有一个 GO、Transform、Colliders；Colliders 内一个 BoxShape，半边长 0.5。
   原生预制体负责注册物理组件，避免分配裸 Collider 后误以为已加入物理世界。
   碰撞过滤资源来自当前地面 `Terrain_Default.cfil`（Layer1）；Group 由引擎分配，不能固定复制 134。
5. 最初射线把三参数 `setRay` 当成“起点、方向、长度”，无命中。
   改用 `setRay(via.vec3, via.vec3)` 的起点与终点后成功，且回读 Ray/Distance 确认正确。
   **不要将先前无命中直接归因于 Collider 注册失败；也不要沿用未核实的重载语义。**
6. 检查必须比较命中 collider 与自有 collider 的地址，同时确认 GO 归属。
   不能把命中地面或另一个场景物体算成成功。

## 原生资源格式

MESH260209350：进程内映射 new135 / internal250203152；不修改用户全局 Blender 插件。
MDF51：材质头 104 字节，独立 scalar value count，无 ver51UnknOffset。
TEX251111100：40 字节头、每 mip 16 字节条目、256 字节行对齐的原始 BC 数据，不能使用 gdeflate 包装。

参考环境材质 `V_Env_Base_ALP.mmtr`。MC 版替换 `BaseDielectricMap`，MetalScale=0，
NormalRoughnessMap 使用环境材质族已有的 NullNormalRoughnessOcclusion，去除参考木纹凹凸。
该独立石头方块的外观已由用户验证；不能推广为所有 MC 方块、实体均已原生绘制。

生成脚本：`onimusha/tools/Build-Native-Probe.py`（Blender 后台），
`onimusha/tools/NativeProbeAsset`（.NET10，依赖本地 REE-Lib 与鬼武者 RSZ schema）。
原版参考文件只读；生成文件在 `G:/Onimusha_MC_mod/assets/native-probe/generated/`。
本次没有更换 DLL 或 Fabric JAR，没有改 MC 存档。

## 导航实验事故与恢复

新增独立 PFB：Transform、Colliders、AIMapEffector（Disable=1、OBB=2、Fixed=false），
导航 OBB 半边长 (0.5,1.5,0.5)，覆盖地面。组件一度报告 Affected=true，
Zako/MidBoss hasEffectNodes=true；Boss/Water=false，碰撞射线仍通过。
**这些状态不证明导航安全或有效。**

22:21:44 的日志先记录 `AIMapEffector.hasEffectNodes` 原生调用异常，随后访问违规。
第一次 RIP=OnimushaWotS.exe+0x870e941，后续 dump 阶段另有异常。
附近 TDB 函数符号不能当作精确故障函数。尚未区分方法调用、对象注册/清理或原生更新时序的问题。
不能用 Lua pcall 掩盖原生异常后继续创建此类物体。

保存 `navigation-crash-reframework.log`、`navigation-crash.dmp`、
`navigation-crash-probe-status.json`、`quarantined-navigation-probe.lua` 和生成资源。
运行脚本移除导航创建与 hasEffectNodes 调用，`navigation_cube` 动作直接拒绝。
导航 PFB/USER 和废弃 JSON loader 已从游戏目录移至日志隔离目录；生成器仅保留
`navigation-offline-only` 复现选项，不能部署。

当前两个探针控制文件 enabled=false，22个部署文件哈希一致。
MC 日志确认22:21:51检测到宿主退出后保存世界并退出。
完整64文件备份并核对：`runtime/test-backups/after-native-probe-20261007-222930`。
恢复收据 `safe-recovery-receipt.json`。用户已确认重启后基础场景正常（新游戏PID84716）。
原 MC 世界已恢复（PID85296，日志 `live-native-probe-recovery-20261007.stdout.log`），
用户确认接管后移动、视角、背包与关闭后恢复均正常。当前没有测试物体；导航继续隔离。

## 下一步验收

1. 关闭导航实验后的基础场景、原 MC 世界与接管恢复已验证。
2. 已验证的纯碰撞 PFB 已通过玩家与普通敌人阻挡；可继续接入同步，不能假设会绕路。
3. 导航保持隔离，先离线核对上述崩溃证据与接口；不得再自动加载当前导航 PFB。
4. 接入 MC 放置/拆除事件、区块生命周期与回执。当前 RENSOLIDS 只有占用位，无法准确表示楼梯、
   半砖、栅栏的形状；不可统一变成完整立方体碰撞。
5. 任意 MC 实体的原生材质/动画与处决处理仍是后续工作。

24 个 Lua 回归文件通过，新增测试覆盖资源未就绪、非自有命中、精确命中、清理、
加载中切接管与换场景、脚本重载清理、拒绝隔离的导航动作。模拟测试不代替实际游戏物理验收。
