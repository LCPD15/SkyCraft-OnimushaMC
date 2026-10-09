# 继续测试的停点 / Resume checkpoint

2026-10-08，仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。
其他 RE 游戏需要独立适配。MOD制作：LCPD15/LCPD拉灯。

## 最新结果与下一步

### 2026-10-10 可见 MC 窗口黑屏／放置输入修正版，等待原场景验收

用户确认同一场景离屏模式可以放置，因此按可见窗口引入的回归排查，未调整场景或建筑高度。
LevelRenderer 原来在桥接时完全跳过，ShowWindow 只显示 HUD。现在可见模式保留 MC 世界预览，
在世界后处理结束后保存预览，单独清空透明层绘制手与 GUI；FrameExporter 读回透明层后才合成窗口。
修正清屏 Vector4f 的默认 w=1 陷阱，显式设 alpha=0。隐藏模式继续使用原路径。
SDL 窗口键鼠回调与宿主注入输入隔离，只有 InputBridge 重放范围内的回调能改变桥接控制；
无 GUI 时恢复因焦点变化被释放的逻辑鼠标抓取，仍不抢占真实硬件鼠标。MC 可见窗口是预览，输入在鬼武者完成。

验证：Fabric build／78 项 JVM 测试通过。一次性世界 WindowSmoke-v4 中宿主右键放置成功，
打开／关闭背包后第二次放置成功，物品数量32→30；模拟本地 SDL 右键被拦截，releaseMouse 后逻辑抓取恢复。
GPU 截图已确认窗口显示石头与金块；宿主透明层310682/409920像素为全透明，其余主要是手、盾、HUD。
第一次透明度断言错误地要求80%，大盾和手占约四分之一画面；按该测试场景调整为60%，并保留原始计数。
最终 host.json passed=1、invalid_packets=0。隔离世界均已保存退出，未修改真实世界。
真实世界89个文件与备份逐项SHA256一致；备份 runtime/test-backups/window-preview-20261010-032310。
证据 logs/window-preview-20261010/，日志 window-preview-smoke-v3/v4.stdout.log；新增只限隔离世界的焦点测试工具。
新版 JAR 已安装，原 MC 世界重连 PID46916；鬼武者PID30324、转换器84528，保持暂停／接管关闭。
待用户关闭暂停、F10后复测放置／拆除、MC窗口预览和聊天不误触原生菜单。不可将隔离成功写作原场景已验收。
手动启动入口与文档仍见下方；MC窗口不绘制鬼武者地形，文档已更新说明。

随后用户确认创造可放、认为生存不可放，吃东西与拉弓正常。现场读取确认实际 GameType.ADVENTURE、mayBuild=false；
03:48:40 日志明确切到 Adventure，修正前备份玩家数据也为 playerGameType=2、mayBuild=0。
因此原场景放置失败的确定原因是冒险模式的正常规则，不是窗口可见、场景高度或原生地面。
通过集成服务器线程调用 ServerPlayer.setGameMode(SURVIVAL)，客户端与服务器均读回 SURVIVAL／mayBuild=true；
没有直接改运行中的存档，也没有给冒险模式绕过建造权限。恢复工具限制指定目录与原世界。
证据 live-mode.txt、restore-survival.txt、live-survival.txt；实际MC窗口截图已确认已有铁块正常显示。
仍待用户确认恢复 Survival 后的放拆与聊天。现役JAR SHA256 E6E54E0EC9217C58E639AC26E6F5FDB0A52BFBF154046F4E44614DBD6A8D80D1。

### 2026-10-10 MC 聊天输入隔离已安装；可见窗口与手动启动入口已完成

用户报告 MC 聊天键会触发原生菜单。WndProc 消费消息与 sealAllPlayer 不覆盖原生 UI 的独立输入。
现场反射与只读反汇编确认 GameInputManager.update() / sealAllUI，以及三个 UI 数组的 _SealAll／_IsSealed。
正式 Lua 在 manager.update 后，根据当前 MC screen_open/in_world、存活、接管和连接状态封锁
_UIInput、_PadUIInput、_MkbUIInput；关闭 GUI、断联、死亡、F10 关闭或 REFramework UI 打开时恢复原值。
UI 与玩家输入使用独立恢复记录，关闭 MC GUI 不会误解除仍在接管的玩家输入锁。
已自动热更 generation16，id 21b851cbbe1543b896b99dd41e6c0f52；没有 DLL/JAR 变更。
现场已捕获3组UI／597键且sealed=true，update后钩子上万次执行无错误；仍待用户确认打字不误触与关闭后正常。
随后现场接管已关闭，UI的600项原值恢复完成、pending_records=0、无错误；证据ui-input-runtime-restored.json。
输入生命周期、恢复重试、死亡交接、视觉恢复、初次定位、碰撞交接及渐隐回归均通过。
旧的定位／碰撞测试夹具漏了上轮死亡和渐隐依赖，已补隔离stub后通过；未据此更改运行逻辑。
只读采样证据 logs/chat-input-20261010/。

MC 已正常保存退出后以可见窗口重连，当前PID101968；原生PID30324、转换器84528。
新入口 G:\游戏MOD\0_自己做的Mod\鬼武者\MC\启动并连接MC.cmd，等效 G:\Onimusha_MC_mod\Start-OnimushaMC.cmd。
调用tools/Connect-OnimushaMC.ps1，固定现有世界，ShowWindow/QuitWithHost/SwordBlocking，复用MC和转换器。
Windows PowerShell实际启动与重复启动复用均已验证；PrepareOnly也会生成参数文件，不应在MC运行中用于日常检查。
当前实例26.3/Fabric，不能直接安装所查到的旧版Create；复杂机械绘制与原生碰撞未做兼容验证。
操作与兼容说明见 [启动与操作](ONIMUSHA-PLAY-GUIDE.md)。本轮没有再改库存／存档。

### 2026-10-10 移动恢复已确认；完整死亡重试与近距离渐隐待实测

原生卡死现场已恢复：HP归零但停留在MediumDamage，需要对当前加载的死亡动作发起标准requestBaseAction，
用户已确认正式Lua自动死亡／原生重试成功。正式Lua按确认致死→解除接管并恢复→动态查找死亡动作→一次请求处理。
MC的Gui.setScreen(null)会绕过旧DeathScreen参数拦截，已补内部条件拦截、遗留界面清理及原生回血后的dead标志恢复。
恢复不依赖F10／地形就绪／SKY_IN_GAME，保留MC角色、背包和经验。新JAR已安装，DLL未改。
真实MC客户端维护自测已通过界面拦截、旧界面清理、dead/deathTime恢复，HP与玩家对象不变；
但用户发现重试后只能转视角：LocalPlayer独立覆盖tickDeath，第20tick仍会移除客户端角色，父类拦截无效。
已补本地override拦截，真实MC连续30次死亡tick后实体仍保留、恢复后isAlive=true检查通过。
随后用户仍不能移动，真实快照确认客户端HP20但isRemoved=true/RemovalReason.KILLED。
旧tickDeath保护依赖当前血量权威标志／心跳，原生死亡读档时可暂时失效，30tick常连自测漏掉了此路径。
现用HostLifeLease按MC玩家／世界／内置服务器身份持有生命周期，读档缺失HP标志与暂时断联均不释放；
换MC玩家、世界或服务器／MC世界断开则清除。原生回血与伤害仍要求新鲜有效的原生状态，不能用旧数据回血。
78项JVM测试通过；真实客户端30正常+60缺失权威+60断联死亡tick均保留实体，恢复后isAlive=true。
用户已明确确认WASD与跳跃正常；完整死亡→原生重试→F10再移动仍待复测。
当前MC进程75596，日志live-life-lease-sword-20261010.stdout.log；loader generation14。
渐隐现于onLateUpdateEnd前setEnable(false)、后恢复准确_Enable字段；get_IsEnable包含未结束插值，不能作即时字段读回。
用户移动期间2254次实际consumer抑制成功，Enable=false、Near/FarAlpha=1，无错误；近敌视觉待用户确认。
用户追加补给已完成：背包现有7组不足上限的物品补满（附魔金苹果、南瓜、铁块、TNT、两组箭、门），
空余Slot0加入钻石剑：锋利V、横扫III、火焰附加II、耐久III、经验修补I。
按MC26.3实际附魔JSON验证最高等级、支持物品、互斥关系；不改其他物品组件／HP／XP。
补给前正常关闭MC，88个世界文件备份验证，原子写入后自动重连；收据logs/death-dither-20261010/inventory-sword.json。
鬼武者仍运行／暂停，接管关闭。无需Reset Scripts或游戏重启。
详细原因、验证及测试夹具故障记录见 [死亡与渐隐](ONIMUSHA-DEATH-AND-DITHER.md)。

### 2026-10-09 REFramework 五档伤害倍率已安装并验收

入口 Script Generated UI → Onimusha MC / 鬼武者 MC → Damage / 伤害设置。
100／500／1000／2000／5000快捷按钮及100～5000整数拖动，100对应原伤害，自动保存、即时生效。
复用 `enemy_host_damage_per_mc_point`，没有额外再乘一次100；MC实际命中值乘所选值，
最终限制在已验证原生入队上限100000。只调整此设置不会fail_open或使地形覆盖失效。
范围修正替代最初提议的0.1～100相对倍率，没有部署后者。

loader generation5自动热更成功，无DLL/JAR变更。用户确认面板按钮与重新展开后的保存正常。
最后配置和运行状态均读取到1000（原伤害10倍），无保存错误；保留这个用户选择，勿重置为100。
玩家承伤、护甲、回血及TNT原生爆炸不受影响。原生接管关闭，MC继续连接，无待用户测试问题。
相关5套回归共57组通过（UI6、伤害9、战斗15、原生队列17、重载10）。
安装备份及收据在 `logs/damage-ui-20261009/`，详见 ONIMUSHA-DAMAGE-BALANCE.md。

### 2026-10-09 护甲与武器实际伤害核查完成

用户要求确认 MC 护甲减伤，并按手持道具实际伤害结算。检查当前已安装版本发现两条都已接入，
本轮未重复增加倍率、未修改运行中的 DLL／JAR／Lua、无需重启。部署81项指纹均符合记录。

- 入伤：原生待扣血量 / 原生最大HP × 20 → MC `hurtServer` → 护甲、韧性、有效附魔、
  状态、盾牌等原生 MC 流程 → 最终 `setHealth` 拦截成百分比请求 → 原生 HP 单次结算。
  `health_bypass` 防止回写再次进入护甲计算。不是每件盔甲写死一个减伤百分比。
  当前现场一击原定扣248／2000，MC入伤2.48点，最终1.1150074点，鬼武者实际扣111，
  小数余量保留。此前真实隔离MC对同样10点入伤：裸装10、铁套6、钻石套3，三组均通过。
- 出伤：`Player.attack`／弹射物等 MC 流程已算完武器属性、有效附魔、暴击、攻击冷却等，
  敌人代理的 `actuallyHurt` 收集该实际值；事件a再乘 `enemy_host_damage_per_mc_point=100`。
  这是每1点MC伤害转100点鬼武者伤害，包含此前用户要求从10提升到100的十倍增强，
  不再把道具攻击属性重复乘一次。并非所有道具都造成同一个固定伤害。
- 原生队列把本次runtime的 Attack置0、FixedAttack置上述换算值，保留两种随机原生受击模板。
  模板本身的100／300攻击力不会覆盖MC数值；敌人正常格挡／无敌等原生判定仍保留。
  当前现场原生 pre/post：MC6→600（HP1000→400）、9→900（2800→1900）、
  11→1100（1300→200）。这些具体样本是弹射物命中，不能拿来声称某一把剑或斧头的实测值。
  近战、弓箭、MC生物采用各自MC命中数值；已转发的TNT原生爆炸仍拥有原生AoE伤害，避免重复。

证据 `logs/combat-scaling-audit-20261009/audit.json`，原始host与native-hit快照在同目录。
新增回归验证两种原生模板均保留不同整数及小数伤害；17组原生入队回归和7组倍率／回血隔离回归通过。
MC对特定生物类型附魔的适用性仍由代理实体的MC类型决定，并未在本轮建立鬼武者怪物的种族映射。
用户无需额外操作；游戏仍运行、接管关闭。

### 2026-10-09 吸魂与跨边界修正已通过用户验收

用户确认 C 吸魂正常；随后右键吸魂／原使用行为和原断联边界复测回复「ok」。
最后关闭 F10，原角色移动、操作、C 吸魂及松开停止的恢复检查也回复「ok」。
当前游戏和 MC 保持运行、接管关闭，无待回复问题；不要再次要求 Reset 或重启。

真正完成修复的是 generation4：generation3 的命令注入曾被错误的精确类型判断拒绝，
实际字段类型为 `ace.Bitset\`1<System.Int32>`，继承 `ace.Bitset`。
改用继承关系验证后，原生 normal/cancel 两组 48 位命令的原值写回／读回均通过，
ABSORB=14 才真正进入命令结果。只改 supporter 标志不足以启动吸魂。
原生范围资产已确认：基础水平20、垂直50、全向360°，不是范围缺失，未扩大范围。

现场记录25次原生成功、25次奖励入队，MC stdout 有对应 receipt1～25，包含回血、修理、
堆叠增加及经验四类。证据 `logs/soul-boundary-20261009/c-absorption-user-confirmed.json`、
`c-absorption-host-summary.json`、`rmb-boundary-user-confirmed-*.json` 与 `acceptance.json`。
成功总数是本会话累计，不能将其解释为右键单独新增25次；右键与边界视觉结果来自用户确认。
最后状态 enabled/active=false、command/held=false、原生模型及碰撞 ready=0，无脚本错误。

边界修正使用下节实测的 `Collidable.Enabled` 即时屏蔽，仅在本次同步地形查询期间排除
本 MOD 的方块碰撞体，返回前恢复；组件级 `Colliders.Enabled` 在同帧不生效，已弃用。
动态姿态 DLL/JAR 保持用户已确认不闪动的版本。本轮没有重启鬼武者或改写库存。
generation4 安装收据 `logs/soul-boundary-20261009/bitset-hotfix-installed.json`。
后续如有新场景边界失败，先读 query 的非三角形类型和 last_query_masked，勿取消覆盖范围保护。

### 2026-10-09 23:04 原生命令吸魂修正 + 碰撞体即时屏蔽，已安装待 C 测试

用户确认上一热修吸魂仍失败；抓取 held_frames551 / overwritten0 / success0，已排除输入被覆盖假设。
改接当前玩家的 `cPlayerCommandResult.mergeResult` 后置，写反射验证的 ABSORB=14 普通/取消命令位
和 `_IsSoulAbsorption`，只恢复自己改过的位，保留其他命令和原色奖励。入口已实时观察到数千次调用，
F10 关闭时没有注入和错误，实际 C 测试待用户回复。

边界原因进一步实证：组件 `Colliders.Enabled=false` 在同一查询内仍返回方块，
改为真正的 `Collidable.Enabled=false`。在已验证 physics_cube 上同帧四次原生区域查询：
before boxes1/triangles20 → component disabled boxes1/20 → collidable disabled boxes0/20 → restored boxes1/20。
证据 `logs/soul-boundary-20261009/native-collidable-mask-verified.json`。独立方块已 removed/destroyed，
探针已 disabled，查询保留所有场景三角形。线上排除仅针对本 MOD 实际持有且校验 owner 的碰撞体。
未知原生形状仍保守拒绝认证；没有去掉地形覆盖保护。

Codex 崩溃后 MC 和 worker 也退出，鬼武者 PID30324 仍在。退出后的原世界67文件已完整备份到
`runtime/test-backups/soul-command-hotfix-20261009-230120/world-after-codex-crash`，未修改物品/存档数据。
重新连接原世界：MC PID53520、worker84528，日志 `logs/live-soul-command-20261009.stdout.log`。
三份 Lua 热更 generation3，安装/备份收据 `logs/soul-boundary-20261009/command-hotfix-installed.json`。
command enum 新现场证据在同目录 `command-enum-metadata.json`。

已请求用户按 F10，打出魂后仅按 C 3秒，观察吸收及MC奖励，再回安全位置保持开启。
收到回复先读 onimusha_soul_status.json / MC stdout，再测右键、原边界。
无需重启、无需手动 Reset，用户已确认的动态闪动修复保持不变。

### 2026-10-09 22:36 热更新吸魂决策时序与 MC 碰撞查询排除，待测试

用户已确认动态位置闪动修复；吸魂无效，且边界外接管失效、返回恢复。
游戏 PID30324、MC43960、worker99724 继续运行原世界。用户已回安全位置并关闭 F10，
三份 Lua 热更成功（loader generation2），没有更换 DLL/JAR、没有重启或改动存档。

边界证据：原生地形刷新14次失败，原因 `Unsupported native area query primitive: boxes=5`，
现场 MC 原生碰撞方块 total=5，旧地形覆盖区之外触发 foot/body/support gate。
现通过 `onimusha_native_blocks.query_terrain()` 仅在同步地形查询期间临时禁用本 MOD 持有的碰撞组件，
查询返回前恢复全部原始 enabled 状态；异常也恢复，绝不将 MC 方块烘焙成拆除后仍存在的地形。
未知原生非三角形仍拒绝认证，不能为隐藏错误而去掉覆盖范围检查。
热更后 F10 关闭状态查询4753三角形、零非三角形、消费成功，无失败。
待验证开启接管、存在 MC 方块时查询也能排除这些碰撞；如仍失败，查看 last_query_masked 和 query.boxes。

吸魂新增 `updateAfterActionFromBoneEntity` 决策前再次写入当前 C／右键状态，
记录真实 held_frames、bone_injections、overwritten、原生 absorption_type/absorbing/request。
无需重新采集四种魂；只按真实成功回调发奖励。Lua 早期输入覆盖／恢复、碰撞屏蔽异常恢复、
完整地形消费与失败保留覆盖区等回归已通过。尚未宣称实际吸魂成功。

备份 `runtime/test-backups/soul-boundary-hotfix-20261009-223601`；
证据和安装收据 `logs/soul-boundary-20261009/`，三项部署 SHA 已更新。
已询问用户按 F10 后测试 C 和右键吸魂，再回安全位置保持接管，等待答复。
先读取 soul_status 和 MC stdout 奖励回执，再单独请求复测原来边界；不要让用户手动 Reset。

### 2026-10-09 晚：整帧同步与吸魂奖励候选，待游戏内验收

用户已确认上一版 TNT／像素清晰度／本地缓存三项均正常；新的问题是移动时动态物体位置闪烁。
已找到相机读最新 MC 状态而几何来自另一帧的差异，实现原子 RenPoseFrame + Lua 帧锁定。
用户已按要求退出鬼武者，MC 在 21:29:15 正常保存退出。不要直接重开旧的测试世界参数。

原角色四种魂都已采样，11 次成功吸收；用户指定保留原颜色奖励，额外抽取 MC 奖励，
XP 为一级进度 +23%。C 或右键均触发；详情见 ONIMUSHA-SOUL-AND-POSE.md。
新 onimusha_soul.lua 必须和更新的 loader、DLL、Fabric JAR 一起部署。
只读 soul 探针已停用，不能把探针记录当作实际 MC 吸魂验收。

原世界已备份到 `runtime/test-backups/pose-soul-20261009-213708`（66 文件，修改前）。
应用户要求背包格20已加钻石斧、耐久III；原格中的一组64附魔金苹果完整移到 EnderItems 格0。
收据 `logs/dynamic-sync-soul-20261009/diamond-axe.json`。
新版现已安装，81 项部署文件 SHA256 一致。DLL
`EB5BD91AA965C3C493013FEFC5DF5EC144606C34FBAB1A991D59D5E7E15D585F`；JAR
`DB7087614D5440D70535A96EC10919003D4B3C1C87D494884E721A2C85E6A30E`。
收据 `logs/dynamic-sync-soul-20261009/installed.json`，接管关闭，原世界启动参数已恢复。
已请求用户启动鬼武者进入场景，先不要 F10；收到回复后连接 MC 原世界。

真实独立 MC 测试：1,618 个锁定姿态帧、943 帧第一人称／676 帧第三人称，移动约5米，混帧0、协议错误0；
60 个奖励及其重复副本只执行60次，回血10、修理5、堆叠4、XP41，保存后斧头损伤0、圆石64、经验9级43%。
C／右键的持续与松开均捕获，错误世界回执被拒绝。证据 `isolated/verified.json`。
TNT 回归：受击38帧、TNT158帧（白79／普通79）、scale1→1.17345、错误0；引线起播及 fuse10时active=true。
三个 native CTest、Fabric build和 Lua 生命周期检查通过。
上述独立测试不代替鬼武者移动抖动和原生吸魂动作的实际验收，下一步仍需用户测试。

### 2026-10-09 02:00 TNT／像素边缘／持久缓存修正版已安装，游戏均关闭

用户睡觉并明确要求处理完关闭游戏。通过 Alt+F4 正常关闭鬼武者；MC于01:50:57记录
宿主退出、Saving players/worlds/chunks，旧worker退出。65文件原世界备份且SHA逐一核对：
`runtime/test-backups/tnt-pixel-cache-20261009-0153`，含旧DLL/JAR/Lua/manifest/launch args。

真实独立MC世界 `OnimushaMC-TNT-Pixel-20261009` 已执行并保存退出：
38帧受击、158帧TNT，其中78帧white、80帧plain，scale1→1.16107，消息错误0。
新Mixin正常加载，引线audio start=STARTED，fuse=10时active=true，爆炸后stop。
该证据不代替鬼武者本身的视觉/听觉验收。3项native CTest均实际通过、无跳过。
证据 `logs/tnt-pixel-20261009/animation-smoke/result.json` 和 `logs/tnt-pixel-animation-20261009.stdout.log`。

新版DLL/JAR/native_models Lua已安装，79项部署文件核对一致；原世界65文件在独立测试后SHA未变。
恢复原世界启动参数，未留下测试进程。安装收据 `logs/tnt-pixel-20261009/installed.json`。
当前指纹：DLL AF35EF3301A5724C41BA57CAB616C89F9F3A3158FF1C344A15A23FEA618AE77C；
JAR B5AEDA8E97EEF4B07AD3F1A516B6C014254A402BD26B3E1B13653475E9B12EEA；
models Lua FCF9E3DF114847D64EA1264C2853BE9715B55A118D211D1FAF63611526ACF920。
候选归档 `build/candidates/tnt-pixel-cache-20261009`。
已经将30组实际捕获、回读通过的用例（29个唯一缓存条目）写入生产本地缓存，含几何/材质/TEX及构建验证报告，
收据 `logs/tnt-pixel-20261009/primed-cache.json`；没有修改游戏原生资产或原存档。

明天：用户启动鬼武者进场景后，连接原世界并启动新版worker，确认cache_hit/初始化无异常；
再复测①圆石、梯子和人物像素边缘及帧率②TNT第一次/第二次闪白、最后半秒膨胀及引线声。
全部游戏现已关闭，不应在用户睡觉期间重新打开原世界。没有待回复问题。

#### 本轮实现与离线检查记录

用户恢复任务并要求修复原生过滤导致的模糊，随后要求将已转换方块存到 MOD 本地目录供后续直接使用。
当前游戏 PID107640、MC120964、旧 worker96892 仍运行，接管关闭。独立 render_userdata 探针已 removed/destroyed，
native_object_probe 和 combat_inventory 控制 disabled，两个控制的部署指纹已更新。原存档没有改动。

候选源码及构建：
- 动态顶点 bit21 独立携带白闪，保留外观模型和稳定面 ID。Lua 预加载白色 MDF，再切缓存材质；
  不反复创建或重绑 Mesh。仍需鬼武者现场验证 material swap 无闪回/崩溃。
- 更新变换改为先 LocalScale 后世界位置/旋转，并保留 WorldAABB 诊断。膨胀画面未验收；不宣称已修好。
- Fabric TntFuseAudio 用跟随 PrimedTnt 的位置音效持续到引线结束；独立于绘制回执，最多32个。
  只替换附近对应 PrimedTnt 的一次播放，不吞掉矿车或其他使用同音效的对象。待隔离MC实际启动验证 Mixin 和声音起止。
- 转换器沿原贴图色块划分三角形，并收缩每块采样 UV 到同色区域内部，保留4倍最近邻扩图。
  不改全游戏过滤；会增加每个模型的三角形数，但不增加实例对象数。实际方块237～3066三角形。
  34个实际捕获用例含4个既有透明/退化UV回退；30组资源导出与回读通过，面积误差<1e-5。
  首次实际转换约0.22～0.46秒/外观；游戏画面清晰度及帧率尚待验收。
- `native_model_cache.py` 持久索引在 `assets/native-models/live/cache-v2/`，资源仍存同级 section_*。
  key含源几何、贴图、动画范围、白闪变体、转换代码/模板/写入器/Blender版本，不含PID/模型ID/世界ID。
  命中跳过 convert_model 和 build，校验MESH/MDF/TEX指纹后直接发布本次会话的新回执。
  旧模糊资源不当作新版缓存。异常/缺失索引为未命中；已加载不可变资源不原地覆盖。

验证：Fabric build/test通过；native及真实D3D12 WARP绘制测试通过（含白闪像素读回）；
5项Lua共享资源/稳定ID/预载/白闪切材质回归通过；像素过滤、白闪形状、缓存、worker IO单测通过。
真实Blender worker在完全隔离fixture目录跑两次进程：更换PID/世界/模型ID后仍命中同资源；
首次0.553秒，重启命中0.114秒，证据 `logs/tnt-pixel-20261009/cache-worker-test/014150/result.json`。
不是 RE 游戏内加载耗时或视觉验收。生产 worker 尚未重启。

上述停止/备份/隔离测试/安装流程已经执行，结果见本节顶部。鬼武者视觉复测尚未执行。


### 2026-10-09 TNT 仍未通过；用户 Escape 停止电脑操作

用户确认两次活动 TNT 切原生后，闪白及临爆前膨胀均看不到。声音进一步澄清：爆炸声有，
引线嘶嘶声只在 MC 绘制期间听到，切原生即消失。不要写成所有声音均没有。
两次记录 `tnt-still-frozen-user.json` 的实际 Transform scale 达 1.18155/1.16108；
原生爆炸 shell 两次成功。这不能替代画面验收。

本地 26.3 TntRenderer 字节码确认只在最后 10 ticks 膨胀，白闪每 5 ticks 切换。
原版 entity.tnt.primed 调用一次 playSound；当前 assets 的 random/fuse.ogg 长 2.830771 秒。
没有找到原生绘制切换停止 Java 声音的逻辑，但尚未采集实时声音起止，不可下结论声音正常。
确定遗漏：AvatarExporter 将白闪只转换为 fullbright light，DynamicModels canonical face 又将
light 清零。因此原生白闪丢失；尚未修复。不要用每次闪白新建/重绑 Mesh 的办法修复。

用户安全关闭 F10 后，已热更新可选 WorldAABB 读回（失败仅记录，不影响绘制）。
独立 USER3 显示探针新增 replay_scale/offset/flash_probe 控制；flash_probe 未开启且未验证，
不可接入生产。临时面按 1/1.3 倍各停留 180 帧，用于视觉检查，不产生爆炸或改 MC 存档。
`tnt-scale-replay-before-stop.json` 保存实际 scale=1.3 及 WorldAABB 尺寸 1.3 的记录。
电脑操作工具已成功找到鬼武者窗口，但随后用户物理 Escape 停止操作，未取得两尺寸画面对照。
已发送 remove 并关闭独立探针；无新增 DLL/JAR，角色切物品和铁傀儡受击的已通过修正保留。
Lua 换序和 USER3 生命周期回归通过。备份 `runtime/test-backups/tnt-draw-audit-20261009`。
下一步仍为真实 TNT 渲染/闪白和声音时间对齐，不能提前报已修好。

### 2026-10-09 道具切换与铁傀儡受击连续性已实景通过

用户对新DLL的两项测试回复“都OK”：第三人称切换道具时身体不再瞬间回退，铁傀儡受击
保留红闪且不再逐部件重新加载。`switch-hurt-user-passed.json`保留当时状态。
当前原世界已连接并接管开启；正在请求两次TNT引爆，分别观察临爆前最后半秒膨胀，
并读取native_sections.dynamic_scale_samples。TNT缩放问题不能提前记为通过。
本次游戏日志00:04:04有已有相机诊断getActiveCameraParam调用异常记录，游戏仍运行、
相机接管正常；它不是Mesh.setMesh绑定异常，不得笼统声称整个REF日志无错误。


### 2026-10-09 00:00 稳定部件编号/受击实例颜色已安装，等待重新进场景

用户进一步确认：第一人称手持物、铁傀儡受鬼武者光照正常；切换道具缓存生效，不再逐个恢复。
仍有问题：切换瞬间身体闪回MC一次，新道具约1秒等待；铁傀儡受击后整体回退并逐个恢复；
活动TNT切换原生后用户观察到缩放停止。不要把这些问题标成全部通过。

用户已退出游戏，MC日志23:50:59确认保存退出；原世界65文件哈希备份在
`runtime/test-backups/dynamic-identity-tint-20261008-235156`。DLL/JAR Lua实验前版本均保留。
隔离MC世界`OnimushaMC-Animation-20261008`完成后亦已保存退出，不改原存档。

候选修改：
- DLL为动态面分配不复用的稳定ID；列表换序保留相同外观实例ID，原有绘制回执继续有效。
  Lua回执遇到已经消失的旧道具，只忽略该面；不会拒收整个人物。150ms租期不延长。
- 均匀顶点颜色从纹理身份拆为实例BaseColor，受击红闪不再创建一套贴图和Mesh。
  材质颜色以线性值写入当前私有Mesh；非均匀顶点颜色仍保留原模型处理。
- Lua兼容旧DLL的偏移回执，新DLL使用stable_faces/id；动态结果检查从15帧缩为3帧，
  每帧最多8个结果读取，仍最多2个新动态对象，不提高分配上限。
- 新增有界缩放回读（场景中类似单位立方体且缩放变化时，最多1面/帧、最后32条）。
  TNT问题未复现于隔离源几何，不能声称已确定修好；下次实际游戏引爆后检查此记录。

验证：3项native CTest全部通过（DLL API在原游戏退出后实际执行，无跳过），Lua动态、换序、
红闪复原、预加载/上限、方块共享/加载以及独立USER3探针回归通过。
独立原生模型get/setMaterialFloat4回读正确；静止位置/旋转时scale和WorldAABB也随变化。
**材质实例互不影响的双对象检查尚待下次游戏启动**，探针已准备但启动控制关闭。
隔离真实MC捕获37帧受击变色、158帧TNT，临爆几何由1.0增至1.17345，消息错误0；
证据`logs/native-dynamic-engine-loader-20261008/animation-smoke`。该结果不等于鬼武者视觉验收。

已安装DLL E6E8434E09B2E2905172F216322B7F4CD013598C6943541AE7C79E10C473449C，
models Lua 0752CDC70114B380C4D2ABB906E0CF513979B89C18B99F9EEDF5B601CCECDBF6，
probe Lua B6869B8D687CB40C4F7925D1F8F0A1F6F31B60E7BF69428162F0D4026D569B5E。
JAR不变，协议15；部署79项无差异。运行配置F10关闭，动态三个流启用，独立探针disabled。

用户已正常进场景（PID107640）。私有双模型检查已通过：一个实例红色1/.55/.55，
共用同一MDF的另一个仍1/1/1，material_isolation.isolated=true；两个对象均撤除。
日志material-isolation-live/removed。原MC世界已启动（Java120964、worker96892），接管仍关闭。
需要复测：道具切换瞬间身体连续性、铁傀儡受击红闪/光照连续性、TNT临爆前缩放及scale回读。


### 23点后 动态原生绘制恢复及道具切换复用候选

本节取代下面动态硬关闭的停点。引擎 USER3 加载路径已用于动态面；先完成独立面419次
移动/旋转/缩放及撤除，再预加载226个玩家面和48个场景面。用户已确认第三人称角色与
身上道具的鬼武者光照、动作正确；用户同时发现切换手持道具导致逐个恢复光照。

已修正动态实例身份：顶点列表偏移不是稳定身份，保留偏移与外观均相同的对象，再按
同一流/同一外观复用移位的对象；只销毁真实消失的部件。偏移整体移动及循环交换的
回归通过。用户确认安全后已自动关闭接管并热更新，generation6 loaded。
目前正在实测此修正及第一人称；不能把它们、NPC或活动TNT的画面结果预先记为通过。

运行控制 `reframework/data/onimusha_native_dynamic_control.json`：enabled=true、
preload_only=false、hands/avatar/scene均true、max_instances=768、per_frame=2。
没有控制文件时动态默认关闭；最多2个新动态对象/帧，共768个，所有Lua原生对象总上限2560。
每组件只绑定一次，保留依赖直到延迟销毁完成；不允许恢复直接holder创建、定时重绑或组件重建。
第一人称须整组完整且回执接受后才隐藏MC层；单外观失败仅回退对应部分。

日志：`logs/native-dynamic-engine-loader-20261008/`。本轮原存档未编辑，DLL/JAR未改。
安装清单新增动态控制文件，目前79项。第一次动态预载曾出现一条worker.json读取EOF并恢复，
没有新增Mesh.setMesh异常；不要写成所有日志绝对无错误。
最新快照after-reorder-await-user：11/11方块、156/156手持面、48/48场景面加载就绪，
dynamic_reused=1362，资源错误为空。此快照说明接口就绪，不能替代用户视觉确认。


### 22:49 方块光照、放拆、约30米显示与 F10 恢复实景通过

用户追加确认：放置/拆除时其他方块不再全体闪回，约30米仍保持鬼武者光照；
随后 F10 关闭，原角色和操作恢复正常。`userdata-live-success/restored-f10-off.json`：
active=false，显示对象创建229/移除229，owned_total=0、warm_retiring=0，
碰撞count=0/retiring=0，无资源错误。当前游戏/MC/worker仍运行，接管已关闭。
78项部署哈希仍一致。无需再让用户重复本轮方块测试。

下一项为玩家、手持物、NPC、活动TNT的原生绘制；当前开关仍false。
先以已通过的引擎依赖加载方式做少量动态资源/实例验证与数量控制，
不要恢复直接 create_resource/create_holder 或定时重绑，不要一次开启大量动态面。
本轮成功只覆盖上述方块场景，不能宣称动态实体、所有模型或长时间稳定性已验证。

### 22:45 接管中的方块首次光照结果

用户确认：方块正常，新创建方块响应鬼武者光照的时间明显缩短。
实景记录 `logs/native-lighting-crash-20261008-211723/userdata-live-success/`：
11/11 方块就绪、6 种外观加载完成、无资源错误/等待项、11 个存活对象、无延迟销毁积压。
热更新后 REF 日志没有新增 error 或 setMesh 异常。下述候选的首次接管加载已通过，
放拆、约30米与退出接管的后续验收见22:49记录；长时间稳定性仍需区别记录。

### 22:39 引擎依赖加载候选热更新记录

**本节取代以下旧停点，禁止恢复定时 holder 重绑或隐藏组件重建。**
用户确认恢复版仍会十几秒后只有部分方块受光，新增方块让全部方块恢复 MC 效果。
21:40:04 日志再次捕获 `Mesh.setMesh` 原生访问异常；用户随后安全关闭 F10，原角色正常。
先关闭自动原生绘制并保存现场，再完成下述单对象对照，没有再要求用户反复放方块。

证据：`logs/native-lighting-crash-20261008-211723/` 中 recovery-block-exception、
mesh-binding-disassembly、resource-refcount-disassembly、global-holder-probe。
异常指令位于资源 add_ref 的 `lock inc [rcx+0x28]`；rcx 为模块 vtable 地址，
setMesh 从 holder+0x10 获取了不适合作为资源对象的指针。确切失效生命周期仍未证明；
不得声称仅靠引用计数或更换 create_holder_global 已解决。
`create_holder_global` 对照：新 Mesh/MDF 首次超时，同资源第二次才就绪。

新路径由引擎反序列化私有 USER3 的 `_Mesh` / `_Material` 依赖。
根类型 `app.montage.data.MontagePartsModelData` 仅作为数据容器；未挂接玩家、未调用换装逻辑，
其他字段为空。4 个全新资源 ID 首次加载成功，后三个从请求到就绪分别约 1.010、0.102、1.112 秒，
每次撤除均确认 destroyed，无新增 setMesh 异常。这是单立方体试验，不是所有模型/大批量稳定性保证。
首个样本 `section_c8a249840581409cab79`；其余结果见
`global-holder-probe/userdata-cold-series/summary.json`。

自动转换接入内容：
- `NativeModelLoader` 用 REE-Lib 生成并回读 896 字节 USER3 模板。Python 只替换等长 ID，
  输出与 4 份独立 C# 生成文件逐字节相同，不需每个模型启动子进程。
- worker 为新旧转换资源都发布 `_loader.user.3`，结果新增 `loader_version=1`。
  旧资源只补依赖文件和回执，不改写已缓存的 Mesh/MDF/TEX。
- Lua 等待引擎生成的两个 holder 后才创建隐藏 Mesh；每组件仅绑定一次，取消定时重绑和超时重建。
  保留 USER3 / holder 直到对应显示对象与延迟销毁对象释放。
- 单类型加载/绑定失败仅让该类型保留 MC 绘制，已有成功方块的回执不清空。
- 动态原生绘制仍硬关闭；不能把人物、手持物、NPC、活动 TNT 说成已修复。

当前游戏 PID82956，MC PID101676，worker PID114264；原世界不变，存档本轮未编辑。
已安装备份 `runtime/test-backups/engine-resource-loader-20261008-223922`；78 项部署哈希一致。
models Lua `BACD3FA942E2B1812B7ACBF4076CD685B4DF92AE8375445E1207C85DD2CD7EC7`；
combat probe Lua `91EEF74425983E31393C73CA8CD18B71213EAB6FAD18F4F41D12D022581E041F`。
DLL/JAR 未改。热更新 generation4 已 loaded；接管关闭，自动方块绘制配置恢复 true，独立探针关闭并已撤除。
worker 当前 4 个既有转换回执均升级成功；额外 4 个真实模型输入的 Blender 转换/文件哈希检查通过。

定向检查：共享资源与恢复、加载并发/暂停、单次绑定、单类失败隔离、动态禁用、动态离线模拟、
独立物理/显示探针及 USER3 探针通过；模板与 worker IO 单元测试通过。
这些与单方块实景记录是不同证据，不能替代下一步的接管实测。

首次 F10 测试用户已通过，详见上面的22:45状态。
无需重启或手动 Reset。不要自行开启接管，不要重新启用动态面批量绘制。

### 21:32 崩溃后隔离动态原生绘制，已安装恢复候选，等待启动

**本节取代以下旧停点。不要再次部署 21:16 的组件重建版本。**
用户反馈最后一版 F10 后严重卡顿，方块稍后恢复原生光照，角色仍是 MC 绘制，随后游戏崩溃。
21:17:23 REFramework 记录 `via.render.Mesh.setMesh` 调用异常，随即出现 `c0000005` 原生访问异常。
这把排查范围缩到资源绑定/重建路径，但不能仅凭最近 TDB 符号确定底层失效对象。
没有证据支持把问题归因于模型计算预算或用户操作。

证据完整保存在 `G:/Onimusha_MC_mod/logs/native-lighting-crash-20261008-211723/`：
原始 dump、完整 REF 日志、MC 日志、崩溃脚本、配置、部署清单和 recovery-install.json。
MC 日志 21:17:29 记录宿主关闭后保存玩家/世界并退出。游戏、MC、转换器均已退出。
当前世界 65 文件逐项哈希备份到 `runtime/test-backups/native-lighting-crash-20261008-211723`；未回滚或改写存档。

恢复内容：
- 以 `runtime/test-backups/native-component-refresh-20261008-211620/onimusha_native_models.lua`
  为基线恢复 **同组件重新绑定 holder**。这一基线曾得到用户方块光照正常的确认。
- 撤回 30 帧后销毁并重建隐藏组件的实验；当前候选并非重启后的实景稳定性已通过。
- 生产源码 `DYNAMIC_NATIVE_ENABLED=false`：玩家、装备、手持物、NPC、活动 TNT
  全部保留 MC 绘制，不请求动态面转换、不发送动态抑制回执。不要把此状态误报成动态光照已修复。
- 128 米显示/最近 1280 方块、方块编辑保留掩码与转换器写入修复仍保留；远处/编辑实景验证仍待完成。
- DLL/JAR 未更换，协议仍15。安装 Lua SHA256：`3E2E086724CF7E5F3E872C71C467D09275EB33A9E457D3025CD14FAB4D1851E5`。
  78/78 部署哈希一致，接管配置 `enabled=false`，所有实验探针维持关闭。

5 个定向 Lua 回归脚本通过：模型共享/清理、加载上限与暂停、同组件 rebind、动态隔离、
动态代码的离线 mock 回归（最后一项明确只在测试内打开开关）。这些不是原生引擎生命周期验证。
之前 mock 也通过但游戏仍崩溃；不得再用 mock 结果替代游戏验收。

当前已提问：启动鬼武者进入场景，保持 F10 关闭。收到用户确认后连接原 MC 世界及唯一转换器，
先检查 native_sections.dynamic_enabled=false，再只测方块与接管恢复；本轮不要求角色/TNT光照测试。
后续动态方案必须减少逐面资源/GO，先在孤立场景验证资源引用和延迟销毁，再考虑批量实体绘制；
不要简单重新打开开关或批量重建所有 warmer。通用战斗、爆炸伤害、原生完整方块碰撞不因绘制隔离而关闭。


### 20:41 原生显示范围／方块编辑闪回修正版已安装，等待启动

本节替代旧的当前状态。用户已安全关闭接管并退出；游戏、MC、旧转换器均已退出。
已请用户启动鬼武者进入场景、暂不 F10，待回复后连接原世界与新版转换器。
原世界 `OnimushaMC-XYZ-v2` 未修改，65 文件完整备份在
`runtime/test-backups/native-lighting-repair-20261008-204039`。
78/78 部署哈希已核对；探针保持 disabled。安装回执 `logs/native-lighting-repair-20261008/install.json`。
DLL `C7B7A300E52D9C0E28AA7D0622498D4A041F79BFE62B5402B58815D57631B014`；
models Lua `121BCF520DD1E06DFA443D334707261E557B4A975053A31125FAD1A000034D68`；JAR 未改变，protocol15。

用户此前已确认自动转换的方块光照生效、手持物光照生效，但存在：超过约16m回退、放拆瞬间全部回退、F5身体仍MC效果。
本版将显示扩大128m/最近1280实例，显示GO不再依附16m碰撞GO；区域网格重建时按位置+外观保留未改变实例的抑制掩码，旧租期不延长。
资源预载隐藏绘制但启用组件，最多8个同时加载，暂停/后台时间不计超时，最多3次尝试；dynamic_streams分别记录avatar/scene/hands的desired/ready/errors。
身体加载问题仍需实景确认，不能宣称已修复。原生点光源、近镜头淡化（此前hook调用0）也仍待实景验收。

转换器最初死亡原因已确认：Windows JSON读者短暂占用导致os.replace抛PermissionError；现加入有界重试、结果待发布队列、恢复已完成回执。
新方块请求优先于实体面积压，每4个任务重新检查队列，取消每任务扫描整个磁盘资源缓存。
修正版：3/3原生CTest（含真实D3D12/WARP、退出游戏后DLL API）、30个Lua回归脚本、3个worker IO测试通过。
真实后台转换器4任务到MESH/MDF/TEX写入及哈希回读通过；宿主结束后自动退出。
下一轮只测：约30m外方块、连续放拆已有类型是否整片闪回、F5身体/装备；读取dynamic_streams与resource_errors。


### 19:53 当前运行：protocol 15 已连接，等待自动方块转换实景测试

用户已启动并进入场景。游戏 PID46412，MC PID111780，转换器 Blender PID122116，原世界 OnimushaMC-XYZ-v2。
相机、地形、host_ready、connected 均 true；F10 关闭，3 sections / 4 textures，invalid/rejected=0，error为空。
worker ready，mode=automatic_models。首次连接证据 `logs/live-automatic-models-20261008/connected-f10-off.json`。
已请用户 F10 开启，在安全处放置石头、南瓜、梯子，初次等待约30秒后观察纹理/光照/遮挡/镂空，保持开启后回复。
收到回复立即读取 native_sections 与 worker/result，勿重启或 Reset；此版仍未获得实景通过结论。
下一轮再测试第一人称手持物/F5动态角色、火把原生照明及近镜头半透明抑制。

### 11:47 当前安装：protocol 15 自动外观转换，待启动游戏验收

本节取代下面所有“当前 PID / protocol14 / 未实现”描述。旧内容保留为历史，不要依照旧停点启动或部署。
游戏、MC 和测试 Blender 均已退出；已请用户启动鬼武者进场景并保持 F10 关闭，等待回复。
收到正常进场景答复后读取状态、连接原 MC 世界和转换器，不重复询问同一步。DLL/JAR/Lua 已配套安装，接管默认关闭。
详细范围、边界和回退见 [自动模型转换候选](ONIMUSHA-AUTOMATIC-MODELS.md)。

完成自动完整模型缓存、镂空几何、实际玩家/手持物/NPC 变换、原生点光源候选、聊天、接触碰撞和
近镜头淡化抑制候选。护甲走真实 MC 伤害链，隔离实测通过。背包附魔及补满已经写入，勿重复写存档。
Java 70 项、3/3 CTest、29 个 Lua 脚本及真实 MC/后台转换器隔离测试通过；第一人称切换额外回归通过。
这些新功能尚未经过鬼武者实景验收，尤其动态姿态/FOV、原生光源、半透明抑制和性能。
火/岩浆动画表面仍回退 MC，原生点光源已接代码；不要误称完整原生自发光表面。

部署 78 项已核对；备份 `runtime/test-backups/before-automatic-models-20261008-114743`，65 文件存档逐项哈希一致。
回执 `logs/automatic-models-20261008/install.json`：

- DLL `F052FAAA5ABFF0F34655AB78FF9CF8F078ED1E73CDE9A773AE25EB9AF01132AD`
- JAR `492C2AA16036A2098252300B5DC1D8AA528E160851C6B0C4F85D834654C2DA37`
- models Lua `FB0284F7525F3815ABE0B3CA6A65FA3FF70CDD69D222DC7F1B406405501D833A`

下一步请用户启动鬼武者进场景，暂不 F10；先检查新协议和脚本，再通过 MC-launch-dev.ps1 连接原世界。
启动器已经自动启动原生模型转换器，无需另开第二个 Blender。F10 测试优先此前未支持的南瓜/梯子，
随后第一人称剑盾、F5 玩家/铁傀儡、火把照明和退出清理。不要再要求重复手动 Reset Scripts。
之前导航崩溃路径仍停用；偶发跨区闪断按用户要求暂缓，处决与进一步伤害平衡仍为独立未完成研究。

## 早期检查点（历史记录）

### 最新实测：铁块、圆石、TNT原生绘制通过；通用方块尚未实现

用户确认预加载版“铁方块、圆石、TNT正常了，南瓜、梯子还是MC的效果”，并问是否逐个适配。
已明确答复当前是16种白名单；南瓜/梯子未接原生绘制。通用方案应自动读取MC烘焙模型/贴图/状态，
按类型+状态缓存RE资源，同外观只转换一次、放置复用，处理方向/薄片/cutout，不能不断手工加白名单。
**这一通用方案尚未实现，也未声称完成。** 首次新模型转换延迟、非整块的所有权/碰撞均需独立处理。

游戏81132与MC107592仍运行，F10接管保持开启，无待回复操作问题。
状态 `native_sections`: synchronized，8/8实例ready，3种资源ready，无loading/error/临时预载GO残留；
原生碰撞9/9ready（原生绘制与碰撞支持集合不同）。证据
`logs/live-native-sections-20261008/user-three-kinds-pass.json`。
当前是protocol14，已安装JAR E3466C4E...与Lua B832F0BF...，完整哈希见下面检查点。
暂未实测此版F10关闭清理/冷启动16种/1280性能，不要要求再做无关攻击等旧测试。

### 02:32最新：圆石用户实景通过，其他种类冷加载修正待验收

编号修正后仍有Cube resource timeout；记录显示铁块MeshReady/MaterialReady=false、材质数0，
但所属碰撞对象Update=true。用已验证单对象探针对同一圆石资源独立加载成功，
保存证据 `logs/live-native-sections-20261008/prebuilt-cobble-standalone-ready.json`，随后撤掉探针。
按验证过的DrawSelf初始化顺序再次试验后，用户确认“圆石方块能正常接鬼武者光照，但其他没有”。
当时圆石资源已经驻留，其他冷资源仍超时；不能把这一轮称为全部通过。

新增**每种类一个隐藏预加载对象**，沿用成功单对象路径等待Mesh/MaterialReady，再把共用holder交给
现有碰撞对象。最多每帧新建2个预加载器、总种类16；资源就绪后立即销毁预加载GO并等延迟销毁。
这不是逐方块建第二套GO，也不实时转换文件。某个种类预加载失败不再撤掉其他已就绪种类。
回归覆盖冷种类超时隔离/隐藏对象回收/共享holder/1280实例/重载，已通过。

当前Lua `B832F0BFFEA6B6E6EC9D3610EF57ADD5DC8156F749F65B2747F632E29CD0C7D3`；
备份 `runtime/test-backups/native-instance-preload-20261008-023148`。
loader generation6 / id `22d683df4a6048f084fb84ec88bccd84` loaded。
游戏81132、MC107592持续运行，F10因重载关闭，探针control enabled=false。
最新已请用户“按F10开启，观察已有铁块等方块是否开始接原生光照，保持开启”；等待答复。
回复后立即检查 native_sections.resources_ready/resources_loading/resource_errors、ready/count/desired
及prefab_blocks。仍未确认16种/冷启动/拆除/F10清理和性能，勿宣称全部完成。

### 02:13追加：实景发现Lua资源编号格式问题，已热修，等待开启接管读取

用户第一轮反馈“贴图对，但遮挡不正确且完全没有原生光照”。实际status明确显示
`Missing cube kind 2.0`，不是本方案光照通过；Lua收到DLL的浮点编号2.0，用tostring查找JSON键"2"失败。
现在先用math.tointeger验证/规范化资源编号，沿用原碰撞坐标和生命周期；回归已加入浮点/整数混合编号。
只更新 `onimusha_native_instances.lua`，安装哈希
`3C85ED589E5CE007C87372592E80F4AB53930A11D06B050A9751992614782D55`，77项部署核对通过。
备份 `runtime/test-backups/before-cube-integer-fix-20261008-0210`。
自动重载generation3，id `1fc5dc0604f240c386aeca12144d11c1`，phase=loaded。
游戏81132和MC107592均保持运行。最新问用户：按F10开启并保持，先不用放方块；
收到回复立即读native_sections/prefab_blocks，确认原生模型ready>0且error为空再进行目视验收。

### 02:06当前状态：MC已连接，预制资源识别修正，等待少量方块实景结果

用户已启动鬼武者，PID81132自01:53持续运行。MC首次PID88040正常连接，但发现默认Fabric
把每个模块列成独立资源包，旧的vanilla/fabric名称白名单导致 `prebuilt cube resources=false`。
已改成检查实际minecraft命名空间的方块贴图、模型、blockstates、atlas资源来源；Fabric仅列出
资源包但没有覆盖这些资产时不阻止原生绘制，实际自定义资产仍保留MC绘制。
新增4项回归，Java共67项通过，JAR重新编译安装。

通过本项目JDK Attach维护工具 `onimusha/tools/java/MinecraftSaveAndQuit.java` 在MC渲染线程调用
正常 `Minecraft.stop()`；日志确认保存玩家/世界/区块并退出。没有结束鬼武者，没有强杀Java。
重启前65个存档文件逐项哈希备份，路径
`runtime/test-backups/before-pack-source-fix-20261008-0204`，未编辑存档/背包。
新JAR SHA256 `E3466C4EA12B78ED54486AB8147C8CE05BEFD57142560EE79B572A44626DB571`；DLL/Lua/77项游戏部署不变。

当前MC PID107592，世界 `OnimushaMC-XYZ-v2`，日志前缀 `live-native-instances-packfix-20261008`。
日志确认四类资产来源均vanilla，`Onimusha prebuilt cube resources: true`。
protocol14、connected/camera_ready/collision_ready/host_ready均true，render_invalid/rejected均0，error为空。
F10关闭，所以native.ready/renderer_ready=false、native_sections.phase=disabled是预期状态。
已向用户询问：开启F10，少量连续放置石头/铁块，观察纹理、场景光照、遮挡、延迟/闪烁，
随后保持开启供读取。**等待这一轮结果；不要重复启动MC或要求Reset Scripts。**
证据 `logs/live-native-sections-20261008/connected-packfix-status.json`。

以下01:43为部署历史，里面“当前未运行/等待重启”已经被本节取代。

### 01:43当前安装：预制方块实例原生绘制，protocol14，等待重启验收

用户要求接管时实际放置方块受鬼武者光照/遮挡，并指出合并模型转换0.45秒的交互延迟。
已改成**预制16种常用方块资源、复用原生碰撞GameObject**，放置时无文件转换；合并模块保留但不加载。
详情和支持范围见 [原生方块绘制](ONIMUSHA-NATIVE-BLOCK-RENDERING.md)。
已更换DLL、Fabric JAR、loader/main/native_blocks和新增第六payload `onimusha_native_instances.lua`。
`enable_native_section_rendering=true` 实际委托预制实例模块。源 `onimusha_native_sections.lua` 是停用实验，
不要同时加载它。原生碰撞1280上限保留，导航与全部物体探针保持关闭。
27个Lua脚本、63项Java测试、3/3原生CTest以及10项转换输入测试通过；77项部署哈希验证。
65文件存档完整备份 `runtime/test-backups/before-native-sections-20261008-014343`，没有改动背包/世界。

之前游戏PID122276已于01:10关闭，MC PID18704自行保存退出。当前游戏/MC都未运行。
已询问用户“请启动鬼武者、进入场景、保持F10关闭”，**等待回复**。
回复后先读新status确认新DLL协议14与场景正常，再运行
`G:/Onimusha_MC_mod/tools/MC-launch-dev.ps1 -WorldName OnimushaMC-XYZ-v2 -LogPrefix live-native-instances-20261008 -StartHidden -QuitWithHost -SwordBlocking`。
这个启动器已撤掉自动启动Blender转换器的临时补丁。不需要启动worker。
MC启动日志应有 `Onimusha prebuilt cube resources: true`，否则检查selected packs，不要强制换掉用户贴图。
连接ready后再请用户F10、少量连续放置石头/铁块；观察 `native_sections.mode=prebuilt_instances`、
ready/count、source native receipt及资源加载错误。**尚未进行这版实际游戏测试，不能宣称已完成光照验收。**

以下00:30及更早均为历史；不要按历史PID、protocol13或旧指纹重新部署。

### 00:30新增结果：原生合并区块模型实景通过

1280完整方块碰撞同步已通过下面四项用户实测，并保存本地提交8d7915b。
随后离线实现REN_SECTION/REN_ATLAS→原生合并MESH/MDF/TEX工具，
用户确认五个石头/铁块的合并测试模型“显示、光照和遮挡均正常”。
它是协议格式的人工测试几何+真实MC贴图，**不是实时MC世界区块，实时原生绘制仍未接入**。
详见 [原生区块模型原型](ONIMUSHA-NATIVE-SECTION-PROTOTYPE.md)。

试验请求 merged-mc-section-20261008-b已就绪/实景通过/撤除，destroyed=true。
第一次a请求因游戏暂停、对象Update=false而加载超时；用户回到场景后同一文件成功。
源码探针已加入暂停等待与清理ready=false，回归通过且已热加载。
唯一loader最新generation3，id `63b819d4a29a442aa77ebcbdd3a4dfd6`，phase=loaded。
游戏PID122276、MC PID18704继续运行，F10关闭，没有待回复问题；物体探针enabled=false。
部署manifest现26项已核对。此阶段只更新combat_inventory payload并添加3个显示测试资源，
没有更换DLL/JAR，也没有更改MC存档。原生导航仍停用。

下一步：有界实时section/atlas捕获与后台转换、资源生命周期和精确版本回执后切换绘制。
禁止把当前离线Blender转换器逐帧调用；禁止提前隐藏原overlay或宣称全部MC内容已受原生光照。
日志/备份 `logs/native-section-20261008/`；生成资源 `assets/native-sections/`。

### 当前候选：1280 原生完整方块碰撞同步，protocol 13

已在单独石头方块验证原生显示/光照/遮挡、玩家和普通敌人阻挡、删除清理后，
实现 MC 完整立方体的碰撞同步。**用户已确认放置阻挡敌人、拆除恢复通行、TNT清除碰撞，以及F10关闭后原角色恢复且无残留碰撞。**
当前只实测少量方块；1280上限及分批创建有离线回归，尚未进行游戏内1280密集构建压力测试。
用户指定上限1280；半径16，最近优先，最多每帧创建2个、轮流检查16个，退休中的对象也计入上限。
非完整立方体（半砖/楼梯/栅栏等）暂不接入，不能强行用整块代替。MC整体仍为叠加渲染，导航停用。

Protocol13新增 REN_FULL_CUBES=12，32字节头带world/epoch/MC PID，512字节位图全量替换section。
DLL `snapshot_full_cubes` 返回最近方块快照与截断数量。拒绝旧会话、错误尺寸、错误位计数，
连接generation变化后须先收到MC清空栅栏；Lua关闭接管/换场景/重载时清除自有碰撞。
新第五个payload `onimusha_native_blocks.lua`，唯一autorun loader文件清单已更新。
`enable_prefab_block_colliders=true`；旧 `enable_native_block_colliders` 和全部物体探针仍false。
单位尺度只支持已实测1.0；无导航和新原生渲染组件。

2026-10-07 23:22关闭游戏PID84716；MC PID85296于23:22:57正常保存退出。
最新64文件完整世界/旧DLL/JAR/Lua/config/manifest备份：
`runtime/test-backups/before-prefab-collision-20261007-233153`。
候选部署收据 `logs/prefab-block-candidate-installation.json`，23个游戏文件哈希核对通过。
安装工具 `onimusha/tools/Install-PrefabBlockCandidate.py` 只用于此次旧指纹迁移，不可不检查就反复运行。
Fabric构建与JUnit通过，25个Lua回归通过（1280密集对象测试另有复测通过），3个原生CTest全部通过。
本轮已更换DLL/JAR/loader/main；不要使用下方历史protocol12指纹作为当前安装值。

新游戏PID122276、MC PID18704，原 `OnimushaMC-XYZ-v2` 世界，
日志 `logs/live-prefab-collision-20261007.stdout.log`；协议13、相机/地形/连接ready。
用户已通过放墙阻挡敌人→拆掉后恢复通行；读取时 count=ready=retiring=desired=0、phase=empty，render_invalid=0。
TNT测试用户回复“方块被炸掉，敌人能正常经过”；F10关闭测试用户回复“恢复正常，没有残留碰撞”。
最终状态 active=false、native.enabled=false、count=ready=retiring=desired=0、phase=disabled，render_invalid=0。
当前接管关闭，游戏和MC保持运行，没有待回复问题。对应证据保存在
`logs/remaining-engine-work-20261007/prefab-block-{place-break,tnt,f10-off}-user-*`。
不要重复发道具，不要重新引爆原游戏油桶，不要开启导航实验。
同PID的长时间MC停顿/心跳恢复后，generation变化会撤销方块缓存，需要MC重新发清空与快照；
该恢复分支尚未进行实时验收，不能声称任意断连都已无缝恢复。

