# 自动模型转换与原生光照候选 / Automatic native models candidate

2026-10-08，protocol 15。仅适用于本项目已记录的 OnimushaWotS 01.000.001 / TDB82 / REFramework
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他 RE 游戏必须独立验证资源格式、SDK 与参数。
基于 chasmlol/SkyCraft；MOD制作：LCPD15/LCPD拉灯。

## 安装状态

11:47 已安装整套 DLL、Fabric JAR、Lua 和转换器启动入口，78 项部署文件哈希一致。
游戏和 MC 均已正常退出，接管配置关闭。此版通过离线、隔离 MC 和 GPU 测试，**尚未完成鬼武者实景验收**。
具体安装回执：`G:/Onimusha_MC_mod/logs/automatic-models-20261008/install.json`。

## 自动转换怎样工作

MC 导出实际模型、贴图和朝向；DLL 按完整外观去重，后台常驻 Blender 将新外观写成鬼武者的
MESH/MDF/TEX。相同外观共用原生资源，新增同类方块只创建实例，不重新压缩贴图。
资源完整写入、原生 Mesh/Material 加载完成且会话回执吻合后，才隐藏对应的 MC 绘制。
等待期间保持原有 MC 画面，因此首次出现新外观时可能先以 MC 光照显示，再切换成原生绘制。

这已替代旧版 16 种名称白名单，支持实际采集到的不透明及镂空模型。不同朝向可产生不同缓存资源；
邻居的改变不会强迫同一完整外观重复转换。梯子和树叶的透明孔洞按贴图裁成真实几何，
不会生成挡住孔洞的整张实心面。自定义模型仍受顶点数量、atlas 大小和材质支持范围限制。

实测后台转换 4 种新外观分别为 0.312、0.195、0.238、0.184 秒；这是本机少量样本，
不包含队列等待和原生加载，不能当作所有模型的上限。大量首次出现的不同外观仍需排队。
方块最多 1280 个、半径 16 格；每帧最多附加 4 个显示实例、预加载 2 种资源。
完整方块复用现有碰撞对象，非完整方块使用独立显示对象，**没有用完整立方体替代其原生碰撞形状**。
非完整方块对鬼武者角色的精确碰撞尚未新增。

## 玩家、手持物、NPC

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
blocks, animated entity faces, and first-person held items switch ownership only after native readiness.
It also adds bounded native point lights, chat input, player/enemy contact handling and an experimental
near-camera fade override. The existing real Minecraft armor path has been verified with isolated damage tests.
Inventory supplies and legal maximum Unbreaking/Infinity enchantments have been applied to the backed-up save.

Installation and automated tests passed; in-game acceptance is still pending. Animated/translucent surfaces
remain Minecraft-rendered, partial-block native collision and native AI navigation are not added, and dense
builds/multiple NPCs still require performance testing. Previous navigation experiments remain disabled.
