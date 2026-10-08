# 自动模型转换与原生光照候选 / Automatic native models candidate

2026-10-08，protocol 15。仅适用于本项目已记录的 OnimushaWotS 01.000.001 / TDB82 / REFramework
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他 RE 游戏必须独立验证资源格式、SDK 与参数。
基于 chasmlol/SkyCraft；MOD制作：LCPD15/LCPD拉灯。

## 安装状态

2026-10-09 00:00 已安装稳定部件编号和实例颜色候选，等待启动及复测。
用户已确认第三人称角色/装备、第一人称手持物和铁傀儡原生光照正确，部件缓存避免道具切换
逐个恢复；仍有瞬间身体回退、受击后重建和活动TNT缩放异常。当前候选不能提前标记通过。

DLL动态面编号现在独立于顶点偏移，换序与旧道具消失不会使整个人物的回执失效；
受击颜色改为Mesh实例BaseColor，保留红闪且不重新转换贴图。动态结果读取每3帧检查，
最多8个结果/帧、2个新对象/帧。全新外观仍有转换/加载成本，不能承诺零延迟。

方块光照、放拆连续、约30米显示和F10恢复已通过，候选保留该路径。
动态控制hands/avatar/scene启用、768实例上限；没有控制文件时默认关闭。
79项部署哈希一致，原世界65文件已备份，JAR及协议15不变。

The user has verified native lighting on the avatar, held items and iron golems. Stable face IDs
and per-instance hurt tint are installed but await live regression testing. TNT source capture
shows growth from 1.0 to 1.17345 before detonation; the reported native scale freeze remains
under investigation, with bounded engine-scale readback added for the next live test.

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

运行开关位于 `onimusha_native_dynamic_control.json`，可分别启用玩家、手持物和场景实体，
也可设为仅预加载。引擎生成的Mesh/MDF holder持续保留到对象销毁，每组件仅绑定一次。
单外观加载/绑定错误不撤回已经成功的方块与其他动态流。

实际 MC 玩家、装备和铁傀儡等实体的可支持矩形面转换为共享资源，动画仅更新原生实例变换。
同一面移动时不重复导出文件。玩家、场景实体、第一人称手持物各最多 512 面。
均匀受击颜色直接写入当前原生实例；换装备产生的新外观尚未就绪时，该部分保留 MC 绘制。
切换道具改变顶点偏移时，按流和外观复用已有对象，避免将身体一起销毁重建。

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
# 2026-10-09 持久缓存与像素采样修正版

本节修改已安装但尚未完成鬼武者游戏画面验收，仅适用于本项目的鬼武者版本。

转换资源保存在 `G:/Onimusha_MC_mod/assets/native-models/live/section_*`；
`cache-v2/*.json` 记录输入内容及转换规则对应的资源与 SHA256。换世界、重启游戏或模型编号变化
不会单独触发重做。模型、资源包贴图、动画元数据、白闪外观或转换代码/格式模板变化时才重新转换。
命中缓存仍需引擎加载资源，不能承诺零延迟。worker.json 提供 cache_hits/cache_misses。
原生文件缺失/损坏不会直接确认就绪；旧运行会话的结果 ID 不复用。
已用实际Blender worker跨进程验证：首次转换0.553秒，重启后内容缓存命中0.114秒（不含引擎加载）。
30组已通过资源回读的方块/动态面用例合并为29个缓存条目，待游戏启动直接按内容匹配。

像素边界改用同色区域的三角形分区和内部 UV，减少线性采样混入相邻颜色；
切换为鬼武者绘制后保留像素边界，同时仍由鬼武者计算光照、遮挡及阴影。
几何数量增加且保留预算，原版动画贴图/混合透明的既有回退范围未扩大。
此修正会使旧过滤资源失效一次；新版转换后可跨启动直接使用持久缓存。
