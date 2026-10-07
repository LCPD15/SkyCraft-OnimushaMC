# 鬼武者适配验证 / Onimusha validation

当前处于开发和场景接入阶段。更新时间：2026-10-07。本记录只覆盖 OnimushaWotS 的本地版本，不覆盖其他 RE 游戏。

最新验收：BC6A转向时任务图标和敌人血条正常跟随，F10恢复通过。Lua466822/JAR22004的MC格挡音效、未格挡正常扣血已由用户确认；原生受伤/MC恢复道具双向HP同步正常。7MC→700原生HP已实测，倍率100生效，完整平衡未验收。敌人原生反馈已通过：稳定资产双 profile 首轮8次，活动受击范围版14次，用户确认此前打不到的敌人也能扣血和反馈；远程距离补丁待实景。MC方块站立不代表原生NPC碰撞；真正RE深度和光照未接入。

Latest acceptance: turning world-space UI and release passed. Lua466822/JAR22004 passed real blocking sound and ordinary HP loss; healing synchronizes both games. The scale100 HP path is verified, while native enemy feedback passed 8 shared-profile hits and 14 hits with active damage bounds; the projectile range correction awaits live verification. Native NPC block collision and true RE depth/lighting remain unfinished.

2026-10-06 场景加载期间出现一次游戏本体空指针崩溃。当时 MC 未连接、接管未开启、GPU 绘制未初始化；同时启用了新增原生碰撞对象测试，具体根因尚未确认。停用 DLL 和这些测试，仅保留严格只读 Lua 后，用户确认可以正常进入场景。当前默认配置为只读阶段 A，新增原生 Collider/RCOL 创建及零伤害钩子测试均关闭。

A loading crash occurred in the game executable while Minecraft was disconnected and takeover/rendering were disabled. Native collider allocation tests were also enabled; the cause is not yet established. The user confirmed normal scene loading after disabling the DLL/tests and retaining read-only Lua diagnostics. Defaults currently select stage A and disable native collider allocation and health mutation tests.

随后在同一进程通过了阶段 A（DLL 加载与只读 Lua）、阶段 B（地形导出）和阶段 C 的普通受击观察：`addHealth(int,bool)` 捕获了 6 次玩家负血量变化，接管仍关闭。移动后另发现地形查询的临时 managed 对象被回收复用，已显式保留 query/result 引用并检查类型；再次运行导出 9,774 个三角形、0 不支持形状，查询类型保持正常。不能据此断言此前空指针崩溃的全部原因也已解决。

03:13 起完成首次真实游戏接管：D3D11-on-12 初始化 3840×2160，场景内显示 MC 心形血量、快捷栏、第一人称剑盾及 F5 第三人称角色。原角色隐藏，配置关闭后恢复绘制和原相机 FOV。背包可打开，但连续点击发现鼠标内部位置被重置到中心；已编译位置同步修正，实际复测待完成。自动化绝对鼠标输入未能可靠转动视角，不能把角色显示成功当成 3C 对齐验收。

04:45–05:06 再次实测（游戏 PID 49912、MC PID 111500，stage20/area78）：原生地形 9,822 个三角形、0 不支持形状；F10 可开启接管，HUD 和原角色隐藏正常。首次传送后 host 与 MC 的 yaw 都为 -90°、pitch 都为 0°，旧 MC 存档的 -57.75° 仰视角已被覆盖。关闭接管后原角色和 FOV 41 恢复；输入恢复使用真实 `REManagedObject:set_field`，123 个字段写后回读成功、错误为空。此前 `REField:set_data` 不存在及 `get_elements()` 被误判为 table 的两项故障已修正。

The second live run verified the initial host-to-Minecraft rotation and ordinary takeover release. Both sides reported yaw -90° and pitch 0°; the previous saved pitch was replaced. The native character and FOV returned after disabling takeover, and 123 input fields were restored with readback confirmation. This verifies the tested scene's ordinary release path, not all menus, cutscenes or input-object replacements.

背包坐标仍未通过：05:00:51 点击预览图中的第一格（895,767），MC 先收到正确的 host 坐标 671,575，随后收到中心 960,540，最终在 GUI 坐标 240,135 点击了第五格。按钮 LPARAM 在该自动化操作中也已经被原游戏居中；不能靠沿用旧位置来伪造通过，因为会破坏真正的中心点击。当前工具没有可控制的相对鼠标或持续按键接口，完整视角、行走、战斗和建造继续待验证。按照用户要求，已停止实际电脑测试、正常退出游戏，MC 于 05:06:04 保存退出；运行配置恢复为关闭接管的只读阶段 A。

Inventory clicking remains unresolved: the native input stream changed the correct event coordinate to the window center before the click. Absolute-position automation cannot establish relative mouse control. The live test was stopped at the user's requested boundary, the host was closed normally, and Minecraft saved and exited. The installed configuration was returned to read-only stage A with takeover disabled.

本轮实测 DLL SHA256 为 `CCC46A7044EBE197ABD401D75B3975D66DE97808E7284E0BA34B9F373A350E97`，Lua 为 `6E2FBCBB60716DC72A25C74663376B50E6B41575353A2503F762854570D17B45`，JAR 为 `7BF4F2047463984252282420B9239666CA7AEC4DD685BB89E5F46D055C339851`。后续 Lua 增加失败恢复记录保留/重试、原绘制和 FOV 验证及显式 no_dirty 参数，已通过回归检查，尚未复测实景；新编译文件不能沿用旧 hash 的实测结论。日志：`logs/game-cursor-events-20261006/` 与 `logs/game-client-cursor-events-20261006.stdout.log`。隔离世界测试后备份已逐文件校验。

停点版本：Lua `903F5959B7B29A2F0E666D691AB356DD033159FB8E60027816BDA119B68BF835`；DLL `E5A0F1A81EE2417D289783DC00EB37919CDBDF3676AAD9BA2536F638D0D161B8`。DLL 同时移除了多余的 WM_INPUT `DefWindowProc` 调用：固定版本 REFramework 的 WindowsMessageHook 在插件返回 false 后本身会执行一次，插件不应重复清理。对应真实 DLL 接口回归已实际通过、无跳过；此变动尚未在游戏中复测。JAR 保持上述已实测版本。

The saved checkpoint additionally retains failed restoration records and delegates WM_INPUT cleanup to the verified REFramework message wrapper. Regression tests passed; these post-run changes still need a live retest. See [resume notes](ONIMUSHA-RESUME.md) before continuing.

2026-10-06 下午由用户接手实测。先确认停点 DLL `E5A0F1…` 的阶段 A 正常加载；随后正常退出，安装 DLL `2B64F161513771E75173889EFCD32F19527BCCCA4729A83A44BE87DF9379CF07` 与 Lua `D2330D4711E605D65AC5DEBAE69A06991744CB7385897EA2CA89B36ED147B32C`。阶段 C 保持默认接管关闭，所有新增原生碰撞对象及伤害测试仍停用；用户确认正常进场景，导出 9,822 三角形后连接同一 JAR。按 F10/E 后，用户确认背包左侧第一格及另一中间格的光标、高亮和所选物品一致，鼠标移动正常。原生报告真实 GUI RAW 包 4,791、fallback 包 0；MC 日志记录不同的 GUI 点击位置，不再固定为中心。日志和实测 DLL/Lua 副本保存在 `logs/live-human-20261006/`。该结果仅覆盖这次背包选择，持续3C、战斗、建造及菜单恢复继续分项验收。

The user took over physical input testing in the afternoon. The new virtual-cursor DLL and reset-guard Lua loaded normally in stage C with takeover initially off and experimental tests disabled. The user confirmed correct inventory hover/selection for both the leftmost and a central slot. Genuine GUI RAW packets reached the native plugin, and Java logged distinct click coordinates. This verifies physical inventory selection for the tested build and scene; it does not establish the remaining gameplay or recovery checks. The game save and all 28 isolated MC world files were backed up and hash-checked before this run.

同一轮用户确认：上下视角、前后移动、碰撞、F5 正常，但左右视角和 AD 侧移反向。数学复核确认旧 XYZ→XY−Z 的反射会使前向一致、右向相反；随后统一 XYZ 基，相机采用 `yaw=180−MC yaw / pitch=−MC pitch`，备用渲染相机的视图和投影同时改为 RH，三角形保留 A/B/C 绕序。关闭旧接管后用户确认原角色、移动与原菜单均恢复；D233 的报告有 63 次输入恢复写入、无错误且 input/draw/FOV pending 都为零。鬼武者与 MC 正常退出后，修改过的旧 MC 世界 33 个文件再次备份并逐文件核对。

新版 DLL 为 `8D9056C815A4B66562E1AC1AD5790829993ACEAB5D1C06D13279793B26D709B1`；当前 Lua 为 `1A6F1D8DE85D34AFB348D560F2381397FCB6EA169FBC57E0F982588EBA2E96E1`。三项 CTest 均实际通过、无跳过：真实 DLL 回调覆盖 ReleaseAll 排在下一输入之前，矩阵检查覆盖 8 方位×7俯仰×3F5，GPU 像素确认 MC 右向在屏幕右侧。7 个 Lua 回归脚本通过，包括 37 个 PASS 组及 8 个配置案例（共45组）。JAR 未改变。新实景运行使用独立 `OnimushaMC-XYZ-v2` 世界。复杂场景的半径32导出 12,141 三角形触发单次12M体素候选检查预算，正确拒绝接管；运行半径改16后成功，未提高安全预算。源码及全部配置默认半径16，重采样余量为半径一半且不超过12格。Reset Scripts 后重新导出并确认新 epoch、连接及地形就绪；新版3C实景验收正在进行。

The old physical test exposed a reflected right axis even though forward movement worked. The fix changes position, native rotations and renderer projection as one coordinate contract. Standalone direction/winding/matrix/GPU checks passed. A new isolated world avoids reinterpreting old placements. In the more complex scene, radius 32 exceeded the existing voxel work limit; radius 16 succeeded without raising or bypassing that limit. The new build's physical camera/movement acceptance is still pending at this checkpoint.

上述新版本随后由用户实测通过：鼠标左右/上下、WASD 四向移动、跳跃、墙体/台阶碰撞、F5 三视角、E 背包两格点击均正常，另确认 MC 物品放置正常。测试后的 `status-after-direction-pass-flash.json` 保存于 `logs/live-human-xyz-v2-20261006/`。用户同时报告接管偶尔瞬间失效、闪回原角色，因此持续接管稳定性仍未通过。该快照的 `rejected=415` 与半径32失败后相同，期间未新增拒包；不能据此把本次闪回归因于新的预算超限。代码确认每次移动超过8格重新查询地形时会立即清掉 Lua `collision_ready`，3178三角形按每帧1600导出需要多帧，足以触发原绘制恢复；正在修正完整地形批次的交接并增加退出原因日志。

The user then passed physical mouse direction, four-way movement, jumping, wall/step collision, all three F5 views and two-slot inventory selection with this coordinate build. Item placement also worked. Sustained takeover remains unresolved: the user observed brief returns to the native character. The post-test rejection count remained 415, unchanged since the earlier radius-32 failure. The Lua refresh path clears readiness while collecting terrain over several frames; complete-batch handoff and explicit release diagnostics are being implemented. This is a diagnosed code path, not a completed live fix. Block removal, placed-block collision, combat and health round trips still require separate acceptance.

同一坐标版随后关闭接管，用户确认原角色与原操作恢复；`status-restored-after-F10.json` 的输入恢复写入123次、错误为空，input/draw/FOV待恢复项为零。碰撞交接修正版已构建但此刻尚未安装：DLL `5291E47D62D33D9ED8B7B95A9B285256C02E509D18115AAA0F6F104401F44931`；Lua `0E8ED3A83F9C83ECF062AF89F8CCCCBC7DFBF315A23BFF0FE0EE681AEACA30D9`。Lua8脚本55组通过，跨进程整批/绕回/容量不足/消费序号及GPU检查通过；真实DLL Lua接口因游戏仍持有正式映射而按77跳过，退出后必须重跑，不能标成三项全部通过。

修复保留相同epoch/配置/MC进程/连接代次的已认证碰撞。成功发布新批次后，旧认证范围收窄至旧、新真实查询AABB交集，避免MC逐cell替换使padding边缘变为错误认证；整批消费确认后才切换新范围。未完成、95000上限截断、未知primitive、读取失败、队列不足或范围外不会伪装为就绪。当前只认证实测单位比例1；其他比例在native身体尺寸实测前拒绝接管。新增最近16条真实退出记录、分类计数、碰撞耗时及连接年龄，保持原预算和实验碰撞开关不变。

The user also verified release of the coordinate build; the log confirms 123 input restoration writes with no errors or pending input/draw/FOV records. The handoff build above has not yet been installed or physically tested. It retains certified same-session terrain, narrows retained bounds to the old/new query intersection when queuing, and switches only after complete consumption. Partial or truncated queries remain unready. Default unit scale 1 is the measured body envelope; other scales require native body measurements. The actual DLL API test is explicitly pending after its live-mapping skip. Telemetry records real release transitions, packing time and connection age without raising existing limits.

随后用户正常退出鬼武者，MC于20:21保存退出。XYZ世界28个文件及原游戏存档已备份并逐文件核对SHA256。上述修正版三项CTest重跑全部实际通过、无77跳过，日志 `logs/native-handoff-after-game-exit-20261006.txt`；Lua复跑55组通过，日志 `logs/lua-regression-handoff-20261006.txt`。DLL/Lua已安装并核对manifest，运行配置为C、接管关闭、半径16、实验原生碰撞及合成血量测试关闭。游戏修复效果等待下一次实测。

After normal host/client exit and verified save backups, all three CTests passed without skips, including the actual new DLL's Lua API, integer generation/sequence diagnostics and invalid-ring gates. The new DLL/Lua are installed and hash-checked with takeover off. Their in-game handoff acceptance remains pending.

用户确认5291 DLL正常进入场景；同一XYZ世界连接后，新3264三角形批次seq1完整消费，pack耗时178.6ms、pack/queue失败0。此时发现MC旧位置z22在新native目标z42的查询范围外，双foot检查把host.ready也关闭，阻止首次MC传送。Lua更新为 `AD35E3FAF8348840FDDB9259E344E7F32BB30537D731F7EC65580049722CDB3E`：未确认传送时仅以已消费的native目标覆盖发布bootstrap就绪，native ack gate仍禁止接管/绘制/输入；确认后继续检查两个身体范围。F10明确关闭→开启时仅增加传送seq、保持地形epoch，重新同步当前native位置；active未知越界不会被强制传送掩盖。新增7组实际production tick回归，共9脚本62组通过。已在接管关闭时热更新，等待Reset及实景结果。

The new DLL loaded normally and the 3264-triangle batch was fully consumed with no packing/queue failures. The saved MC pose outside the new target AABB exposed a startup readiness cycle. The Lua-only revision separates certified target bootstrap from pose takeover; acknowledgement and both body bounds remain mandatory for control. Explicit off-to-on reserves one new teleport sequence without clearing terrain. Active unverified movement never forces a resync. Seven production tick cases passed, for 62 Lua cases total; the installed Lua awaits reset/live acceptance.

用户Reset后，MC/native位置及新传送确认一致，完整覆盖就绪。随后用户连续移动、转向、跳跃并跨采样距离实测，确认没有再闪回原角色。`status-after-continuous-walk-pass.json`记录24次查询/入队/消费完成、失败0、拒包0；只有原菜单和关闭桥接两项退出原因，没有地形或连接退出，最大pack耗时178.6ms。用户另确认放方块后可以跳上稳定站立，拆除后原位置恢复畅通；对应快照为`status-after-build-collision-removal-pass.json`。这些结果覆盖本次stage0/area0，其他场景和长时间运行继续分项验证。

After reset, the user passed continuous movement, turning, jumping and traversal across refresh thresholds without native-character flashes. All 24 terrain updates completed with zero failures or rejected packets. Recorded releases were native-menu ownership and explicit bridge disable, with no terrain/connection release; maximum packing time was 178.6 ms. The user also stood on a placed block, removed it and walked through its former position successfully. This verifies the tested stage0/area0 and build, not every scene or prolonged session.

