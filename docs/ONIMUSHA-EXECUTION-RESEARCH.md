# 鬼武者处决、动作与伤害接口调查 / Onimusha execution research

2026-10-07。仅适用于本地 **OnimushaWotS 01.000.001 / TDB82** 和固定 REFramework 提交 `b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他 RE 游戏、游戏更新和 SDK 更新都需要重新确认签名、所有者、时序及参数生命周期。

**结论：** 已找到一闪选择器、双人动作流程、力动、吸魂和原生伤害／反馈入口，尚未验证一个可以独立、安全调用的“处决请求”。当前 MC 命中已能实际扣除敌人 HP，但直接改 HP 不会自动组成原生处决、受击动画、力动削减、破甲或吸魂奖励流程。本文只读调查，没有主动请求动作、创建伤害参数、新增运行中钩子或控制游戏。

**English conclusion:** Native action, grapple, posture-break, soul-absorption and hit-feedback interfaces exist. Their signatures do not establish a safe standalone execution request. Minecraft hits already reduce real enemy HP; direct HP writes do not reproduce the native action and damage pipeline. Native execution needs one damage authority, a verified target and action lifecycle, and a separate Minecraft animation plan while the original player remains hidden.

## 证据与当前版本

- 游戏 `reframework/data/onimusha_mc_probe_types.json` 的 `types` 和 `onimusha_mc_probe_snapshot.json` 的 `discovered_types`：本地 TDB82 声明类型、字段、方法参数和返回类型。以下表格中的方法均来自这些捕获；实例地址和自然执行顺序需要另行观察。捕获子集没有某个类型，不代表整个 TDB 中没有该类型。
- [适配器](../onimusha/adapter/onimusha_mc.lua)、[协议](../protocol/skycraft_protocol.h)、[MC 战斗](../fabric/src/main/java/dev/skycraft/combat/SkyCombat.java)、[HostHealth](../fabric/src/main/java/dev/skycraft/combat/HostHealth.java)：现有桥接结算路径。
- 上游 [Combat.cpp](../skse/src/Combat.cpp)、[Game.cpp](../skse/src/Game.cpp) 和 [AvatarExporter.java](../fabric/src/client/java/dev/skycraft/client/render/AvatarExporter.java)：Skyrim 原生伤害与动画路线。其地址、对象布局、等级倍率不能移植到 RE 引擎。
- [格挡研究](ONIMUSHA-GUARD-RESEARCH.md) 已记录当前玩家、控制器和伤害模块的实际所有者链。本文不重复把普通格挡、一闪或处决当成同一种动作。

伤害修订首次冻结为 `1BD91E3F…`，已把 `enemy_host_damage_per_mc_point` 默认值及四份源配置改为 **100**；此前为 10。该版 **15 个 Lua 回归文件／118 组** 通过并完成 Lua 5.4 编译；随后独立审阅补相机失败回滚，最终身份及回归数以[停点记录](ONIMUSHA-RESUME.md)为准。倍率回归验证 7 MC 伤害只换算一次为 700 原生 HP、浮点取整、零值、上限和致死边界。它们是离线生产代码回归，不是处决、原生受击特效或当前候选的游戏内验收。

## 先区分玩法与内部名字

卡普空的玩法说明把力动削减后的“崩し一閃”、命中前精准输入的“一閃”、命中时继续输入的“連鎖一閃”和魂吸收分别介绍。魂吸收可恢复生命／鬼力及获得强化资源。这些是不同玩法，不应统一成“HP 低时按一次键处决”。[卡普空官方发布的玩法说明](https://prtimes.jp/main/html/rd/p/000005330.000013450.html)

| 玩法／需求 | 本地内部证据 | 当前能得出的结论 |
|---|---|---|
| 普通 MC 剑击与 MC 暴击 | EV1 的 `a` 已是 MC 自身修正后的伤害；标志含 `HIT_CRITICAL` | MC 暴击不是原生一闪。不得在换算 100 后再按暴击标志乘一次伤害 |
| 力动崩溃后的特殊攻击 | `cCharacterRikidoSupporter`、`isUsableBreakIssen`、`selectRikidoIssenAction` | 力动与 HP 是不同量；直接改 HP 不证明已满足崩溃条件 |
| 一闪／反击一闪 | Issen sensor、`selectIssenAction`、`requestCounterIssenlAction` | 要观察原生命令、命中时机、目标和失败类型；不能猜枚举值 |
| 连锁一闪 | `cPlayerChainIssenSupporter`、专用伤害与相机方法 | 是多目标／多阶段流程，不应每帧重放一个普通 MC 命中 |
| 终结／双人处决候选 | `executeFatalIssen`、`fatalBlowImpactNotice`、`selectBlowGrappleAction`、grapple flow | 名称支持调查方向，但与用户所指“处决”的确切映射尚未自然验证 |
| 倒地追击候选 | `getEnableBlowGrappleTarget`；selector 有 `selectBlowAttackAction` | 尚未证明目标必须倒地、是否与 FatalIssen 同一路线。`selectIdleCollapseDown*` 属于玩家选择器，不能当作敌人倒地标志 |
| 吸魂 | 独立 SoulAbsorption supporter 与 motion track | 属于收集／恢复流程，不是直接杀敌请求；不能调用成功通知来虚造奖励 |

**English distinction:** Minecraft critical hits, native timed Issen, posture-break finishers, chained Issen, paired grapple actions and soul absorption are separate systems. The exact mapping of `FatalIssen`/`BlowGrapple` to a particular visible finisher is still unverified.

## 真实所有者、合法目标与动作状态

当前玩家链是 `PlayerManager.getControllingPlayerInfo().get_Character()` → `PlayerCharacter` → `get_CharacterEntityHolder().get_Entity()` → 实际 `cPlayerCharacterEntity`。实体及模块的 `get_OwnerCharacter()` 必须匹配当前玩家。当前控制器的 `get_MainControllerEntityHolder().get_Entity()` 应解析为实际 `cPlayerDefaultInputControllerEntity`，其 `_ActionSelector` 的 `_OwnerCharacter`、`_OwnerController` 与 `get__InputEntity()` 也必须一致。

处决目标应来自当前原生 sensor／合法 grapple 目标，并与现有 MC actor 的当前 GameObject、context、epoch 和身份一致。不能仅因两个对象名字相同、距离最近或旧代理 ID 相同，就沿用目标。当前玩家、控制器、场景或目标改变时，动作事务失效；不要另建空选择器或控制器。

表中省略参数名，保留准确声明类型；均为实例方法。返回布尔值不证明方法无副作用。

| 完整签名 | 返回类型 |
|---|---|
| `app.CharacterBase.get_BaseCurrentAction()` | `app.CharacterActionBase.cCharacterActionBase` |
| `app.CharacterBase.get_CurrentActionInfo()` | `app.cCharacterActionInfo` |
| `app.CharacterBase.getActionID_Base()` | `ace.ACTION_ID` |
| `app.cCharacterActionInfo.get_BaseActionID()` | `ace.ACTION_ID` |
| `app.cCharacterEntityBase.get_IsActionValid()` | `System.Boolean` |
| `app.cPlayerActionSelector.get__InputEntity()` | `app.cPlayerDefaultInputControllerEntity` |
| `app.cPlayerCharacterEntity.get_IssenSensor()` | `app.cPlayerIssenSensorController` |
| `app.cPlayerIssenSensorController.get_SelectInfo()` | `app.cPlayerIssenSensorController.SelectInfoData` |
| `app.cPlayerIssenSensorController.getTargetContext()` | `app.cGameContextHolder` |
| `app.cPlayerIssenSensorController.getIssenType()` | `app.PlayerDef.ISSEN_TYPE` |
| `app.cPlayerIssenSensorController.getIssenSuccess()` | `System.Boolean` |
| `app.cPlayerIssenSensorController.getIssenFailureType()` | `app.cPlayerIssenSensorController.SelectInfoData.FAILURE_TYPE` |
| `app.cPlayerIssenSensorController.SelectInfoData.get_TargetObject()` | `via.GameObject` |
| `app.cPlayerIssenSensorController.SelectInfoData.get_TargetJointHash()` | `System.UInt32` |

`SelectInfoData` 另有 `get_TargetContext()`、`get_IssenType()` 和 `get_IsSuccess()`。这些可帮助自然样本关联目标和部位；尚未捕获并确认 `ISSEN_TYPE`、`FAILURE_TYPE`、`PlayerCommand.TYPE`、`ACTION_REQUEST_CATEGORY` 或 `ace.ACTION_ID` 对应可见动作的数值，不能默认 0 就是所需动作。

## 动作请求、双人流程、力动及相机候选

| 完整签名 | 返回类型／边界 |
|---|---|
| `app.cPlayerActionSelector.executeFatalIssen()` | `System.Void`；有零参数方法，不代表可脱离 selector 状态直接执行 |
| `app.cPlayerActionSelector.selectIssenAction(app.PlayerCommand.TYPE)` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.selectIssenAction_BreakIssenCombo(app.PlayerCommand.TYPE, app.CharacterBase)` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.selectRikidoIssenAction()` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.isUsableBreakIssen(app.CharacterBase)` | `System.Boolean` |
| `app.cPlayerActionSelector.selectBlowGrappleAction(app.PlayerCommand.TYPE)` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.selectBlowAttackAction()` | `ace.ACTION_ID` |
| `app.CharacterBase.requestBaseAction(ace.ACTION_ID, app.CharacterDef.ACTION_REQUEST_CATEGORY)` | `System.Boolean`；请求类别含义尚未确认 |
| `app.CharacterBase.requestBaseActionWithArgument(ace.ACTION_ID, app.CharacterDef.ACTION_REQUEST_CATEGORY, app.cCharacterArgumentData)` | `System.Boolean`；需要实际有效参数 |
| `app.cPlayerCharacterEntity.getEnableBlowGrappleTarget()` | `app.CharacterBase` |
| `app.cPlayerCharacterEntity.isEnableGrappleTablePack(app.GrappleTableDef.GRAPPLE_TYPE_Fixed, app.CharacterBase)` | `System.Boolean` |
| `app.cPlayerCharacterEntity.get_GrappleRequestFlosSupporter()` | `app.cGrappleRequestFlowSupporter`；`Flos` 为捕获中的真实拼写 |
| `app.cGrappleRequestFlowSupporter.requestGrapple(app.CharacterBase, app.REQ_GRAPPLE_INFO)` | `app.cGrappleInfo` |
| `app.cGrappleRequestFlowSupporter.requestGrappleFlow(app.REQ_GRAPPLE_FLOW_INFO)` | `app.cGrappleInfo` |
| `app.cCharacterEntityBase.onStartGrapple(app.cGrappleInfo)` | `System.Void`；生命周期通知，不是已验证的外部请求 |
| `app.cCharacterEntityBase.onFinishGrapple(app.cGrappleInfo)` | `System.Void`；同上 |
| `app.cPlayerCharacterEntity.fatalBlowImpactNotice(app.cGameContextHolder)` | `System.Void`；不能把 impact 通知当作动作开始或独立扣血接口 |
| `app.cPlayerCharacterEntity.blowGrappleNotice(app.cGameContextHolder)` | `System.Void` |
| `app.cCharacterEntityBase.get_RikidoSupporter()` | `app.cCharacterRikidoSupporter` |
| `app.cCharacterRikidoSupporter.isBreakIssenTargetCheck()` | `System.Boolean` |
| `app.cCharacterRikidoSupporter.isRikidoBreak()` | `System.Boolean` |
| `app.cCharacterRikidoSupporter.getRikidoValue()` | `System.Int32` |
| `app.cCharacterRikidoSupporter.getRikidoMaxValue()` | `System.Single` |
| `app.cCharacterRikidoSupporter.applyDamage(System.Int32, System.Boolean, System.Boolean)` | `System.Boolean`；两个布尔参数含义未验证，不主动调用 |
| `app.cPlayerCharacterEntity.get_ChainIssenSuporter()` | `app.cPlayerChainIssenSupporter`；`Suporter` 为真实拼写 |
| `app.cPlayerChainIssenSupporter.readyMove(app.CharacterBase)` | `System.Boolean` |
| `app.cPlayerChainIssenSupporter.registerChainIssen()` | `System.Boolean` |
| `app.cPlayerChainIssenSupporter.directChainIssenDamage()` | `System.Void`；不能作为普通剑击追加伤害 |
| `app.GameCameraController.requestChainIssenCameraV2(via.GameObject, via.vec3)` | `System.Void` |
| `app.GameCameraController.requestChainIssenAttackV2()` | `System.Void` |
| `app.GameCameraController.chainIssenCameraV2End()` | `System.Void` |

`REQ_GRAPPLE_FLOW_INFO` 是值类型，捕获到 `Owner : CharacterBase`、`PartnerList : CharacterBase[]`、`ReqGrappleInfos : REQ_GRAPPLE_INFO[]` 三个 backing field。仅这些声明不足以初始化合法事务；`REQ_GRAPPLE_INFO` 的完整内容、动作表／motion bank、相对定位、部位及取消规则尚未验证。

`requestBlockIssen()`、`executeBlockIssen()` 及带 `AttackSensorHitInfo` 的 `requestCounterIssenlAction(...)` 是其他一闪入口。后者原名含小写 `l`；不要修正拼写后按猜测的方法调用。`GameCameraController.isNormalCamera(System.Boolean)` 的布尔语义也没有验证，不能用猜测调用宣称已经保护所有过场。

## 伤害与受击反馈：补反馈必须避免再扣一次

| 完整签名 | 返回类型 |
|---|---|
| `app.cCharacterStockDamage.stockDamageDetail(app.HitInfo)` | `System.Void` |
| `app.cCharacterStockDamage.stockDirectDamage(app.cStockDamageInfoCharacter)` | `System.Void` |
| `app.cCharacterApplyDamage.createApplyParam()` | `app.cCharacterApplyDamage.cApplyParam` |
| `app.cCharacterApplyDamage.execFirstDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.execSecondDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.execThirdDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.calcDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.calcRikidoDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applyDamageReaction(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applyHitSound(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applyHitEffect(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applySoulGenerate(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamageAfter.requestDamageAction(app.BattleInfo.cDamageInfoBase)` | `System.Void` |
| `app.cCharacterApplyDamageAfter.doAfterApplyDamage(app.BattleInfo.cDamageInfoBase, app.cCharacterApplyDamage.cApplyParam[])` | `System.Void` |
| `app.BattleInfo.cDamageInfoBase.get_Damage()` | `System.Single` |
| `app.BattleInfo.cDamageInfoBase.get_HealthDecrease()` | `System.Int32` |
| `app.BattleInfo.cDamageInfoBase.get_RikidoDecrease()` | `System.Int32` |
| `app.BattleInfo.cDamageInfoBase.get_ApplyParam()` | `app.cCharacterApplyDamage.cApplyParam` |

这些是流水线候选，不是可以依次裸调用的食谱。`HitInfo`、stock damage 和 `cApplyParam` 的构造、池归属、嵌套引用、初始化顺序及有效期尚未验证。只允许在真实所属角色、真实命中回调内观察；借来的参数不能跨帧保留。不要在直接改 HP 后再执行 `execFirstDamage`、`stockDirectDamage` 或 `doAfterApplyDamage` 来“补动作／特效”。它们可能再次扣 HP、削力动、破甲、产魂或触发事件。

当前 EV1 仅按 ID 找到当前 enemy HealthManager，将 `max(0, min(1000, a)) × 100` 换算为原生 HP；`set_native_health` 以 `floor(current + delta + 0.5)` 取整并夹在 `[0, maximum]`，调用 `setHealth` 和 `checkHealthZero`。没有派发 `HitInfo`、力动伤害、原生痛苦动作、声音或特效。实际 MC 剑击扣 HP 已经由用户确认；原头顶血条不随转向的问题属于活动相机时序，不能再据此判定 HP 写入无效。`checkHealthZero` 也不等于原生处决、奖励或所有任务事件已经通过。

## 吸魂不是处决；恢复百分比不套敌人倍率

| 完整签名 | 返回类型 |
|---|---|
| `app.cPlayerCharacterEntity.get_SoulAbsorption()` | `app.cPlayerSoulAbsorptionSupporter` |
| `app.cPlayerSoulAbsorptionSupporter.get_IsAbsorption()` | `System.Boolean` |
| `app.cPlayerSoulAbsorptionSupporter.get_IsAbsorptionEnableAction()` | `System.Boolean` |
| `app.cPlayerSoulAbsorptionSupporter.requestSoulAbsorptionAction(System.Boolean)` | `System.Void`；参数语义未验证 |
| `app.cPlayerSoulAbsorptionSupporter.requestAbsorption()` | `System.Boolean` |
| `app.cPlayerSoulAbsorptionSupporter.getAbsorptionType()` | `app.SoulDef.SoulAbsorptionType_Fixed` |
| `app.cPlayerSoulAbsorptionSupporter.executeSoulAbsorptionSuccess(app.SoulBase)` | `System.Void`；需要真实魂对象，不用于造奖励 |

当前玩家受到原生攻击后经过 MC 护甲／盾路径，再用 EV6 的最大 HP 百分比回写原生生命。MC 食物也按同一百分比路线恢复，用户已确认两边恢复同步。**本次 10→100 只影响 MC 对敌人的伤害**；玩家受伤、治疗、吸魂恢复和爱心百分比都不乘 100，也不乘额外 10。实际吸魂、魂奖励及特殊颜色资源仍需要自然样本，不能从食物恢复验收推导。

## 原 SkyCraft 怎样处理命中和动画

上游 `Combat.cpp::ApplyHit` 根据 Skyrim 等级把 MC 伤害换算为原生伤害，通过已核实 AE 地址和调用点的 `HitData` 构造／`Populate` 与 `processHit` 派发命中，填入武器、命中位置、方向和 stagger；有直接扣血／动画图 fallback。它尝试进入真正的 Skyrim 命中流水线，因此与目前鬼武者只改 HealthManager 的能力不同。RE 引擎需要自己的有效 stock／hit 参数路线，不能复制 Skyrim 的内存布局或函数地址。

上游 `Game.cpp::SkyrimTakeover` 会在 `IsInKillMove`、坐骑、坐睡、部分动画／原生相机状态下停止 MC 驱动，让原生控制和动作继续；结束后把 MC 同步到原生最终位置。这不是“把 Skyrim 处决骨骼动画自动变成 MC 人物”。照搬这种退让并恢复原生绘制，不满足用户“始终使用 MC 角色、原角色隐藏”的要求。

`AvatarExporter` 导出的是 MC 自己的已姿态化三角形／纹理，第三人称跟随 MC 自身步行、挥手和使用物品状态；另导出六部分 ragdoll。现有协议没有普通处决用的原生骨骼矩阵、动作 ID／命中帧／相机事务同步。死亡 ragdoll 也不能直接当作任意双人处决的动画重定向。

**English upstream comparison:** SkyCraft dispatches Skyrim-native hits and yields control during native kill moves. Its exported Minecraft avatar is Minecraft-posed geometry, with a separate ragdoll path. It does not supply a generic native-finisher-to-Minecraft skeleton retargeter. Onimusha requires its own verified damage dispatch and a dedicated action/animation handoff while keeping native player drawing hidden.

## 建议实现与唯一结算点

先改善普通 MC 命中：自然样本证明真实 `stockDamage`／`applyDamage` 所属对象与参数后，选择一次完整的原生命中派发来替代当前直接 HP 写入，从而获得原生反应、声音、特效与需要的力动／部位变化。替代而非追加；参数构造未证实时保持现有 HP 路线，不裸调用反馈流水线。

处决采用明确事务 `MC_PLAY → NATIVE_ACTION → RETURN`：事务包含新 transaction ID、当前 epoch、玩家／目标身份、合法动作、状态与命中帧。开始前检查真实原生条件；原生动作期间只对该玩家和该事务调整输入／root motion／相机所有权，不运行全套更新或永久放开原生输入。既有每帧 MC 位移和相机重放会与原生双人动作冲突，应在已验证动作窗口暂停，并在结束、取消、场景变化或 owner 失效时精确恢复原值、同步最终位置及新 teleport 序列。不能用一个未确认的 HP 阈值或计时器代替原生开始／结束事实。

MC 模型继续绘制，原生玩家继续隐藏。较小的视觉实现是自制 MC 六部位处决关键帧，按原生动作实际命中／结束阶段同步；它只能称为自定义 MC 动画。若需要贴合原生招式，则另验证原生关节姿态、绑定轴和骨骼到 MC 六部分的映射，再按原生动作帧重定向。两条路线都需要协议／MC 动画支持，当前候选没有完成；原始角色的原生动画不能仅靠设置血量或保留 motion 组件自动显示在 MC 模型上。

| 结算情形 | 推荐唯一权威与倍率 | 防止重复 |
|---|---|---|
| 普通 MC 命中 | MC 修正后的 `a`，一次 `×100` 进入原生 HP／未来有效命中路线 | 暴击已在 `a` 中；不再乘额外 10，不再同时 direct HP + native hit |
| 原生处决／一闪作为完整原生动作 | 原生实际命中帧的伤害与奖励；先保留原生动作本身的数值 | 同一事务不再提交普通 MC 的 700 HP，不能先扣 700 再执行原生处决 |
| 若后续明确选择 MC 数值驱动处决 | 每个已验证事务命中只结算一次 MC 数值 `×100`；原生同次 HP 扣减必须被精确去重 | 需要验证原生伤害所在时点、部位与回调；当前未实现，不能先盲拦截所有原生扣血 |
| 玩家受伤／治疗 | 原生 HP 百分比与 MC 20 点生命，现有 EV6 路线 | 不应用敌人倍率；不借处决补扣玩家血 |

若未来要求原生处决伤害也额外增强，应先取得原生动作自然伤害基线，再在唯一的该事务最终伤害结算点决定倍率。不能把当前 `100` 当“所有原生动作都再乘 100”，也不能叠加 MC 700 与原生动作伤害后宣称倍率正确。协议 EV1 当前只有目标 ID、伤害、击退、标志和武器类别，没有处决事务／epoch／动作帧确认；不能挪用现有武器值或 EV6 的 epoch 字段来假装完成处决协议。

## 明日最少自然样本与通过条件

今晚不新增运行中钩子、不请求用户操作。明日先用 **F10 关闭的原生模式**，由用户在可重复的普通敌人场景自然操作；研究阶段只做有界只读记录，不主动调用上表请求／结算方法。

1. 一次普通剑击：关联当前玩家、活动敌人、真实命中回调、DamageInfo 的实际 HP／力动下降与反馈。作为现有 MC 伤害换算的原生流水线对照。
2. 一次用户所指的处决／倒地终结，并说明画面触发方式；同时取得开始前 sensor／合法目标、action ID、grapple 开始／结束、实际伤害帧、相机 owner 与最终位置。若用户所指实际是崩し一閃，就按该动作记录，不能用名字猜映射。
3. 在同场景一次力动崩溃的一闪及随后吸魂；若第 2 项已经覆盖崩溃一闪，只补吸魂。仅在上述样本仍不能区分普通精准一闪与终结动作时，再增加一次对应一闪，不要求同时测试全部招式／Boss。

每个样本只保留少量记录，保存数字、类型、owner／target 地址、原返回值和相位，不持有借来的 HitInfo／ApplyParam 跨帧。不用全量类型扫描或泛 hook 每帧重入流水线。

通过条件是：一次输入产生一个合法动作事务；一次实际命中只结算一次；原生敌人确有反应与正确 HP／力动／奖励；MC avatar 的动作及位置跟随事务；原生玩家仍隐藏；取消、F10 关闭或场景切换后，输入、相机和所有恢复 ledger 均正确归还。未满足这些条件前，只能报告“接口候选与设计”，不能报告“处决已可用”。

**English next validation:** Capture a natural native hit, the specific finisher the user means, and a posture-break/soul-absorption example, reusing the same example where possible. Observe ownership, target identity, action/impact phases, HP/posture changes and camera handoff. Do not invoke guessed requests or replay borrowed damage parameters. Keep one damage authority and verify cancel/disable restoration before accepting Minecraft takeover executions.

---

MOD制作：LCPD15/LCPD拉灯
MOD author: LCPD15 / LCPD拉灯. Based on SkyCraft by chasmlol; retain upstream license and attribution.
