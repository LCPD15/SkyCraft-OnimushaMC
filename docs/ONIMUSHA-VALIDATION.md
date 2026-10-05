# 鬼武者适配验证 / Onimusha validation

当前处于开发和场景接入阶段。更新时间：2026-10-06。本记录只覆盖 OnimushaWotS 的本地版本，不覆盖其他 RE 游戏。

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
| F10 消息与鼠标事件路由 | 实际 DLL 回调覆盖普通/系统首按、重复、松开、GUI 事件缓存及重置；三项 CTest 实际通过，无跳过；F10 在实景可用 | 中心按钮坐标仍覆盖 GUI 目标位置，实景 GUI 点击未通过 |
| 输入与绘制恢复 | 实景普通 F10 关闭：123 个字段写后回读成功，原角色/FOV恢复；Lua 输入10组、视觉3组、相机4组及两组既有回归通过 | 失败记录保留/重试补丁仅回归通过，菜单/切场景/输入对象替换待实测 |
| 原生地形打包压力测试 | 8,450 个三角形、729 区域、1,458 数据包；满队列安全拒绝；AddressSanitizer 无错误 | 独立进程，不证明游戏对象生命周期安全 |
| 新生成的 unit-box RCOL | `.rcol.37` 序列化并重新读取；1 group / 1 request / 1 Box | 文件格式检查不能替代游戏物理注册 |

## 实际游戏验收 / In-game acceptance

以下各项必须通过真实游戏测试后才可标记通过。尚未验证的项目保持待验证；不能用功能已写入代码替代结果。

| 项目 / Feature | 当前状态 / Status | 验收条件 / Acceptance |
|---|---|---|
| 玩家位置与相机接管 | 首次朝向同步通过，完整3C待验证 / Initial rotation verified | MC 移动和 F5 三种视角与原场景对齐 |
| 原角色隐藏与恢复 | 基本绘制通过；菜单/过场待验证 / Basic draw verified | 接管时隐藏；关闭后恢复已实测，菜单、过场或断开需继续验证 |
| HUD、物品及 MC 角色绘制 | 实景绘制通过；GUI 点击仍失败 / Rendering verified, GUI click unresolved | HUD、剑盾、F5 角色及背包已显示；连续点击、遮挡及视角对齐待验证 |
| 原地形碰撞 | 待验证 / Pending | 地板、台阶、墙体、场景切换正确且不掉穿 |
| MC 方块建造和拆除 | 待验证 / Pending | 放置和拆除立即显示，MC 玩家碰撞一致 |
| 鬼武者实体方块碰撞 | 实验功能停用 / Experimental, disabled | 原游戏实体受方块阻挡，拆除和切场景不残留碰撞；不得自动启用 |
| MC 战斗 | 待验证 / Pending | 命中正确敌人，伤害和死亡流程正确，不重复结算 |
| 百分比心形血量 | 待验证 / Pending | 75% 显示 7.5 心；受伤、治疗、最大血量变化、死亡正确 |
| 过场和原游戏交互 | 待验证 / Pending | 原游戏交互保留；过场不抢相机或残留输入 |

实际测试日志保存在任务目录的 logs/ 和游戏 reframework/data/；日志不含登录凭据。发布前更新此记录并附可复现的测试环境。
