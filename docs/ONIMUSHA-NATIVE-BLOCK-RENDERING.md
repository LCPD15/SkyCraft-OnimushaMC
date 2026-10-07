# 原生方块绘制候选 / Native block rendering candidate

2026-10-08。仅适用于 OnimushaWotS 01.000.001 / TDB82，REFramework
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。不能直接套用到别的 RE 游戏。

## 当前实现

**安装的是预制资源实例方案，protocol14；用户已确认铁块、圆石、TNT原生绘制正常。**
日志为8/8可见实例、3种资源全部就绪且无错误。南瓜、梯子未接入，仍为MC绘制；
目前16种白名单不能宣称是通用方块支持。
原生合并五方块的显示/光照/遮挡此前已通过用户实测，但不能视为此实例方案已通过。

MC 给受支持的方块三角面标记资源种类，DLL 校验面属于精确单位格，恢复方块坐标。
Lua 从已经验证的原生碰撞管理器取得该格的 GameObject，在原对象上附加一个 Mesh 组件，
复用提前生成的模型/材质/贴图。**不再为每次放置调用 Blender、压缩纹理或导出区块文件，
也不按每个方块额外创建第二套 GameObject。** 同类方块共用资源 holder；同一格变种类时复用 Mesh 组件。
首次使用某种类时，经一个隐藏的临时GameObject预加载资源；Mesh/Material就绪后销毁该临时对象，
再用于碰撞对象上的显示组件。每帧最多2个预加载器，总种类16，资源在本脚本生命周期内复用。
某个种类加载失败保留该种类overlay，其他已就绪种类继续原生绘制。

MeshReady、MaterialReady 和材质数量验证通过后，DLL 才停画这个原生实例对应的 MC 三角面。
原生模型接入 RE 场景光照、深度和投影阴影。DLL 同时保留这些三角面的深度绘制，
防止仍使用 overlay 的 MC 角色、物品和透明面穿画到方块前面。这个遮挡分支已用真实 WARP GPU
像素回读测试；不等于所有 MC 内容已经获得 RE 光照。

放置、替换、拆除、TNT、换场景、F10 关闭和脚本重载都校验当前会话并更新可见集合。
关闭绘制只禁用借用的 Mesh，GameObject 的销毁仍归碰撞管理器负责，避免重复 destroy。
资源未就绪或不支持时保留原 overlay。

## 支持范围与开销

- 当前资源库16种默认方块：石头、圆石、铁块、TNT、泥土、橡木木板、黑曜石、金块、
  钻石块、石砖、红砖、下界合金块、绿宝石块、铜块、石英块、基岩。
- Java 检查实际方块贴图、模型、blockstates及atlas的资源来源；全部vanilla才启用标记。
  Fabric自带模块的资源包名称不会造成误判，实际自定义方块资源仍保留MC绘制。
- 半径16格、最多1280，与碰撞对象范围一致。碰撞仍每帧至多创建2个对象，
  绘制至多附加4个新 Mesh 组件；大批量首次出现会分批就绪，不能保证1280个同帧全载入。
- 1280个实例上限与资源复用经过离线生命周期测试，**没有做游戏内1280密集实例帧率测试**。
- 动态实体、玻璃、水、动画贴图、其他方块仍为 overlay；无动态原生发光/点光源接入。
- 材质使用已验证的中性环境材质，普通金属贴图还未专门调整金属度；像素图采用整数放大、
  带边缘填充的atlas，当前无mip链。MC AO顶点颜色不会再次烘到原生模型上。
- 不包含原生AI导航；此前导航崩溃路径仍隔离。用户暂缓的偶发跨区域闪断也未重新修改。

## 合并方案保留为实验

曾实现 REN_SECTION/ATLAS → 异步快照 → 常驻 Blender 转换 → 原生显示回执的候选，
并离线验证五方块转换约0.45秒。这包含贴图压缩、写盘和回读，不能按“每五块固定0.45秒”外推。
用户指出交互延迟后，默认改用上述预制实例。合并模块 `onimusha_native_sections.lua`、
后台转换器和辅助API保留供后续静止建筑优化，**loader不会载入它，启动器也不会启动转换器**。
当前唯一loader的第六个payload是 `onimusha_native_instances.lua`。

## 验证与部署

- 67项 Java/JUnit测试通过（含资源来源判断4项）；27个Lua回归脚本全部通过，含新实例模块1280数量、共享资源、
  修改材质等待就绪、拆除不重复销毁、接管关闭、拒绝回执和会话恢复。
- 3/3原生CTest通过：真实Windows映射/Lua DLL接口、源三角面身份与版本回执、真实D3D12/WARP像素回读。
- 10项区块输入/分区测试通过；16种预制资源的MESH/MDF/TEX逐项写入回读校验通过。
- 生成资源 `G:/Onimusha_MC_mod/assets/native-block-library/`。
- 安装时间01:43，77项manifest哈希核对；DLL
  `69BEDC16B9C5E32B3DF7BDDE9E32943619596040929538D2B1321A351D5ADF67`，JAR
  02:05修正资源包误判后的JAR为 `E3466C4EA12B78ED54486AB8147C8CE05BEFD57142560EE79B572A44626DB571`。
- 65个存档文件未修改，完整备份在
  `runtime/test-backups/before-native-sections-20261008-014343`。
- 02:04维护工具让MC正常保存退出后又备份65文件到 `runtime/test-backups/before-pack-source-fix-20261008-0204`；
  鬼武者保持运行，MC重启连接后日志确认默认资源识别通过，相机/地形同步就绪。
- 第一轮用户实测仍是overlay；日志定位到Lua浮点编号 `2.0` 与JSON键 `"2"` 的差异。
  已用math.tointeger规范化资源编号并加入混合数字类型回归。
- 后续确认圆石资源独立加载正常；用户确认圆石已接原生光照，其他种类仍没有。
  已加入每种类隐藏预加载步骤及超时隔离，用户随后确认铁块/圆石/TNT正常。不能声称16种全部通过。
- 安装/测试证据 `logs/live-native-sections-20261008/`。

仍待系统实测：首次种类加载响应、阴影细节、显示拆除/TNT清理、F10关闭恢复、密集实例性能。
下一架构应使用MC真实烘焙模型/UV/贴图，自动生成按状态与材质身份缓存的RE资源；
同外观首次处理后复用。南瓜方向、梯子薄片/cutout等应由模型数据驱动，避免继续手工扩大白名单。
这个通用缓存尚未实现，首次新模型转换仍有开销，非完整方块碰撞也不能直接套单位盒。

English: The installed candidate reuses prebuilt vanilla cube assets on the existing native
collider objects. Placing supported blocks requires no live Blender conversion or texture
compression. Native readiness gates overlay suppression; a depth-only copy still occludes MC
overlay entities. Lighting, occlusion, edit cleanup and dense performance need in-game acceptance.

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯
