# 鬼武者光照与遮挡接入研究 / Onimusha lighting and occlusion research

2026-10-07。只适用于本地 **OnimushaWotS 01.000.001 / TDB82 / D3D12**。固定 REFramework SDK 提交：`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。调查开始时以 SkyCraft 提交 `3d21e87d52a3eb8c7580e485ba6c455d29379b40` 加当时工作树候选为输入；以下按具体文件 hash 记录渲染身份，不能用提交 HEAD 代替已安装文件身份。其他 RE 游戏、更新后的鬼武者或 SDK 必须重新验证。

用户要求是 MC 方块、角色及物品正确受到鬼武者场景的遮挡与光照。本调查只读本地源码、SDK、TDB 缓存、schema 和已有测试日志；没有启动游戏、操作 UI、新增 GPU hook、调用游戏接口、创建原生对象或部署 DLL。

**English conclusion:** Upstream SkyCraft uses custom shaders, but integrates them with Skyrim's real scene depth, HDR targets, lighting and shadow data before post-processing. The Onimusha port currently draws at Present using a private depth buffer and collision geometry. That is not native scene-depth or lighting integration. The pinned REFramework API exposes the device, swapchain and command queue, but no certified scene depth/HDR resource or current command list. Native mesh/material registration and verified resource capture are separate research paths; neither is implemented by this document.

## 固定源码与现状证据

| 文件／版本 | 本次身份或位置 | 能证明什么 |
|---|---|---|
| `skse/src/WorldRender.cpp` | SHA256 `5D140792572C69B71D6D04E5180723C0852C201B729EAFE42E7134947C3B4D8A` | 上游 Skyrim AE 渲染实现，不是鬼武者 ABI |
| `skse/src/BlockLights.cpp` | SHA256 `F705BC3E914DBE22F40BDCCEFCB1D96BCB626C1AD59F0DB99C421D1FB9565327` | 上游原生光源创建／注册实现 |
| 当前 `onimusha/native/Renderer.cpp` 工作树 | SHA256 `AAFBE43CD184312647F86AFB091E2610FAEA3AE2CB31A0A2194ACFFA684BF112` | 含透明 pass 候选；不能当成当前已安装 DLL 的行为 |
| 独立透明候选 | `build/native-transparency/Release/OnimushaMC.dll` SHA256 `FC445437F870A5D09952A8F7935DFD7F9BC502336FF83F500661618DCB23ACA5` | 保留候选，没有部署；已有 WARP GPU 测试，不证明 RE 场景融合 |
| 独立验证日志 | `logs/native-transparency-all-tests-root-20261007.log` | root补编译API/mapping测试目标后完整CTest 3/3通过、无跳过，FC445 hash保持一致；包含玻璃／cutout／排序及 reset/resize 像素检查，仍不证明 RE 场景融合 |
| 固定 SDK | [API.h:75](../onimusha/native/vendor/reframework/API.h#L75)、[API.h:96](../onimusha/native/vendor/reframework/API.h#L96) | 回调和设备数据边界 |

源码行号按以上快照记录，文件后续变化时按函数和 hash 重新定位。原始游戏资源、schema 和 TDB dump 只作为本地研究输入，不复制进可公开源码包。

当前 [Renderer.cpp:113](../onimusha/native/Renderer.cpp#L113) 在实际 D3D12 device/queue 上创建私有 D3D11-on-12 context；[Renderer.cpp:132](../onimusha/native/Renderer.cpp#L132) 只包装 swapchain backbuffer，约定进入／退出为 PRESENT。[Renderer.cpp:169](../onimusha/native/Renderer.cpp#L169) 创建自己的单采样 `D32_FLOAT`。`render` 每帧选 `GetCurrentBackBufferIndex`、Acquire、清私有 depth、绘制，再 Release/Flush，见 [Renderer.cpp:321](../onimusha/native/Renderer.cpp#L321)。

其遮挡 prepass 来自 `RenderStore.collisionTriangles`，只写私有 depth、关闭颜色，见 [Renderer.cpp:340](../onimusha/native/Renderer.cpp#L340)。原世界颜色已经在 backbuffer 中，这些三角形只是查询范围内的物理几何重画：无碰撞装饰、头发、草、部分动态物体和范围外物体都不完整；碰撞简化网格也可能挡住实际可见空隙。**私有 collision D32 不能称为真实 RE depth。**

当前 WorldVS 仅按 MC block/sky light 的最大值使用 `0.32 + 0.68 * light` 调整颜色，见 [Renderer.cpp:70](../onimusha/native/Renderer.cpp#L70)。它不读取 RE 太阳、点光、探针、阴影、曝光或雾。Atlas 建为 `R8G8B8A8_UNORM`，见 [Renderer.cpp:174](../onimusha/native/Renderer.cpp#L174)；目前没有原生 HDR/pre-exposure 或材质颜色空间的校准。[RenderStore.cpp:86](../onimusha/native/RenderStore.cpp#L86) 对 `kRenLights` 只接受消息，不创建 RE 光源。

当前适配器向 `bridge.set_camera` 提交 `valid=false`、`binding_ready`，渲染使用 MC 相机 fallback。[CameraProjection.hpp:15](../onimusha/native/CameraProjection.hpp#L15) 支持另一条 supplied view-projection 路径，但现 fallback 是 RH、近平面0.03、远平面2048、标准0..1深度。即使屏幕看起来对齐，也没有证明它等于实际 RE 的 jittered projection、near/far 或动态渲染 viewport。

透明候选按现有协议先画 opaque/cutout，再按实际三角形 centroid 和 mesh origin 排序画透明，透明不写 depth；HUD 最后关闭 depth，见 [Renderer.cpp:220](../onimusha/native/Renderer.cpp#L220)、[Renderer.cpp:280](../onimusha/native/Renderer.cpp#L280)、[RendererSmokeTests.cpp:116](../onimusha/native/RendererSmokeTests.cpp#L116)。这能改善 MC 物体之间的遮挡，不能使其受到 RE 灯光，也不能替代真实 RE depth。

## 上游 SkyCraft 如何接入 Skyrim

上游并没有把 MC 网格全部变成原生 Skyrim 材质对象。它保留自定义 D3D11 shader，通过已经掌握的 Skyrim runtime 与 SDK 读取并绑定真实引擎资源。

- [WorldRender.cpp:2894](../skse/src/WorldRender.cpp#L2894) `DrawInFrame` 从 `BSGraphics::Renderer` 获取 `kMAIN` HDR color、主 DSV/SRV、motion vector 和 normals。它核对 HDR format、color/depth 尺寸及单采样；不匹配则退回 finished-frame 路径，而不是盲用。
- [WorldRender.cpp:2442](../skse/src/WorldRender.cpp#L2442) `EnsureDepthCopy` 根据真实资源和 SRV descriptor 创建可读副本，随后 CopyResource，避免同时把同一 depth 当写入目标和普通 SRV。Skyrim 是 D3D11，不能照搬成 D3D12 无状态跟踪的复制。
- [WorldRender.cpp:3023](../skse/src/WorldRender.cpp#L3023) `RenderWorldHook` 先调用原函数，再 `DrawInFrame`；[WorldRender.cpp:3289](../skse/src/WorldRender.cpp#L3289) 用 Skyrim AE relocation 与期望 call-site 校验挂在 RenderWorld 完成后、后处理前。所有这些地址／ID 都不能用在 RE 游戏。
- [WorldRender.cpp:2787](../skse/src/WorldRender.cpp#L2787) 写真实 HDR、motion、normal 和 depth；[WorldRender.cpp:2852](../skse/src/WorldRender.cpp#L2852) 还更新已识别的原生 depth copies，使后续 fog/DOF 等使用含 MC 的深度。只写 color 或只读 depth 不能获得同样效果。
- [WorldRender.cpp:1642](../skse/src/WorldRender.cpp#L1642) `GatherLighting` 读取 sun/moon/interior directional light、室内／天气的六向 ambient、fog 和 nearby native point lights；[WorldRender.cpp:210](../skse/src/WorldRender.cpp#L210) 自定义 `Lighting` 把这些值与 MC sky/block light 合成。它不是完全借用原生 PBR shader。
- [WorldRender.cpp:1997](../skse/src/WorldRender.cpp#L1997) 及 `SunShadowRenderHook` 获取太阳 shadow cascades、descriptor 和矩阵；自身也绘制方块阴影。shadow map 与 screen-space shadow mask 是不同数据，不能拿一张灰图当完整光照。
- [WorldRender.cpp:1830](../skse/src/WorldRender.cpp#L1830) 有异步深度 probe；其 median 启发式只适用于该实现的诊断。鬼武者应把 clear value、depth compare、实际投影与已知近远物体共同作为证据，不能只按深度中位数猜 reverse-Z。
- [BlockLights.cpp:78](../skse/src/BlockLights.cpp#L78) 创建真实 `NiPointLight`，按合法 `LIGHT_CREATE_PARAMS` 注册 `ShadowSceneNode::AddLight`，并维护更新／RemoveLight。[WorldRender.cpp:1751](../skse/src/WorldRender.cpp#L1751) 从 native lighting sampler 排除这些自建光源，避免 MC block light 重复计算。MC 火把影响原世界需要这一类原生注册；仅接收 MC light 消息没有此效果。

因此有四个不同目标：RE 物体挡住 MC、MC 物体进入 RE 后处理／depth、RE 灯光照亮 MC、MC 光源／阴影影响 RE。不能把其中一个测试通过写成四者都完成。

## 已存在的鬼武者接口与仍然缺失的证据

固定 [API.h:96](../onimusha/native/vendor/reframework/API.h#L96) 的 `REFrameworkRendererData` 只有 `renderer_type`、`device`、`swapchain`、`command_queue`。回调包括 Present/device reset、pre/post named application entry、ImGui 和 pre-GUI-element。它没有场景 HDR/depth、DSV/SRV descriptor、当前 command list、资源状态或灯光常量接口。CPU application stage 有名字不等于已经获得可安全插入绘制的 GPU pass。

本地 TDB82 缓存已经证明以下实例方法存在，尚未在新建 MC 原生网格对象上调用：

| 真实方法 | 返回类型 |
|---|---|
| `via.render.Mesh.getMesh()` / `setMesh(via.render.MeshResourceHolder)` | `via.render.MeshResourceHolder` / `System.Void` |
| `via.render.Mesh.get_Material()` / `set_Material(via.render.MeshMaterialResourceHolder)` | `via.render.MeshMaterialResourceHolder` / `System.Void` |
| `via.render.Mesh.get_MeshReady()` / `get_MaterialReady()` | `System.Boolean` |
| `via.render.Mesh.get_Enabled()` / `set_Enabled(System.Boolean)` | `System.Boolean` / `System.Void` |
| `via.render.Mesh.get_StaticMesh()` / `set_StaticMesh(System.Boolean)` | `System.Boolean` / `System.Void` |
| `via.render.Mesh.getMaterialTexture(System.UInt32, System.UInt32)` / `setMaterialTexture(System.UInt32, System.UInt32, via.render.TextureResourceHolder)` | `via.render.TextureResourceHolder` / `System.Void` |
| `via.render.Mesh.getMaterialFloat4(System.UInt32, System.UInt32)` / `setMaterialFloat4(System.UInt32, System.UInt32, via.Float4)` | `via.Float4` / `System.Void` |
| `via.render.Mesh.get_DrawShadowCast()` / `set_DrawShadowCast(System.Boolean)` | `System.Boolean` / `System.Void` |
| `via.render.RenderEntity.get_DrawDepthOcclusionFlag()` / `get_DrawGlobalSparseShadowFlag()` | `System.Boolean` |
| `via.ResourceHolder.get_ResourcePath()` | `System.String` |
| `via.GameObject.create(System.String)` / `create(System.String, via.Folder)` | `via.GameObject`，静态方法 |
| `via.GameObject.createComponent(System.Type)` | `via.Component`，实例方法 |
| `via.GameObject.destroy(via.GameObject)` | `System.Void`，静态方法 |
| `via.GameObject.findComponents(System.Type)` | `via.Component[]`，实例方法 |
| `via.Transform.get_Parent()` / `set_Parent(via.Transform)` | `via.Transform` / `System.Void` |

[API.h:322](../onimusha/native/vendor/reframework/API.h#L322) 还提供 resource manager `create_resource(type_name, path)`，resource `add_ref`／`release`／`create_holder`。这证明 SDK 有加载入口，不证明某个路径、扩展名、holder 类型、加载完成条件和资源归属正确，更不证明该资源已经注册到当前场景。`create_instance` 不是对任意 native component 的完整初始化承诺。

本地 schema 列出 `via.render.Light`、`DirectionalLight`、`PointLight`、`SpotLight`、`LightProbes`、`SkyLight`、`LightRenderer`、`MeshRenderer`、`RenderOutput`、`RenderTargetHandles`、`RenderTargetView`、`DepthStencilView` 和 `ToneMapping` 等名称。实际 light 的多数字段只是 `v0`／`v1` 等匿名 `Data`，并无可证明的 Color/Power/attenuation 语义；`SkyLight.v1_Exposure` 是 F32 序列化字段，也不是已经验证的运行时曝光 getter。RT holder 在 TDB 缓存中的字段／方法可能为空。

schema 证据身份：本地 `downloads/re-collider-reference/rszoniwots.json` SHA256 `8216C1DB20003F7D87C805E770FDADE4CF5B3AABDE5862A5E42C724C9DD3432E`；fixed 版本 `C4FCFF451B43718F7606296207E51C573FE19AD6F76199D8F527A1C432C4D66A`。**序列化 layout/type 名称不是 COM resource、descriptor 或运行时偏移证据。** 不将 holder、`via.resource_handle` 或匿名字段强转成 `ID3D12Resource*`。

已有角色替换包中可见 `mesh.260209350` 和 `mdf2.51`；这证明该批资源文件曾按本机游戏格式制作，且现有已注册角色可以显示替换模型。它不证明动态顶点上传、空 GameObject 创建、任意 MDF shader 或新对象进入 world renderer 已成功。纹理和内部 mesh 版本继续按实际导出工具与本机文件核对，不能套用别的 RE 游戏参数。

## 路线 A：真实 depth 的最小只读消费原型

第一目标只做“原生物体挡住 MC”，先不写原生 depth，不接 HDR，不清空任何原生 target。必须先取得一次可复核的实际帧资源证据；下一次受控运行才可考虑资源观察／GPU capture，本轮没有新增这些 hook。

需要从真实 render pass 或资源创建／绑定轨迹关联 DSV/RTV/SRV 到资源与 subresource：资源 descriptor、视图 descriptor、对应 viewport/scissor、command list 实例和 reset generation、执行 queue、资源 barrier、fence 和 pass 顺序。单个 COM 地址、资源尺寸或 RenderTarget 类型名都不足以判定它是当前主相机的 depth；还可能是 shadow、Hi-Z、历史、AO、反射或另一相机资源。

| 必须确认的项目 | 最小证据与拒绝条件 |
|---|---|
| 实际资源与视图 | `ID3D12Resource::GetDesc`、真实 DSV/SRV format、dimension、mip/array/depth plane、sample count及是否允许 shader resource；CPU descriptor handle不能当GPU handle，descriptor会复用 |
| depth convention | clear value、PSO depth compare、近远世界点和真实投影共同确认 standard/reverse-Z；stencil plane独立处理；未知就关闭原型 |
| 相机／jitter | 同一 pass 的 view/projection/inverse、近远、相机原点、jitter及当前 frame；当前MC fallback矩阵不是认证RE projection |
| 动态分辨率 | 内部depth尺寸、有效viewport/rect与最终backbuffer的映射，缩放、letterbox、jitter UV；不得按swapchain尺寸猜内部depth大小 |
| MSAA | sample count和视图为Texture2D/Texture2DMS的真实类型。首先只支持已证明的单采样；不能把depth当color盲做ResolveSubresource，depth reduction规则需单独验证 |
| color空间/HDR | 不因backbuffer是大尺寸或浮点就当scene HDR；后续需GetColorSpace1、原scene格式、pre-exposure、tone-map前后证据 |
| state／queue | 当前各subresource状态和实际读写执行顺序；D3D12没有通用GetCurrentResourceState。不能猜COMMON/PRESENT，也不能把另一queue未完成的resource直接读 |
| lifetime／reset | 资源/descriptor/heap generation、aliasing、ResizeBuffers、动态分辨率重建、device lost；AddRef不能保证alias heap内容仍属于本帧 |

通过认证后，优先在原引擎最后一个有效 depth producer 之后、资源生命周期允许的点创建**自己的可采样快照**，使用兼容的 typeless/view format和正确subresource/state转换，并还原引擎预期状态。若使用独立 queue，必须与producer/后续consumer做明确fence同步；最小原型优先已认证的同一graphics queue。只读捕获仍可能需要合法barrier，不等于可以任意CopyResource。

Present阶段自定义PS将MC片元用相同相机、jitter和viewport映射投影，比较认证scene-depth snapshot；可用同projection下的device depth，或经真实inverse projection得到view depth，绝不能混用当前MC near/far公式与未知RE depth。此步不写原depth、不会使MC物体被原生fog/DOF/SSR处理，也不会让MC方块向原世界投影。

若现有D3D11-on-12继续使用该快照，wrapped-resource in/out state和Acquire/Release也要单独验证。不要把主scene HDR/depth也照着backbuffer的PRESENT→PRESENT包装。缺少认证同步时应保留现有明确标注的近似模式或停止新模式，不能把错误depth当成已经融合。

## 路线 B：后处理前的 HDR／原深度融合

获得A的真实资源证明后，才研究在鬼武者实际opaque/lighting完成、post-processing之前接入。固定SDK没有这个完整GPU入口；CPU相机 `lateUpdate` 的返回位置，只证明相机覆写顺序，不证明scene command list录制/执行到了此点。

最小原型应先只有一个opaque测试面，直接D3D12 pass更容易明确PSO、descriptor heap、root signature和resource states；若坚持D3D11-on-12，必须证明interop在该pass合法并不会提交到错帧／错queue。记录插入前后原有color/depth/normal/motion资源身份和状态，不能复用Skyrim relocation或调用原生whole renderer update。

真正进入HDR时使用linear albedo、经认证的native pre-exposure；不能把目前的UNORM颜色和固定亮度直接当linear radiance，也不能先手动tone-map再让原游戏tone-map一次。原始HDR resource与最终显示HDR色彩空间是两回事。

opaque/cutout的depth写入、normal编码、velocity/motion vector、TAA历史及必要depth copies必须逐项验证；只补主depth可能仍被随后Hi-Z重建或历史copy覆盖。透明物体仍按正确pass测试深度而不写入，第一次接入不要改原scene的透明排序。MC avatar、动态实体和新建／拆除方块需要正确前帧几何/相机运动；固定零velocity会产生鬼影。HDR接入成功本身也不提供太阳shadow sampling、GI或PBR材质，不能宣称原生光照已完整。

风险包括device removal/TDR、队列死锁、descriptor复用、临时资源alias、原rendergraph状态破坏、TAA/FOV抖动和后处理图层覆盖。未知format/state/queue/reset即关闭该原型，保持原renderer/state恢复；所有GPU等待有界，读回异步，禁止在游戏帧无限等待。

## 路线 C：原生 Mesh/MDF 注册

若目标是原生光照、阴影和后处理都按游戏规则处理，合法原生Mesh/MDF是值得并行验证的路线。先离线生成一个自有unit cube或小chunk的匹配MESH/MDF/TEX，使用可确认的标准受光材质而非unlit；保留原游戏文件。已有角色替换和资源loader方法可作为文件格式依据，不能作为新对象生命周期证明。

最小原型分两关：先验证自有资产在已存在、已注册的可控渲染对象上加载及实际受光；再研究一个新对象的合法创建／场景归属／组件初始化。具体 `create`／`createComponent`、Folder/Scene owner、RenderOutputID、Transform与resource holder归属、异步MeshReady/MaterialReady、culling bounds、draw/shadow flags和销毁线程时机都需readback和实际frame观察。资源loading成功或holder refcount增加不等于renderer已经接受新entity。

只有“创建→显示→受光→被遮挡→安全移除→切场景/reset重建”全流程通过，才扩大到MC chunks。避免一方块一个GameObject的无界增长；考虑chunk合并和少量共享材质/atlas。Mesh/MDF资源loader不提供已经证明的每帧动态vertex上传API：不能将setMesh当setVertices。频繁写磁盘重载全部chunk、无限resource cache或裸改GPU buffer也不构成可用方案；后续需要有预算的dirty chunk和合法资源替换，并证明旧GPU/holder已释放。

avatar/手持物/粒子每帧动态变化更难，可能保留custom renderer并使用A的深度，而opaque块先走原生chunk；该混合方案仍需分别验证光照一致性。标准native材质可参与哪些shadow/GI/SSR取决于其真实shader与flags，不保证所有效果自动具备。**不启用此前导致崩溃的physics/RCOL allocator；渲染注册与碰撞注册是独立流程。**

## 路线 D：RE 灯光采样到 custom shader

这是现有独立renderer的局部改善路线，可与A分开原型，但尚缺有效运行时灯光采样接口。先只读识别真实scene Light组件及其当前owner，获得有明确类型/语义的color、direction/position、power unit、radius/attenuation、enabled/light mask、spot cone、native ambient/probes和exposure getter。匿名schema字段不够，不能猜偏移或把原backbuffer亮度反推为准确光照。

采样线程只输出有界纯数字snapshot给renderer：frame/epoch/owner generation、坐标基、linear color与强度单位、方向、距离与有效范围。灯光对象不能在Present任意解引用，不能跨scene继续使用旧snapshot；当前D3D私有shader的常量layout和shader计算需显式扩展。没有合法getter的项目保持unknown，而不是补一套假native数据。

[protocol/skycraft_protocol.h:506](../protocol/skycraft_protocol.h#L506) 的 `RenVertex` 已含MC tint/AO、block/sky light和flags中face-normal信息。块面可按实际MC Direction ordinal在 **MC/RE统一XYZ、Y-up** 下解码；不能照抄上游Skyrim Z-up的normal表。未带normal的avatar/物品需要用实际导出几何计算或认证shader derivative，处理变换、退化面与双面，不能默认全朝上。

正确做法是在线性空间把认证RE directional/point/ambient项与MC光源项合成，并明确避免同一MC火把已写入MC block light又在native light采样中重复贡献。只用灯光列表不提供shadow、GI遮蔽或fog：将这些缺口写明。若仍在Present后画，还要处理原场景tone-map/exposure一致性；重写一个近似tone-map仅能称近似，不能说已经经过原游戏后处理。

MC火把照亮鬼武者地面是另一条注册路线：需要真实RE Light创建、scene注册、更新和移除，当前没有被验证的 `NiPointLight::Create/AddLight` 对应入口。不要用schema的PointLight类型或一个空component代替完成的world light。

## 最小原型与验收顺序

| 原型 | 先决条件与最小测试 | 通过后可以声称／仍不能声称 |
|---|---|---|
| A0 资源证据记录 | 同帧主camera/viewport/DSV resource与descriptor、barrier/queue/pass关联；多个场景/resize对照，不新增绘制 | 仅“定位候选资源”，没有视觉融合 |
| A1 depth只读采样 | 单采样standard/reverse-Z实验夹具、兼容view、前后状态还原、queue/fence、jitter/不同viewport尺寸、失效关闭；真实墙/动态NPC/无碰撞装饰前后移动 | “认证RE depth遮挡MC”；没有MC原depth写入、光照或阴影 |
| C1 自有native测试cube | 已加载合法Mesh/MDF、正确scene owner、普通场景灯光下读回与可见观察、移除与场景重载；另查bounds/shadow/material | 只对该测试资产“原生受光/遮挡”，不能扩大到动态MC所有几何 |
| D1 一个真实灯光snapshot | typed getter/readback；开关/移动灯与标准cube/MC面同时对照；单位、gamma与normal方向验证 | “该灯采样到custom shader”；没有完整native shadow/GI |
| B1 一个opaque HDR测试面 | 真GPU pass、HDR/pre-exposure、depth/normal/velocity格式、state/queue完整；后处理前后数据和scene readback | 仅明确通过的HDR/depth项目，不自动等于完整RE PBR |
| 扩容和恢复 | 多chunk dirty更新、透明、F5/avatar/GUI、TAA/动态分辨率/MSAA不支持时fail-closed、F10恢复、ResizeBuffers/device lost、切场景、资源/VRAM/CPU/GPU预算 | 完成测试覆盖的运行范围，未知选项继续禁用 |

新增GPU原型先在隐藏窗口D3D12实验夹具验证resource transitions、format/view、排序、标准/reverse-Z和resize，随后才做真实游戏验证。实验夹具模拟scene depth不等于已经找到原游戏depth；源码编译与WARP像素通过也不能替代实景证据。每个独立候选保留hash/日志并可回退，研究文档不能写成已交付功能。

推荐先取得A0资源证据，同时离线准备C1合法自有cube；根据可获得的真实GPU/对象生命周期证据决定继续A还是C。D只有typed运行时灯光入口被确认后才实现；B在A的资源与时序基础上推进。今晚不推测新的hook地址、不调用未知allocator、不运行live probe。透明候选FC445继续独立保留。

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯
