# 自动模型转换与原生光照候选 / Automatic native models candidate

2026-10-08，protocol 15。仅适用于本项目已记录的 OnimushaWotS 01.000.001 / TDB82 / REFramework
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他 RE 游戏必须独立验证资源格式、SDK 与参数。
基于 chasmlol/SkyCraft；MOD制作：LCPD15/LCPD拉灯。

## 安装状态

22:39 已热更新引擎 USER3 依赖加载候选；**玩家、手持物、NPC、活动 TNT 的原生绘制仍关闭**。
21:16 组件重建版本崩溃；恢复旧的定时 holder 重绑后，21:40 仍在 `Mesh.setMesh` 出现异常，
导致新增方块让全部绘制回退。以上两条资源加载路径均已撤回，不能作为可靠回退版本。
新路径通过引擎反序列化 Mesh/MDF holder，4 个全新单方块资源首次加载及撤除成功。
每组件绑定一次；取消超时重绑/重建，单类型失败不会清除已成功方块的回执。
22:45 用户已确认接管时方块光照正常，新创建方块等待时间明显缩短；日志11/11方块就绪，
6种外观已加载，热更新后无新增绑定异常。22:49 用户进一步确认放拆不再全体闪回、
约30米仍有原生光照、F10恢复正常；日志显示229个显示对象全部撤除，碰撞亦无残留。
长期稳定性、更多外观与动态实体仍需单独验证。

The engine-owned USER3 dependency loader passed the user's block-lighting,
place/remove continuity, approximately 30 m visibility and F10 restoration tests.
All 229 display objects were retired and no collision objects remained after takeover stopped.
Native entity rendering remains disabled; this result does not validate that path.
78项部署哈希核对通过；本轮未修改存档。安装回执及旧文件：
`G:/Onimusha_MC_mod/runtime/test-backups/engine-resource-loader-20261008-223922/receipt.json`。
此前128米显示和放拆保留改动仍待实景验收，不能视为已全部通过。

## 自动转换怎样工作

MC 导出实际模型、贴图和朝向；DLL 按完整外观去重，后台常驻 Blender 将新外观写成鬼武者的
MESH/MDF/TEX 及 USER3 依赖文件。相同外观共用原生资源，新增同类方块只创建实例，不重新压缩贴图。
USER3 是私有 `app.montage.data.MontagePartsModelData` 数据容器，仅填写 Mesh/Material 路径，
不挂接玩家或执行换装。模板由 REE-Lib 生成并回读校验，worker 仅替换等长私有资源 ID。
回执要求 `loader_version=1`；旧转换结果由 worker 补依赖文件，无需重新导出贴图。
资源完整写入、原生 Mesh/Material 加载完成且会话回执吻合后，才隐藏对应的 MC 绘制。
等待期间保持原有 MC 画面，因此首次出现新外观时可能先以 MC 光照显示，再切换成原生绘制。
新方块优先于积压的实体面转换；结果写入遇Windows读锁重试、已完成任务重启复用，仍不能承诺新外观零延迟。

这已替代旧版 16 种名称白名单，支持实际采集到的不透明及镂空模型。不同朝向可产生不同缓存资源；
邻居的改变不会强迫同一完整外观重复转换。梯子和树叶的透明孔洞按贴图裁成真实几何，
不会生成挡住孔洞的整张实心面。自定义模型仍受顶点数量、atlas 大小和材质支持范围限制。

实测后台转换 4 种新外观分别为 0.312、0.195、0.238、0.184 秒；这是本机少量样本，
不包含队列等待和原生加载，不能当作所有模型的上限。大量首次出现的不同外观仍需排队。
原生显示取128米内最近1280个方块，碰撞仍为16米；每帧最多附加4个显示实例、启动2种预载，最多8种同时预载。
所有显示对象独立于近距离碰撞，离开碰撞范围不会撤掉显示。区域重建按未改变的位置+外观保留显示确认，原租期不延长。
**没有用完整立方体替代非完整方块的原生碰撞形状**。
非完整方块对鬼武者角色的精确碰撞尚未新增。

## 玩家、手持物、NPC

**当前生产版本隔离此功能（`DYNAMIC_NATIVE_ENABLED=false`）。以下描述仅是尚未稳定的实验实现。**
动态对象统一回退 MC 渲染，所以不会获得鬼武者光照/遮挡。战斗、实体寻路和爆炸伤害桥接仍保留。
逐面资源加载曾造成大量排队；重建加载组件的修补发生真实游戏崩溃。必须先解决资源生命周期和
批量绘制，再恢复此功能。离线 mock 通过不能证明原生引擎安全。

实际 MC 玩家、装备和铁傀儡等实体的可支持矩形面转换为共享资源，动画仅更新原生实例变换。
同一面移动时不重复导出文件。玩家、场景实体、第一人称手持物各最多 512 面。
伤害变色或换装备产生的新外观尚未就绪时恢复 MC 绘制。

第一人称手持物单独捕获原版姿态并校正 FOV；整组资源全部就绪才停止 MC 的手持物层绘制。
未就绪、回执失败或 F5 切换均撤回原生显示。第一人称道具不向场景投射巨大近镜头阴影。
Lua 管理的显示、预加载、动态面与光源总对象数限制为 2560；退休中的对象也计数。
目前按面生成对象，**仍需实景确认多 NPC 帧率与第一人称对齐**，不能宣称已完成批处理优化。

## 发光与支持边界

火、岩浆、火把等已有 MC 光源元数据同步为原生 PointLight，最多取附近 64 个，逐帧分批创建。
火焰和岩浆使用轻微强度变化。方块移除、爆炸、退出接管、换场景和脚本重载均清理光源。
光源暂不投射动态阴影，亮度和半径仍需实景调校。

