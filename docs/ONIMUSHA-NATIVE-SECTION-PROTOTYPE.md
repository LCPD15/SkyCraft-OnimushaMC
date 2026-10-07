# 原生区块合并模型原型 / Native section asset prototype

2026-10-08。仅适用于 OnimushaWotS 01.000.001 / TDB82，当前 REFramework
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他游戏需要独立验证格式、材质与生命周期。

**实景通过：由 REN_SECTION / REN_ATLAS 格式的测试数据生成一个合并原生模型，
包含五个石头/铁块，用户确认显示、光照和遮挡均正常。** 几何是人工构造的测试数据，
贴图来自本地 MC 26.3 客户端。没有读取或修改当前存档，尚未把实时变化的 MC 区块接入原生绘制。

English: One merged native mesh made from synthetic protocol-format geometry and genuine
Minecraft stone/iron textures passed the user's in-game appearance, lighting and occlusion
check. This validates the asset/registration route, not real-time world rendering or arbitrary
Minecraft materials. Existing world rendering remains the overlay.

## 实现

- `onimusha/tools/native_section_input.py`：校验 protocol13 的 section 和 atlas 载荷，
  限制坐标、尺寸、顶点数量、浮点值、UV与标记。此阶段拒绝染色/AO、顶点透明、透明混合及透明贴图足迹。
- `onimusha/tools/Build-Native-Section.py`：在独立 Blender 后台进程中调用已安装插件的
  MESH/MDF 编解码器；不修改全局插件、原游戏素材或运行中的世界。
- 保持 MC/RE 的 XYZ 同向、Y向上，顶点留在区块局部坐标；单独记录 section origin，
  不把数万格的世界平移写进单精度模型顶点。按三角面计算法线、切线。
- 输出 MESH260209350 / MDF51 / TEX251111100；中性受光环境材质与此前石头方块一致。
  纹理采用 BC7 sRGB、原始BC块、256字节行对齐。当前只有一层 mip，尚无 atlas mip 边界处理。
- 对照原协议检查每个位置、三角索引、UV和法线。额外检查原始MESH中的UV，确认没有重复翻转V。
  超过65535顶点时拆成多个子网格，仍为一个模型、一种材质和一个场景对象。
- 路径包含输入和转换器内容的哈希；同名输出目录已存在时拒绝覆盖，避免改写仍可能被引擎缓存的资源。
- `render_section` 探针只允许私有 `section_<20 hex>` 路径；只创建一个显示对象，
  不创建碰撞或导航对象。接管开启、换场景、移除或重载时撤掉自有对象。

## 验证与真实游戏结果

1. 五个 Python 校验测试通过：坐标与UV、镜像切线、错误长度/数值/标记、透明足迹、退化面。
2. 小型合并模型：5方块，120顶点、40三角面、1子网格，内部相邻面剔除，离线回读通过。
3. 大型合成夹具：2048个交错方块，73728顶点、24576三角面、2子网格，离线回读通过。
   **该夹具没有在游戏中创建，不是1280碰撞对象的性能测试。**
4. 五方块实景资源为 `section_ea77b84c15f9e3c6a178`。`merged-mc-section-20261008-b`
   已回报 MeshReady、MaterialReady、Draw、Update 为true，材质数量1，世界AABB为2×2×2。
   用户回复“显示、光照和遮挡均正常”。
5. 随后 `remove-merged-mc-section-20261008-a` 回报 removed、destroyed=true；探针控制再次关闭。
   原接管与1280完整方块碰撞配置保留，导航继续隔离。

日志与备份：`G:/Onimusha_MC_mod/logs/native-section-20261008/`。
生成物：`G:/Onimusha_MC_mod/assets/native-sections/generated/`。
三份 fixture 均在 `assets/native-sections/`，明确标注 synthetic-fixture，不能伪称真实世界捕获。
Lua回归通过，包含模型/材质异步等待、资源路径限制、暂停等待、撤除和既有碰撞实验生命周期。

## 此轮定位的问题

第一次请求 `merged-mc-section-20261008-a` 在游戏暂停时创建。模型包围盒已出现，
但对象Update=false、模型和材质未就绪，600帧后自动撤除。原游戏没有崩溃。
主适配器同时记录 menu_pause=true、player_pause=true。

用户返回场景后，**同一套文件、同一加载路径**的第二次请求立即就绪并通过视觉检查。
因此不能把第一次超时直接归因为文件格式错误。
探针现已在暂停时等待、不分配对象也不消耗请求；载入中再次暂停时，不累计资源加载超时。
清理后同时把 ready 置false，避免“removed但ready=true”的误导状态。

## 接入实时世界前仍需实现

- 从运行中的生产者获取同一会话、同一版本的区块网格与atlas快照；带 world/epoch/进程/区块版本身份，
  不能把磁盘旧存档或合成夹具当成实时画面。
- 有界后台转换队列与资源缓存。转换不能阻塞游戏帧；本工具是离线原型，不能每帧启动Blender。
- 新原生模型与材质就绪后，向DLL回执其精确版本，才停画对应overlay区块。
  区块变化、拆除/爆炸、会话变化和F10关闭须撤销回执并及时撤除旧显示对象，避免双重绘制或残影。
- 旧holder、场景对象与引擎资源缓存的释放/复用上限需要实测；不能不断生成新路径造成无界内存增长。
- 原生shader的顶点色、cutout、玻璃/水、动画贴图、自发光、atlas mip边界和阴影分别验证。
  MC角色、动态实体、物品与粒子尚未接入此路径。

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯
