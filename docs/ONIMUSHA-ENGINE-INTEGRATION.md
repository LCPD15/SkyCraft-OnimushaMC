# 鬼武者引擎接入边界 / Engine integration boundary

更新时间：2026-10-07。仅适用于当前本地 OnimushaWotS 01.000.001 / TDB82 / 固定REFramework SDK，不代表其他RE游戏接口。

当前不是两个完整游戏画面的截图叠加。MC导出三维网格、纹理、角色和HUD，由独立D3D11-on-12绘制层在鬼武者Present时绘制；玩家位置、相机和百分比血量通过共享内存交换。独立绘制仍不等于进入原引擎渲染与物理系统。

| 功能 | 原版SkyCraft（Skyrim AE路径） | 当前鬼武者版 |
|---|---|---|
| 绘制时机 | RenderWorld后、原后处理前，自定义D3D11 shader | Present时，最终backbuffer上的独立绘制 |
| 原场景深度 | 主depth及相关depth copies，兼容motion/normal targets | 私有D32，重画附近原生碰撞三角形；没有真实主depth |
| 光照 | 太阳/月亮、六向环境、点光、雾和阴影数据填入自有常量缓冲 | MC顶点block/sky light的固定亮度，没有RE灯光和阴影 |
| 原生NPC方块碰撞 | Havok约束、排斥/滑墙及寻路障碍三个独立路径 | solid bitset已接收，合法原生碰撞注册与生命周期未完成 |
| MC光源影响原世界 | 创建并注册真实NiPointLight | 灯光消息未创建RE灯光 |

源码依据：原版`skse/src/WorldRender.cpp`的`DrawInFrame`、`RenderWorldHook`、`EnsureDepthCopy`、`GatherLighting`；`DigPhysics.cpp`、`NpcBlocks.cpp`、`PathAvoid.cpp`、`BlockLights.cpp`。当前`onimusha/native/Renderer.cpp`的backbuffer包装、私有D32创建和collision depth pass；`RenderStore.cpp`的solid消息和未处理灯光。

碰撞几何不能代表头发、草、没有碰撞的装饰、动态NPC及查询范围外的物体。因此MC玩家能站上方块，不能证明NPC能被方块阻挡；合成GPU遮挡测试也不能证明原场景遮挡正确。最新用户确认后两项没有通过。

MC攻击目前先命中MC代理，再由EV1目标ID查找缓存原生HealthManager，调用setHealth/checkHealthZero。新实景trace中15次EV1均接收并写后回读成功；用户重新确认确实扣敌人血，之前误判来自F10后原生世界空间UI冻结。此路径没有调用原生受击、硬直或破甲流程；死亡/破甲尚不能视作通过。Java命中日志在无条件pushEvent之后输出，不能单独当作入队或原生HP下降的证明。代理名称仅创建时设置导致Reset后名称残留，也正在单独修正，名称错误本身不能证明位置或命中ID错误。

用户新增UI问题：任务指引、头顶血条等在转向时固定，移动时仍能更新。adapter没有跳过整PlayerUpdate/GUIUpdate，控制SKIP仅匹配玩家root motion；相机直接写入位于LateUpdateBehavior回调末。只读Lua 8A108…的实景记录确认：实际TARGET_0对应的CameraComponent就是primary camera，写入后两者view完全一致；CameraManager activeView仍不变，virtual eye与渲染eye相差1.56单位，活动参数FOV仍为41而MC目标为70。frame7770/7800的primary view变化1.068943、active view变化0，符合用户所述移动/转向差异。

证据保存在`logs/live-human-handoff-20261006/status-ui-active-camera-difference.json`。这证明活动相机没有随渲染相机同步，尚不等于已追踪到全部UI调用者。修正候选仅在实际target和对象身份一致时同步活动虚拟相机及当前参数，逐项记录原值并恢复；矩阵缓存读数只作时序观察，不因同帧缓存未刷新反复退出接管。须以真实任务图标/头顶血条转向与F10恢复验收，不能隐藏原UI冒充修复。

Lua 9164…的六项同步版已通过91组实际生产helper/回调回归与Lua54编译，由root重跑；已安装并Reset，用户确认场景正常。真实记录验证了controller/virtual、operator/currentParam身份链，六项readback及恢复pending0。用户复测：血条恢复显示，移动时图标/血条跟随，转向时仍固定。`status-camera-sync-9164-active-turn-ui-still-fixed.json`表明afterTick及下一preUpdate的primary/active view差为0、eye差为0、FOV70；beforeTick却两者一起回到原生方向/FOV41。仅在LateUpdateBehavior末同步不够，后续以只读自然方法hook记录相机更新与投影调用的实际顺序，再选择同步位置；目前尚未证明具体UI调用点。此版本没有新增原生渲染资源、光照或方块碰撞接口。

只读B274版（103组回归）已实测定位：`app.CameraManager.lateUpdate`正常执行结束时把primary恢复为原生方向/FOV41，每帧一次。其前面update仍为MC70，内部preprocess后仍是MC70但CurrentParam已41。四个候选投影方法没有真实调用；reflectToComponent有调用，但参数身份不匹配认证owner，因此没有据此新增写入。下一候选只在已计数的outer lateUpdate post重放上轮认证MC相机，保留全部ready/watchdog/owner/epoch限制；是否修复可见UI仍须用户转向复测。

固定REFramework API只提供device、swapchain、command_queue、Present/reset及命名应用阶段回调，没有直接给出场景HDR/depth/DSV/当前command list或光照常量。真实深度接入需要先确认资源及descriptor、格式、sample count、动态分辨率、reverse-Z、投影/jitter、状态、队列顺序和生命周期。应用阶段回调存在不证明某个阶段可以安全插入GPU绘制。

本地TDB存在via.render.Mesh资源/材质接口，只证明资源方式的原生渲染是候选路线，不能推断动态网格上传和新对象world注册已可用。原生方块碰撞先独立验证合法创建、挂接、射线对象身份、移除和切场景，再验证敌人controller碰撞filter、身体接触与AI绕路。此前有加载崩溃的实验allocator不能直接开启。

MC透明/不透明pass可以先利用现有协议改进自身遮挡；此项不能替代真实RE深度。读取已验证的RE灯光填自定义shader是局部改善；原HDR/材质阶段的接入才可能进一步获得原后处理、阴影和反射。

MOD制作：LCPD15/LCPD拉灯
