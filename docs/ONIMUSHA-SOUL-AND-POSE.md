# 吸魂奖励与动态物体同步 / Souls and dynamic pose synchronization

仅适用于已验证的 OnimushaWotS 01.000.001 / TDB82。其他 RE 游戏必须独立确认接口和时序。
MOD制作：LCPD15/LCPD拉灯。

## 用户规则 / Requested behavior

MC 接管时，按住 C 或鼠标右键吸魂。右键仍保留原来的物品使用／格挡行为。
四种魂的原生颜色奖励照常执行，每次实际吸收成功后，额外等概率抽取一个有效 MC 奖励：

| 奖励 / Reward | 边界 / Bounds |
|---|---|
| 回复最大生命的 5% / Heal 5% of max HP | 满血重抽，原生血量仍是权威值 / Reroll at full HP; native HP remains authoritative |
| 随机装备恢复 1 耐久 / Repair one durability | 检查背包及身上装备，无损耗物品时重抽 / Inventory and equipped items; reroll if none damaged |
| 随机物品堆叠 +1 / Add one item to a stack | 只选非空且未到物品自身堆叠上限的格子 / Only nonempty, non-full stacks |
| 增加一级经验进度的 23% / Add 23% of one level's XP progress | 满一格正常升级，保留溢出的进度 / Carry progress into the next level |

不根据颜色改变额外奖励；保留原颜色效果，因此黄魂原生回血后也可能额外获得奖励。
无效类别从抽签池剔除，等价于不断重抽，但不会在满血、满背包时陷入循环。
即使前三类都不可用，仍可获得经验。每次成功有独立回执，重复回执不重复发奖。

## 原生证据 / Native evidence

用户使用原角色自然吸收了全部四种颜色；只读探针记录到 11 次
`app.cPlayerSoulAbsorptionSupporter.executeSoulAbsorptionSuccess(app.SoulBase)`，
以及 11 次 `addSoulAbsorption`。证据保存在
`G:/Onimusha_MC_mod/logs/dynamic-sync-soul-20261009/soul-four-colours.json`。

`updateCommand` 和 `requestSoulAbsorptionAction` 没有可靠非内联回调；
`updateBeforeAction` / `lateUpdate` 已确认逐帧触发。
生产脚本在当前玩家的 `cPlayerCommandResult.mergeResult` 返回后写 ABSORB 命令位及
`_IsSoulAbsorption`，并在 supporter 决策前临时写 `_IsCommandAbsorb`。
在 `lateUpdate` 后或帧末恢复保存的原值；退出接管／重载也恢复。
不跳过原生成功函数、不修改原生颜色奖励、不按敌人类别分支。

持有原生对象引用不等于对象仍有效。恢复时沿已验证的玩家实体链检查 GameObject 有效性。
2026-10-09 用户已确认 C／右键吸魂及关闭接管后的原生行为恢复正常；现场有25次成功回调及对应MC奖励。

## 动态物体抖动 / Dynamic pose jitter

旧路径在 Present 收取身体／场景／手持物的独立消息，而 Lua 相机另外读取最新共享 MC 状态。
两个进程帧率不同时，几何和相机可能属于不同 MC 帧；锁到 30 FPS 只是减轻这种差异。

新增 `RenPoseFrame` 消息一次提交相机状态及三路模型。Native 的 Present 只更新待用帧，
Lua 的 `read_render_mc()` 才一次性选定完整帧；该帧用于相机、模型原点、原生动态对象及叠加回退绘制。
MC 更快时丢弃中间完整帧，宿主更快时重复完整帧，禁止混用旧协议的单独手持物消息。
不同世界、旧回执、乱序、截断数据不会覆盖当前展示帧。若模型导出停滞超过 2 秒则退出旧帧，避免无限冻结。

共享内存实时状态仍用于输入、血量和断线检测。此改变不提高模拟 tick 率，也不保证两个进程完全没有显示延迟。
2026-10-09 用户实测确认移动闪动修复；保留该整帧同步路径。

## 验证 / Validation

离线检查覆盖协议布局、整帧替换、不同速率、乱序及上下文变化；Lua 检查按键生命期、原值恢复、重载和只发一次奖励。
独立 MC 测试通过真实服务端队列发 60 个唯一奖励及重复副本，并读取保存后的物品与 XP，检验去重、耐久／堆叠上限及跨级进度。
还需复测 TNT 的闪白、膨胀和声音，以保护上一个已由用户通过的修正。
实际执行结果以本轮 `logs/dynamic-sync-soul-20261009/` 收据为准。

2026-10-09 候选结果：真实 MC 的 60 个唯一回执与60个重复副本只产生60次奖励；
实际存档读取确认5点耐久修好、圆石60→64、10次回血、41次经验奖励累计9级43%。
完整模型在两种视角与行走中锁定1,618帧，没有混帧或错误消息。
最终 TNT 回归记录158帧，白闪与普通各79帧、scale最大1.17345，引线末段仍播放。

## 2026-10-09 接管吸魂热修，待现场复测

用户实测 C 和右键均未吸魂。旧状态记录 injected=27917，但没有记录 held=true 的累计次数，
不能用注入次数证明输入被原生吸魂判断消费。
只读反汇编确认 `updateAfterActionFromBoneEntity()` 会读取 `_IsCommandAbsorb`、选择吸魂类型，
并生成吸魂动作请求。热修在这一入口前重新应用实时输入，保留早期写入、原值恢复和原生奖励流程。
增加 held_frames、bone_injections、overwritten 和实际原生吸魂类型／状态记录。
Lua 回归模拟早期标志被原生命令覆盖，检查决策前重写及引用／原值恢复；不能代替游戏内成功吸魂。

随后用户复测仍无效。现场 held_frames=551、overwritten=0、successes=0：输入已正确传入，
**原生覆盖输入的猜测被排除**，仅写 supporter 的命令标志不足以启动吸魂动作。
23:01 热修改接 `app.cPlayerCommandResult.mergeResult(app.cPlayerCommandController)` 的返回点，
验证 controller 的 Character 是当前玩家后，仅写当前结果的 ABSORB normal/cancel 命令位和
`_IsSoulAbsorption`。ABSORB=14 经现场 `app.PlayerCommand.TYPE.ABSORB` 反射与原生读位代码交叉确认；
不使用 TYPEBit 的数值代替索引、不放开其他输入、不直接制造吸收成功。
保存并在帧末／重载恢复各 Bitset 的单一 ABSORB 位和原始 Boolean，不覆盖其他命令。
新增 command_calls/injections/held 和 last_held_native；输入生命周期回归通过，等待实际 C 吸魂结果。

### 最终实测结论

首次正式命令版本仍失败，原因是把合法的泛型派生类型误判为错误类型：
`_CommandResultNormal`／`_CommandResultCancel` 实际为 `ace.Bitset\`1<System.Int32>`，
必须检查继承 `ace.Bitset`，不能要求类型全名等于基类。两组长度48，ABSORB索引14。
接管关闭时只将该位当前值原样写回并读回，验证继承方法分派；不会制造吸魂输入。
修正后用户确认 C 能吸魂；右键吸魂、原使用行为、关闭接管恢复均确认正常。
Lua 回归以真实泛型派生类型模拟，覆盖两组命令恢复、其他输入位保留、所有持有引用释放。

原生范围参数已经存在：基础水平20、垂直50、角度360°、成功距离约0.3；
升级水平范围25／30／35。未通过任意增加吸魂范围来掩盖命令失败。
现场25次原生成功对应25次MC奖励事件，MC服务端receipt1～25包含全部四类奖励，
不修改原色奖励。用户的右键复测回复「ok」；累计计数不能区分每个按键的贡献。
原生证据与收据位于 `G:/Onimusha_MC_mod/logs/soul-boundary-20261009/`。