## 已完成的独立检查 / Completed standalone checks

| 检查 / Check | 证据 / Evidence | 边界 / Limit |
|---|---|---|
| Fabric JAR 编译及 43 项测试 | Gradle test XML；健康百分比、协议布局、GUI 坐标及绝对传送朝向测试 | 不证明完整游戏玩法或背包点击已修复 |
| 真实 DLL Lua API | 加载编译后的 OnimushaMC.dll，测试实际 Lua 接口与无效 HP 拒绝 | 使用测试 REFramework 回调 |
| 跨进程共享内存 | 子进程读写映射、输入、HUD、事件及网格解码 | 模拟 MC/host 数据 |
| D3D12 GPU 绘制 | WARP 设备、隐藏窗口、GPU 像素回读；网格、纹理、HUD 透明合成 | 非鬼武者实际 GPU 帧 |
| 地形遮挡、F5 角色显示 | 地形深度前绘、第三人称角色纹理、第一人称不绘制角色 | 使用合成几何 |
| 设备重置与尺寸变化 | reset、ResizeBuffers、重新创建及像素断言 | 不证明所有游戏图形设置 |
| 游戏版本及玩家对象 | 实际游戏 TDB 82；场景只读探针包含 app.cPlayerManageInfo、PlayerCharacter 和 via.Camera | 读取成功不等同于接管成功 |
| 真实 Minecraft 客户端通信 | MC 26.3/Fabric 实际启动，atlas 2048×2576、方块网格、1356 顶点角色网格、HUD、移动、菜单及攻击事件 | 原生 host 为独立模拟进程，未接管鬼武者 |
| 真实 MC 伤害往返 | 原 HP 75 → 68.1，3 点未结算 MC 伤害经过护甲减免；两次查询 MC HP 13.62，无重复扣血；治疗后原 HP 88.1、MC HP 17.62 | 未验证鬼武者敌人实际攻击钩子 |
| 场景 epoch 与方块拆除 | 旧 epoch 健康事件被拒绝；方块网格及实体占用新增后均可移除；host 退出后 MC 保存并退出 | 原游戏实体方块注册仍待确认 |
| 宿主重启专项测试 | 两个模拟 host PID 复用 epoch/seq 1；同一真实 MC 客户端持续运行；新碰撞前 88 次采样 ack=0，随后 ack=1；atlas、已有方块网格与 solidbit 重新导出 | 独立模拟 host，不含真实游戏控制；排队健康事件的跨重启拒绝只有单元测试证据 |
| 原生地形查询 | 实际鬼武者场景 20/78 导出 8,450 个三角形，0 不支持形状 | 地形已读取，实际 MC 行走仍待验证 |
| 分阶段恢复与普通受击 | DLL + A 正常；B 导出 9,821 个三角形；C 捕获 6 次玩家原生负血量回调，用户确认受击后正常 | 当时 MC 未连接；查询引用失效随后单独修复 |
| 真实游戏首次绘制与接管 | 游戏 PID 56472 + MC PID 91036，stage20/area78；HUD、剑盾、F5 角色可见，active/ready=true，零拒包；关闭接管后原角色可见 | 原始按键恢复、背包连续点击、视角、战斗和建造尚未完整验收 |
| F10 消息与鼠标事件路由 | 三项 CTest 实际通过、无跳过；用户真实鼠标确认两格背包点击正确；GUI RAW 包非零且 fallback 为零 | 2B64 DLL 的实景结果；后续构建不能直接沿用 |
| 输入与绘制恢复 | 实景普通 F10 关闭：旧版123字段及D233版63次必要写入回读成功，原角色/操作/FOV恢复；坐标版7个Lua回归脚本共45组通过 | 菜单/切场景/输入对象替换待实测；永久 setter 失败或 Lua 销毁限制见 RESTORATION.md |
| 原生地形打包压力测试 | 8,450 个三角形、729 区域、1,458 数据包；满队列安全拒绝；AddressSanitizer 无错误 | 独立进程，不证明游戏对象生命周期安全 |
| 新生成的 unit-box RCOL | `.rcol.37` 序列化并重新读取；1 group / 1 request / 1 Box | 文件格式检查不能替代游戏物理注册 |

## 实际游戏验收 / In-game acceptance

以下各项必须通过真实游戏测试后才可标记通过。尚未验证的项目保持待验证；不能用功能已写入代码替代结果。

| 项目 / Feature | 当前状态 / Status | 验收条件 / Acceptance |
|---|---|---|
| 玩家位置与相机接管 | 方向、四向移动、跳跃及F5通过；5291/AD35持续移动不再闪回，24次地形刷新无失败 / Physical 3C and refresh handoff passed in tested scene | 其他场景和长时间运行继续验证 |
| 原角色隐藏与恢复 | 基本绘制通过；菜单/过场待验证 / Basic draw verified | 接管时隐藏；关闭后恢复已实测，菜单、过场或断开需继续验证 |
| HUD、物品及 MC 角色绘制 | 实景绘制与两格 GUI 点击通过 / Rendering and two-slot physical GUI selection verified | HUD、剑盾、F5 角色及背包已显示；更多界面、遮挡及视角对齐待验证 |
| 原地形碰撞 | 当前场景墙体和台阶实测通过；切场景待验证 / Walls and steps passed in tested scene | 地板、台阶、墙体、场景切换正确且不掉穿 |
| MC 方块建造和拆除 | 放置、站上方块、拆除后走过原位置实测通过 / Placement, player collision and removal passed | 原地形不可拆除；NPC实体方块碰撞另列实验项 |
| 鬼武者实体方块碰撞 | 未实现有效原生碰撞，用户确认无法阻挡敌人；实验创建仍停用 / Native NPC collision failed; experimental creation disabled | 原游戏实体受方块阻挡，拆除和切场景不残留碰撞；不得自动启用未验证创建路径 |
| MC 战斗 | 稳定双 profile 原生反馈及通用受击范围实测通过 / Shared native profiles and active hurt bounds passed | 8+14次原生队列、特效／声音观察点匹配且用户确认；全Boss阶段、致死奖励、破甲和远程距离补丁仍待覆盖 |
| 原生世界空间UI | BC6A原生lateUpdate结束同步后，用户确认转向时任务图标和血条正常跟随，关闭接管恢复 / Turning and release passed | 证据logs/live-camera-bc6a-20261007；更多场景仍需验收 |
| MC格挡与受击 | Lua466822/JAR22004，用户确认格挡音效及正常扣血 / Block sound and HP loss passed | 红闪、击退、火花、背后攻击和特殊弹反未逐项验收 |
| 金苹果 | 新增4×64普通金苹果用户已确认 / Four stacks verified | 写入前独占锁定和完整世界备份，禁止重复添加 |
| 百分比心形血量 | 敌人攻击扣血及MC道具双向治疗用户实测通过 / Native hurt and MC healing passed | 最大血量变化、死亡、盾牌方向及菜单边界下的已拦截伤害仍待验证 |
| 原场景深度与遮挡 | 私有碰撞深度，用户确认遮挡异常 / Private collision depth; native occlusion failed | 接入真实主场景深度并验证动态角色、装饰、动态分辨率和投影 |
| 原游戏光照与阴影 | 尚未接入，MC自身亮度不能替代 / Native lighting/shadows not integrated | 验证室内外光照、原生阴影和渲染阶段 |
| 过场和原游戏交互 | 待验证 / Pending | 原游戏交互保留；过场不抢相机或残留输入 |

实际测试日志保存在任务目录的 logs/ 和游戏 reframework/data/；日志不含登录凭据。发布前更新此记录并附可复现的测试环境。


2026-10-07 通用受击修复：两套资产从当前玩家解析，无需每种敌人或重载后人工采样。用户两次确认原生受击效果及各类敌人正常扣血；实际 hooks 每击匹配，未叠加 direct HP。20个Lua回归脚本全部通过；后续远程距离分支专项16组通过。近处活动受击AABB及飞行敌人效果位置已实景执行，仍是聚合代理，不能标为精确部位攻击。自动重载首装后连续5次成功到generation6，无DLL/JAR更新。远程 HIT_PROJECTILE 旧10米限制修正已安装，验收结果另补，不提前判为通过。