### 历史记录：单方块实验与此前恢复

以下记录保留事故和测试顺序。协议、部署、进程及验收状态以上方最新结果为准。

动态地形用户已实测连续走上百米，只有一次闪断；用户明确要求暂不处理这一次，继续剩余工作。
不要重新展开该闪断排查。不要模拟键鼠输入，实际游戏操作由用户完成。

本轮原生石头单方块已由用户验证：MC贴图、光照、遮挡正确，阻挡原角色，删除后碰撞清除。
重启后用户另测普通敌人追逐，确认敌人被石头方块挡住；主动绕路尚未通过。
生产MC世界仍使用叠加绘制，原生方块同步尚未接入。
详见 [原生物体实验](ONIMUSHA-NATIVE-OBJECT-PROBE.md)。

**随后导航扩展实验触发闪退，现已撤下。重启后的基础场景与 MC 接管/恢复已由用户确认正常。**
22:21:44日志记录 AIMapEffector.hasEffectNodes 调用异常，紧接访问违规；
尚未区分调用、注册/清理、原生更新时序问题。不要只加pcall后再次尝试。
运行脚本已删除导航创建和 hasEffectNodes 调用，navigation_cube动作拒绝。
导航PFB/USER已撤到隔离日志；资源生成器仅保留 navigation-offline-only 离线复现。
不要部署导航生成物，不要启用旧native block collider全局开关或WorkRate实验。

游戏PID107512已退出；MC PID115140检测宿主退出后22:21:51正常保存退出。
当前64文件世界备份且SHA256核对：`runtime/test-backups/after-native-probe-20261007-222930`。
未手动改世界、道具或背包。世界仍为 OnimushaMC-XYZ-v2。
MC日志 `logs/live-dynamic-terrain-20261007.stdout.log`。
事故、源码隔离副本、dump、恢复收据均在 `logs/remaining-engine-work-20261007/`。
两个探针控制 enabled=false，22个部署文件哈希一致。
24个Lua回归通过；本轮DLL/JAR/主Lua/攻击脚本没有改动。

新游戏PID84716已进入场景；原MC世界已由开发启动器恢复，PID85296。
MC日志 `logs/live-native-probe-recovery-20261007.stdout.log`。
用户确认移动、视角、背包和F10关闭恢复均正常。连接、相机、地形均ready，无渲染协议拒绝。
用户到空地关闭接管后，physics-enemy-collision-20261007-a 已成功生成。
用户确认普通敌人被挡住。随后 remove-physics-enemy-collision-20261007-a 已回报 removed/destroyed=true。
控制文件已再次 disabled，当前没有测试物体、没有待回复问题。
日志目录保存 physics-enemy-collision-a 的 ready/user-pass/user-feedback/removed 证据。
下一步将原生碰撞创建/删除接入MC实际方块同步。导航仍隔离，不能自动加载。
导航继续离线排查，纯显示+Colliders创建路径已通过，可作为后续MC方块同步基础。
RENSOLIDS只有占用位，不能把半砖/楼梯/栅栏都变成满立方体；需要精确形状或明确支持范围。
MC角色原生材质/动画和处决也仍未完成。

项目唯一autorun为loader；不需手工Reset。旧进程请求`6031a4a3de464c1fa77eead8471ffb66`
曾因退出超时；新进程启动后已处理该请求，generation2、frame32、phase=loaded。
游戏目录中的payload为无导航版本，源码与部署指纹一致。
老稳定提交df92eb8及动态地形候选包保留，不能用原生实验覆盖稳定发行包。

## 历史记录：爆炸实现与道具

只读油桶探针成功记录两个 Gm019_000 连锁爆炸（32事件、无错误）。探针在 combat_inventory payload 内，
采样已停用；不要让用户重新采样。逻辑 ID 4 → fixed ID 6 →数组索引 4 → shl_g019_000_004 主 shell。
主 shell 自动创建伤害/效果子 shell；不能把 getShellPackage 的索引误当 fixed ID。
所有生产对象重新分配/通过当前拥有者解析，不重用采样指针或修改共享资源。

爆炸协议本轮未改变。flags bit7 表示原生爆炸能力；EV3 的 formId=事件ID、weapon=epoch、flags=1。
MC 在事件确实入队时抑制该次敌人代理爆炸伤害，避免与原生 AoE 重复；MC 保留自伤与方块破坏。
原生子 shell `_EnableSelfDamage=false`，以当前玩家为 owner。跨进程最终 ACK 尚未实现；不确定原生失败不重试。
爆炸占用尾段加入 loader busy 门控，所有新 hook 继续由唯一项目重载器管理。

测试道具已发放，不要再添加：TNT 3×64、末地水晶64、黑曜石64、打火石1、铁块4×64、雕刻南瓜2×64。
旧有金苹果4×64也已经发过。新增物品只占空格，原物品和其他 NBT 全部验证不变。
完整世界备份 runtime/test-backups/before-explosion-golem-20261007-181455（60文件），
收据 logs/explosion-golem-grant-20261007.json。

## 历史记录：此前部署

唯一项目 autorun：reframework/autorun/onimusha_loader.lua。
四个 payload 在 reframework/data/onimusha_mc/scripts/：main/enemy_hit/guard_probe/combat_inventory。
禁止重建旧同名 autorun。爆炸生产逻辑封装在 enemy_hit 末尾独立 scope，探针在 combat_inventory 末尾。
重载工具 G:/Onimusha_MC_mod/tools/Reload-OnimushaScripts.ps1 自动关闭接管、等待恢复和 native busy 清空。
当前进程是新启动；上个进程最后自动重载 gen11 / 302b3179577c4990a261936684539ebf。
DLL与主Lua本轮已更新，loader未改动，不需手工 Reset。

安装工厂开关 reframework/data/onimusha_explosion_control.json；日志 onimusha_explosion_status.json。
能力位没有就绪时 MC 保留原代理爆炸命中路线（HIT_EXPLOSION=16），不会假称原生生成成功。
fire bit=8（此前误4，4是sweep）已经修复。近战10米、projectile/fire/explosion/mob命中128米。
上一轮弓箭远距离修复仍未独立实测；用户转向爆炸任务，不要宣称已通过。

## 历史记录：此前验证与剩余范围

Fabric build 通过，61 个 Java 测试通过（含3个新增寻路测试）；23 个 Lua 回归脚本全部通过。
新增3个Java作用域测试覆盖嵌套爆炸、异常清理、未入队本地结算；Lua覆盖去重、旧会话/非法输入拒绝、
多个同时TNT、原生不确定结果不重试。真实 TNT/方块破坏已由用户确认。
末地水晶、密集连锁、自伤精确去重、换场景资源独立加载、铁傀儡站立/寻路/近处攻击已由用户确认通过；更远区域待本轮复测。

既有：MC普通/特殊两套全局攻击模板由当前玩家资产ID1/41解析，所有敌人共用，不要求逐敌/逐招采样。
RSC活动受击范围聚合AABB，默认BODY部位；不能称已完成逐部位、装甲弱点或所有Boss阶段。
3C、F5、背包、相机UI跟随、持续移动、F10恢复、方块站立/拆除、百分比HP与治疗已通过。
MC格挡无扣血并有声音已确认；红闪/击退/火花未逐项确认。

原生NPC对MC方块的碰撞/寻路、真实RE深度/光照、处决仍未实现；实验碰撞对象创建保持禁用。
致死奖励、破甲、特殊弹反与跨会话事务 ACK 尚未覆盖。当前 MC 仍用叠加渲染私有深度。

项目 G:/Onimusha_MC_mod/source/SkyCraft，分支 onimusha-bridge，fork LCPD15/SkyCraft-OnimushaMC，未推送。
源码、下载、编译和备份均在用户指定 MC 工作根；保存本地提交，禁止未经授权向外发送。

## 历史文件指纹（protocol12，不是当前部署）

- DLL: `D60C30148D0CBEE6B1727483500EC9AF1D366C15C3E3170AF5CFA6CC66EFD57F`
- JAR: `5A64BF0D97B2CB8CDD6534E33C642A3C601431C8CE42817B5B865EB07EBD43C7`
- main Lua: `A42D3AD1DE4A34037CDE82FC807B44A0AE17E1028A9AC003EC4F7BE21D814281`
- enemy Lua: `7D0B6BB04D8A3DED75FE2FDE3110CBFF0F90B343190846EEC4EBB7B74C11F279`