**动画贴图、混合透明材质和不支持的顶点颜色模式继续使用 MC 绘制。** 火/岩浆的动画表面没有
全部转为原生自发光材质；本版先让其在鬼武者场景中产生照明，不能把这个结果说成动画表面的
全部光照、遮挡和材质已经完成。水、玻璃、粒子及其他回退内容也仍有原叠加绘制的限制。

## 其他同期改动

- T 或 / 打开真实 MC 聊天框，抑制对应按键残留字符。当前测试存档原本已允许命令，可输入
  `/gamemode creative` 或 `/gamemode survival`。
- 护甲使用实际 MC 伤害流程，而不是额外叠加一个简化公式。隔离 MC 中原始 10 点伤害：裸装扣 10，
  铁甲扣 6，钻石甲扣 3；分别只向原生端回写一次 50%、30%、15% 最大血量变化。
- MC 玩家与同会话敌人代理发生接触时阻挡/分离，敌人靠近可推开 MC 玩家；位移通过正常地形碰撞。
  隔离 MC 已通过向前阻挡和敌人主动靠近测试，实际敌人包围和地形边界仍需验收。
- 接管期间抑制 `app.mcCamSys_DitherDepth.isDitherEnableCamera` 的近镜头淡化返回值。
  已核对接口并完成语法检查，**实景半透明是否消失尚未验证**，不改死亡等其他淡出。
- 原存档背包 36 格按物品真实堆叠上限补满；4 组金苹果改为附魔金苹果，弓无限 I + 耐久 III，
  盾及支持耐久附魔的装备耐久 III。空格补入岩浆桶，没有覆盖原有其他物品。
  背包已实际写入存档，回执 `logs/inventory-upgrade-20261008.json`，不能重复执行写入工具。

## 本地验证记录

- Java 70 项测试无失败；原生 3/3 CTest（映射/解码、Lua DLL API、真实 D3D12/WARP 像素回读）通过。
- 29 个 Lua 回归脚本通过，另补测第一人称资源不完整、回执拒绝、全透明面、F5 和清理通过。
- 隔离 MC 实际捕获 10 种方块外观；第三人称玩家与装备 226 面、两只铁傀儡共 96 面；第一人称剑盾 94/94 面。
- 常驻后台转换器四请求从 mailbox 到实际原生文件写入和哈希回读通过；宿主结束后退出。
- 第一人称切换回执让 HUD 的手持物像素正确消失，其他 HUD 仍保留；原生深度镂空测试通过。
- 原用户世界没有用于这些自动场景；安装前再次备份并核对其 65 个文件，安装未改存档内容。

证据均在 `G:/Onimusha_MC_mod/logs/automatic-models-20261008/`。
上述测试不能代替原生游戏光照、遮挡、碰撞与性能验收。

## 启动、诊断、回退

先启动鬼武者并进入场景，F10 保持关闭。再运行项目启动器：

```powershell
& G:/Onimusha_MC_mod/tools/MC-launch-dev.ps1 -WorldName OnimushaMC-XYZ-v2 -LogPrefix live-automatic-models-20261008 -StartHidden -QuitWithHost -SwordBlocking
```

生产映射 `Local\OnimushaMC_v1` 会先启动隐藏的常驻 Blender 转换器；隔离测试映射不触发它。
唯一自动重载器第六 payload 为 `onimusha_native_models.lua`；旧 instances/sections 模块不同时加载。
检查 `native_sections.mode=automatic_models`、ready/desired、resource_errors、dynamic_error、
light_error，以及 `hooks.camera_dither` 的调用/抑制计数。资源缓存位于游戏的
`natives/stm/mod/onimusha_mc/sections/`，请求/回执在 `reframework/data/onimusha_mc/native_models/`。

完整安装备份：`runtime/test-backups/before-automatic-models-20261008-114743`。
如需退回 protocol 14，须停止游戏并让 MC 保存退出，配套恢复备份的 game 文件、
`deployment.before.json`、`MC-launch-dev.ps1` 和 **`minecraft.protocol14.jar`**。
`minecraft.before.jar` 是已经做过隔离测试的 protocol 15 JAR，不是旧版回退 JAR。
新增 models payload 退出旧 loader 后不会被载入；不可混用 protocol 14/15 DLL 与 JAR。
存档备份仅供恢复，不应因代码回退自动覆盖用户后续游玩进度。

## English release notes

This Onimusha-only protocol-15 candidate automatically captures actual Minecraft model appearances and
converts supported opaque/cutout geometry into cached native resources. Identical appearances reuse assets;
blocks switch ownership only after native readiness. Native entity and held-item rendering is currently
quarantined after a Mesh.setMesh access violation; these streams use Minecraft rendering until a safer
resource-lifetime and batching design is validated. Combat and explosion bridging remain enabled.
It also adds bounded native point lights, chat input, player/enemy contact handling and an experimental
near-camera fade override. The existing real Minecraft armor path has been verified with isolated damage tests.
Inventory supplies and legal maximum Unbreaking/Infinity enchantments have been applied to the backed-up save.

The component-recreation experiment crashed in game and has been withdrawn. The block-only recovery
candidate is installed and its deployment hashes and offline isolation checks passed; a new in-game
startup/acceptance check is still pending. Animated/translucent surfaces
remain Minecraft-rendered, partial-block native collision and native AI navigation are not added, and dense
builds/multiple NPCs still require performance testing. Previous navigation experiments remain disabled.
