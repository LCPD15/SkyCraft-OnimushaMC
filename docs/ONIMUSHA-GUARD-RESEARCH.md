# 鬼武者格挡接口调查 / Onimusha guard research

2026-10-07。仅适用于本地 **OnimushaWotS 01.000.001 / TDB82**，以及本工程固定的 REFramework 提交 `b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。其他 RE 游戏或其他版本需要重新确认类型、签名、所有者、时序及参数生命周期。

用户要求：MC 右键举盾，或有格挡能力的剑等物品，应真正进入 MC 格挡结算；完全格挡时不扣血，并产生一次格挡声音和可见反馈。原生玩家隐藏绘制后，也应保留正确的原生受击／格挡行为。下面区分静态接口证据、MC 字节码证据和仍需自然样本的原生行为；本调查没有调用格挡动作、伤害工厂或声音／特效请求。

2026-10-07下午用户明确：MC侧普通成功格挡只需格挡效果且不扣血，不需要消耗鬼武者力动。特殊不可防御攻击需弹反，暂时不做。敌人与MC角色的受击反馈都要处理。此要求不等于把未知来源或所有方向的命中强制判定为成功格挡。

自然格挡、同次stock来源和玩家扣血阶段采样已完成，详见文末实测补记；未主动调用动作、工厂或反馈请求。

**English conclusion:** Minecraft shield blocking uses vanilla directional damage rules. TDB82 natural-hit samples now prove the same-call stock record contains the attacker and receiver, and `execThirdDamage` encloses the player HP mutation. Lua466822 supplies that generic source through the existing actor table; no per-enemy or per-animation logic is used. JAR22004 adds observed vanilla guard feedback and optional sword blocking. These versions have now passed a real Fabric boot and the user's live block/sound and ordinary HP-loss test. Red flash, knockback and sparks have not been individually confirmed. Native enemy reactions and a durable zero-damage settlement acknowledgement remain separate unfinished work.

## 证据来源与验证边界

- 本地 `onimusha_mc_probe_types.json` 和 `onimusha_mc_probe_snapshot.json` 的 `discovered_types`，提供 TDB82 方法、字段和声明类型。方法存在不等于已安全调用，也不证明先后顺序。
- 本工程 `onimusha/adapter/onimusha_mc.lua`、`protocol/skycraft_protocol.h`、`fabric/src/main/java/dev/skycraft/combat/SkyCombat.java`、`fabric/src/main/java/dev/skycraft/combat/HostHealth.java`、`fabric/src/client/java/dev/skycraft/client/InputBridge.java`，提供现有桥接路径。后续源码行号可能变化，因此按文件和方法检索。
- 本地实际 Minecraft 26.3 JAR 的字节码审查，提供盾、剑、`LivingEntity.applyItemBlocking`、`LivingEntity.hurtServer` 和 `BlocksAttacks.onBlocked` 行为。本段不能作为鬼武者原生格挡已通过的证据。
- 未确认原生 `FLAG`／`RESULT` 的枚举字面值、不可格挡位、合法格挡请求条件，以及 `app.cCharacterApplyDamage.cApplyParam` 的完整成员、池归属和借用期限。不得猜枚举值、裸偏移或构造一个空控制器代替当前原生对象。

## 当前原生玩家的真实所有者链

所有链都应在当前普通场景重新解析，核对真实类型、有效性和地址身份。场景、玩家或控制器变化后失效；不能仅凭字段名字相同就继续使用旧实例。

| 用途 | 已存在的链与身份检查 |
|---|---|
| 当前玩家 | `app.PlayerManager.getControllingPlayerInfo().get_Character()` → `app.PlayerCharacter`（继承 `app.CharacterBase`） |
| 角色实体 | `app.CharacterBase.get_CharacterEntityHolder()` → ``app.cEntityHolder`1<app.cCharacterEntityBase>`` → `get_Entity()`；运行时需确认为 `app.cPlayerCharacterEntity`，且 `get_OwnerCharacter()` 与当前玩家相同 |
| 格挡控制器 | `app.cPlayerCharacterEntity.get_PlayerGuardController()` → `app.cPlayerGuardController`；`app.cCharacterModuleBase.get_OwnerCharacter()` 须匹配玩家，`app.cPlayerGuardController.get_CharacterEntity()` 须匹配当前实体 |
| 角色输入参数 | `app.CharacterBase.get_ArgumentData()` → `app.cCharacterArgumentData` → `get_Input()` → `app.cCharacterArgumentData.cInputArgument` → `get_IsGuard()` |
| 当前输入控制实体 | `app.CharacterControllerBase.get_MainControllerEntityHolder()` → ``app.cEntityHolder`1<app.cCharacterControllerEntityBase>`` → `get_Entity()`；运行时核对 `app.cPlayerDefaultInputControllerEntity`，其基类 `app.cPlayerInputControllerEntity.get_CommandResult()` → `app.cPlayerCommandResult.get_IsGuard()` |
| 动作选择器 | 当前 `app.cPlayerDefaultInputControllerEntity` 的 `_ActionSelector` → `app.cPlayerActionSelector`；`get__InputEntity()`、`_OwnerCharacter` 和 `_OwnerController` 须匹配当前真实输入实体、玩家和控制器 |
| 伤害模块 | 当前 `app.cPlayerCharacterEntity` 的 `_DamageInterface` → `app.cPlayerApplyDamage`；继承的 `get_OwnerCharacter()` 须匹配玩家 |
| 当前战斗信息 | `app.cPlayerCharacterEntity.get_BattleComponent()` → `app.BattleComponent.get_DamageInfo()` → `app.BattleInfo.cDamageInfoBase`；另一入口是 `get_ArgumentData().get_Damage()` → `app.cCharacterArgumentData.cDamageActionArgument.get_DamageInfo()`。只能在匹配的实际受击回调内作为该次命中信息，其他时刻可能是旧值 |
| 原生血量 | 当前 PlayerInfo 的 `get_Context().get_Chara().get_HealthManager()`；需与适配器已验证的玩家 HealthManager 相同 |

`PlayerCharacter._PlayerCharacterEntity` 也出现在元数据中，但优先使用已有 holder 的 getter 链并验证实体所有者。不要另行创建实体、控制器、选择器或伤害模块。

## 原生输入、持续格挡与动作接口

下表均为实例方法。返回类型和参数来自本地元数据；本调查没有主动调用动作选择、更新或状态修改方法。

| 完整签名 | 返回类型／用途 |
|---|---|
| `app.cCharacterArgumentData.cInputArgument.get_IsGuard()` | `System.Boolean`，输入请求 |
| `app.cCharacterArgumentData.cInputArgument.set_IsGuard(System.Boolean)` | `System.Void`，不能独自证明已经进入格挡 |
| `app.cPlayerCommandResult.get_IsGuard()` | `System.Boolean`，处理后的命令结果 |
| `app.cCharacterGuardController.get_IsGuard()` | `System.Boolean`，持续格挡状态 |
| `app.cCharacterGuardController.setup(app.CharacterBase, app.user_data.CharacterGuardParam)` | `System.Void`，需要真实所有者和原生参数 |
| `app.cCharacterGuardController.update()` | `System.Void`，原生生命周期方法，不能当作独立请求随意调用 |
| `app.cCharacterGuardController.setFlag(app.cCharacterGuardController.FLAG)` | `System.Void`，枚举字面值尚未确认 |
| `app.cCharacterGuardController.checkEnableGuardActionCondition()` | `System.Boolean` |
| `app.cPlayerGuardController.checkEnableGuard()` | `System.Boolean` |
| `app.cPlayerGuardController.checkEnableGuardActionCondition()` | `System.Boolean` |
| `app.cPlayerGuardController.getGuardDir()` | ``System.ValueTuple`2<app.CharacterDef.DIR15,System.Int32>`` |
| `app.cPlayerGuardController.getGuardRikidoRate()` | `System.Single` |
| `app.cPlayerGuardController.addDamage(System.Single)` | `app.cCharacterGuardController.RESULT`，不是无副作用查询 |
| `app.cCharacterEntityBase.isGuardStance()` | `System.Boolean` |
| `app.CharacterActionBase.cCharacterActionBase.isGuardStance()` | `System.Boolean` |
| `app.cPlayerActionSelector.selectGuardAction()` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.selectGuardStopAction()` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.cancelGuardStop()` | `ace.ACTION_ID` |
| `app.cPlayerActionSelector.selectTwoHandGuardMoveSubAction()` | `ace.ACTION_ID` |
| `app.cPlayerInputControllerEntity.updateInputArgument()` | `System.Void` |
| `app.cPlayerDefaultInputControllerEntity.updateActionSelector()` | `System.Void` |

`app.cPlayerActionSelector.requestBlockIssen() → System.Boolean` 和 `executeBlockIssen() → System.Void` 也存在，但属于另一条一闪相关动作路径，不能替代普通举盾／举剑格挡。控制器存在 `.ctor()` 并不证明新建空控制器能满足 `setup`、所属实体、持续标志和动作状态机条件。

隐藏玩家 `DrawSelf` 属于绘制控制，不等于关闭战斗模块。不过当前接管还会封闭原生输入并跳过原生 root motion；这些操作是否阻止合法的原生 guard 动作，需要单独观察。不能通过猜测 `FLAG` 或设置一个输入布尔值宣称已解决。

## 原生格挡伤害、反应、声音与特效

以下参数类型的完整名字均为 `app.cCharacterApplyDamage.cApplyParam`。所有者必须是上表解析的实际玩家伤害模块。

| 完整签名 | 返回类型 |
|---|---|
| `app.cCharacterApplyDamage.setup(app.CharacterBase, app.cCharacterStockDamage, app.cCharacterApplyDamageAfter)` | `System.Void` |
| `app.cCharacterApplyDamage.apply()` | `System.Void` |
| `app.cCharacterApplyDamage.createApplyParam()` | `app.cCharacterApplyDamage.cApplyParam` |
| `app.cPlayerApplyDamage.createApplyParam()` | `app.cCharacterApplyDamage.cApplyParam` |
| `app.cPlayerApplyDamage.doApplyStockDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.isEnableGuardDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Boolean` |
| `app.cCharacterApplyDamage.calcGuardDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.calcDamage(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.getGuardAttackRate(app.cCharacterApplyDamage.cApplyParam)` | `System.Single` |
| `app.cCharacterApplyDamage.calcGuardDefenceRate(app.cCharacterApplyDamage.cApplyParam)` | `System.Single`，`app.cPlayerApplyDamage` 也有该覆盖方法 |
| `app.cCharacterApplyDamage.getGuardDamageRate(app.cCharacterApplyDamage.cApplyParam)` | `System.Single` |
| `app.cCharacterApplyDamage.applyGuardDamageReaction(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applyHitSound(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |
| `app.cCharacterApplyDamage.applyHitEffect(app.cCharacterApplyDamage.cApplyParam)` | `System.Void` |

这些方法证明存在工厂和结算／反馈入口，但没有证明可以离开原生结算流程安全构造、复制或异步重放参数。`cApplyParam` 的引用／值类型、完整字段、内部池、初始化顺序及借用生命周期必须先验证；借来的命中参数不能跨帧保留。禁止再次调用 `doApplyStockDamage` 来“补特效”，以免重复结算 HP、耐力、破甲或动作。

尚未发现并验证一个可独立零参数调用的 `playGuardSound`。`app.CharacterSoundParamContainer.invokeSoundEvent(System.Int32)` 的方法存在，但 guard 的事件 ID 未确认；`via.effect.script.ObjectEffectManager2.requestEffect(...)` 存在重载，但真实 guard EffectID、挂点和所有者未确认。不要猜 ID 或主动构造效果请求。原生反馈是否复用 `applyHitSound`／`applyHitEffect`，要由自然格挡样本证明。

**English safety boundary:** Observe the real player-owned module and preserve original return values. A factory signature is not proof that an empty damage parameter is valid. Do not allocate replacement guard controllers, guess enum flags, retain borrowed hit parameters across frames, or replay native damage application just to obtain sound or effects.

## 攻击者方向与不可格挡信息

| 完整签名 | 返回类型／观察价值 |
|---|---|
| `app.BattleInfo.cBattleInfoBase.get_Attacker()` | `via.GameObject`，真实攻击者候选 |
| `app.BattleInfo.cDamageInfoBase.get_AttackObj()` | `via.GameObject`，攻击对象候选，不能默认等于角色所有者 |
| `app.BattleInfo.cDamageInfoBase.get_AttackVector()` | `via.vec3` |
| `app.BattleInfo.cDamageInfoBase.get_VectorToAttacker()` | `via.vec3` |
| `app.BattleInfo.cDamageInfoBase.get_AttackerAxisZ()` | `via.vec3` |
| `app.BattleInfo.cDamageInfoBase.get_HitPosition()` | `via.vec3` |
| `app.BattleInfo.cDamageInfoBase.get_AttackParamData()` | `app.cAttackRuntimeParamBase` |
| `app.BattleInfo.cDamageInfoBase.get_ApplyParam()` | `app.cCharacterApplyDamage.cApplyParam` |
| `app.BattleInfo.cDamageInfoBase.get_DamageActionType()` | `app.CharacterDamageReactionType.TYPE` |
| `app.BattleInfo.cDamageInfoBase.get_AttrBit()` | `app.CharacterDamageAttribute` |
| `app.BattleInfo.cDamageInfoBase.get_Damage()` | `System.Single` |
| `app.BattleInfo.cDamageInfoBase.get_HealthDecrease()` | `System.Int32` |
| `app.BattleInfo.cDamageInfoBase.get_RikidoDecrease()` | `System.Int32` |
| `app.CharacterDamageAttribute.get_Attribute_1()` | `app.CharacterDamageReactionAttribute.TYPEBit` |
| `app.CharacterDamageAttribute.get_Attribute_1_Unique()` | `System.UInt64` |
| `app.CharacterDamageAttribute.get_Attribute_2()` | `app.CharacterDamageType.TYPE` |

先证明战斗信息与同次 `cApplyParam`、攻击者、玩家相匹配，再记录攻击者／玩家位置、受击点、攻击向量、属性原值和原生 guard 判断。不要把所有近战一律当作可格挡，或猜某个属性位就是不可格挡。精确属性字面值和具体攻击行为需要普通正面、背后、不可格挡攻击的分开样本。

## MC 26.3 的实际格挡行为和当前桥接缺口

盾有 `BLOCKS_ATTACKS`，默认延迟 0.25 秒，即 5 个 MC tick；字节码中正面 90° 条件内的默认 factor=1 可全额减免。`LivingEntity.hurtServer` 已经过 `applyItemBlocking`，不需要另调用一次。其伤害来源位置为空时按角度 π 判断，无法满足该正面条件。

旧Lua BC6A及之前始终传入`attacker_id=0`。Lua466822从同一次同步扣血调用中核对stock接收者和当前actor表后传真实ID；无法匹配时仍为0。Java `SkyCombat.hurtPlayer`没有攻击者时使用`damageSources().generic()`，有真实actor时才选择带来源的伤害。该机制对敌人共用，不需要逐招式适配，不选择“附近最近敌人”代替来源。

MC 剑的 `applySwordProperties` 添加 TOOL、攻击属性和 WEAPON，没有 `BLOCKS_ATTACKS`；默认 `Item.use` 返回 PASS。因此剑的右键格挡需要明确增加物品能力及使用逻辑，且应保留“主手剑＋副手盾”时盾的使用优先级。举起模型、播放 BLOCK 动画或 `hurtServer` 返回 false 都不单独证明成功格挡。

真实减免依据是该次 `applyItemBlocking` 返回的 blocked amount > 0。完全格挡返回 false，免疫／无敌帧也可能返回 false，不能混为一谈。`hurtServer` 在阻挡判断之后才检查伤害冷却／`lastHurt`，所以有 blocked amount 也可能在无敌帧早退，未调用 `BlocksAttacks.onBlocked`。需要一次命中的上下文同时记录 blocked amount 和原生 MC `onBlocked` 是否实际发生。

Vanilla `BlocksAttacks.onBlocked` 已播放一次 `SHIELD_BLOCK`，没有粒子。反馈实现应优先沿用该次回调；若要求为一次已接受但在无敌帧早退的完全格挡补反馈，只能补缺失的一次声音，不能无条件再播。MC 的可见粒子可以通过现有 `AvatarExporter` 的 quad particle 导出路径实现，但这不等于已经触发鬼武者原生 guard 特效。MC 反馈和鬼武者反馈需分别验收。

**English MC conclusion:** Preserve vanilla shield timing and directional checks. Add sword blocking explicitly if required, while retaining off-hand shield priority. Use the actual blocked amount and whether `onBlocked` ran; a false hurt return is ambiguous. Vanilla already emits its block sound, so supplement only missing feedback and do not play it twice. Native Onimusha feedback remains a separate, unverified integration path.

协议 v12 的 `IN_HURT`（7）仅提供 kind（melee=0、projectile=1、magic=2、other=3）、伤害、attacker ID 和现有标志。`HostUnapplied` 是 bit2（4）；已有 blocked-in-Skyrim 标志不能当作本次 MC 实际格挡结果。协议当前没有命中事务 ID、可信不可格挡字段或显式“零伤害格挡已结算”回执。

`HostHealth.request` 仅为非零 HP 比例变化发送 `EV_HEALTH_CHANGE`（6）。原生 HP 写入被跳过之后，入队成功仍不代表 integrated server 已执行、HP 回执已被宿主消费；重启、暂停、epoch 变化可能丢弃排队命中。MC HP 在回调前后暂时相同也不能证明完全格挡，因为正常非零伤害同样等待宿主权威回写。后续实施必须先设计一击一次的接受／结算事务，包括明确零伤害结果、会话检查、去重和故障恢复，不能靠缺少 EV6 默认为格挡成功。

## 下一步：F10 关闭的自然格挡观察

先观察原生玩家普通正面格挡和普通受击，MC 接管关闭；不自动切开关，不修改输入、HP、动作或效果。独立探针最多同时绑定四个必要方法：玩家 `doApplyStockDamage`、基类 `isEnableGuardDamage`、`applyGuardDamageReaction`，以及 `applyHitSound`。若需要确认特效，将最后一个换为 `applyHitEffect` 做另一轮样本，避免扩大 hook 面。

每个回调先以 raw `this` 地址匹配已验证的当前玩家伤害模块，再使用固定 SDK 的安全对象转换。`cApplyParam` 必须先通过真实方法参数类型元数据确认引用类型；若无法证明，只记录调用计数和数字相关标识，不能解引用猜结构。参数只在同一回调内读取实际类型及已确认的字段；快照只保留数字、向量分量、枚举原值和调用顺序，不跨帧保存临时 managed 对象。

记录输入请求、命令结果、持续 guard 状态、原生判断返回值、格挡反应／声音入口是否发生，同次伤害参数与 BattleInfo 的身份关系，攻击者／玩家位置、受击点、攻击属性和实际 HP 变化。原返回值始终原样返回；日志有限长，回调内不做文件 I/O，不调用 `createApplyParam`、原生效果、动作选择、控制器更新或伤害结算。

自然样本能够证明攻击者和 guard 分支的实际关联，随后才可把可信来源接到 MC 盾的方向判断，并设计不重复结算的事务。该探针本身不会完成原生格挡请求或反馈重放。背后、不可格挡和一闪各需独立样本；不能用普通正面格挡结果覆盖全部攻击类型。

实现后的验收需分别覆盖：盾延迟与正面全挡 0 HP、背后及不可格挡攻击正常伤害、剑能力与副手盾优先、声音／粒子各一次、会话或 epoch 变化不吞伤不重扣、F10 关闭正常恢复，以及隐藏原生玩家时的真实原生 guard 行为。任何尚未验证的条目不得写成已支持。

## 独立四钩子探针设计（下方保留原设计，已实现）

文件为 `onimusha/adapter/onimusha_guard_probe.lua`，与生产适配器分开。已实现、部署并获得首轮有效自然样本。更新版新增同次DamageInfo字段读取和静态战斗metadata导出，17组回归通过，新增部分等待下一次进场景采样；不能把先前版本的实景结果继承给未测的新字段读取。

1. 默认不记录，仅显式 arm。要求原生玩家已入普通场景、桥接 `enabled/active=false`（F10关闭）、stage/owner稳定。只读核对 PlayerManager→PlayerInfo→PlayerCharacter→EntityHolder→实际 `app.cPlayerCharacterEntity`，实体及 `_DamageInterface`／GuardController 的 owner 均指向同一玩家。读取真实 Input.IsGuard、CommandResult.IsGuard、持续GuardController.IsGuard与BattleInfo。探针不能自动切F10或请求格挡。
2. 同时最多四个 hook：`app.cPlayerApplyDamage.doApplyStockDamage(app.cCharacterApplyDamage.cApplyParam) → System.Void`；`app.cCharacterApplyDamage.isEnableGuardDamage(app.cCharacterApplyDamage.cApplyParam) → System.Boolean`；`app.cCharacterApplyDamage.applyGuardDamageReaction(app.cCharacterApplyDamage.cApplyParam) → System.Void`；`app.cCharacterApplyDamage.applyHitSound(app.cCharacterApplyDamage.cApplyParam) → System.Void`。特效另轮以 `applyHitEffect` 替换第四项，不增加第五hook。确认真实function地址、declaring type、参数和返回类型，避免重复同一实现地址。
3. 每个pre回调首先以 raw `this` 数字地址匹配已验证的当前 `_DamageInterface`，再使用固定SDK安全managed-object转换。参数TD必须先证明真实引用类型；固定C++ SDK提供 `TypeDefinition::is_valuetype()`，Lua对应接口必须先确认实际可用，不能编造另一个名字。无法证明则只记调用计数及数字相关标识，不解引用 `cApplyParam`。只有验证后才在同一回调读实际类型与已确认的标量字段。
4. 使用thread-local调用栈关联嵌套原生结算；不能只按池对象地址跨帧相关。核对同次 `BattleInfo.get_ApplyParam()` 与参数身份、真实Attacker/AttackObj、玩家／攻击者XYZ、hit/vector、属性原值与HP。错误或owner失效只记录拒绝原因；不得返回SKIP_ORIGINAL或替换原retval。Bool结果仅观察原回调返回，不额外调用guard判定来“再算一次”。
5. 保留最多256条纯数字／文字快照，回调内无文件I/O，不保留临时managed参数，不factory、new effect、更新controller或重复结算。场景/owner变化解除arm。保存由外部安全回调显式触发；钩子存在但未捕获认证owner时只计数，不能宣称样本有效。
6. 首轮由用户自然执行普通正面guard与普通受击；记录输入请求→真实guard状态→伤害入口→guard判断→反应/声音→HP变化的实际顺序。背后、不可格挡、一闪分轮观察。声音hook出现也不自动证明某个事件ID就是格挡声；必要时关联已存在对象的真实事件身份。

这条观察路线可以帮助替换当前 `attacker_id=0`：必须把**同一次**原生命中的Attacker匹配当前actor registry，并使用其可信位置构造MC伤害来源。当前HealthManager写入hook只能看见HP变化，本身不能代表已经被原生全挡、HP为零变化的完整命中。后续仍需接受／零伤害结算事务与dedupe，不能重复调用 `doApplyStockDamage` 或既走原生扣血又走MC扣血。

## 2026-10-07下午实测补记

`logs/live-camera-bc6a-20261007/guard-user-confirmed-02.json`保留26条自然pre/post记录：

- cApplyParam已由真实TDB证明为引用类型；四个函数都真正调用并命中认证玩家模块。原始返回值、调用顺序、HP和标量快照保留，无读取错误。
- UniqueID18、frame943：持续guard=true，isEnableGuardDamage两次返回true；applyGuardDamageReaction一次、applyHitSound一次；HP1406→1406、HealthDecrease0、RikidoDecrease342。
- UniqueID19、frame970：guard=false，判定false；进入doApplyStockDamage前HP已从1406变981，HealthDecrease425；声音入口一次。说明该回调不能被当作最早HP结算入口。
- UniqueID20、frame1041：用户标记为暂缓的特殊不可防御攻击；HP981→96，HealthDecrease885。未采集到可信属性位，不能凭伤害大小实现不可防御识别。
- BattleInfo.get_ApplyParam与当前参数全部不匹配，没有捏造攻击者信息。参数自身的DamageInfo字段类型为app.cStockDamageInfoCharacter，新增只读版本将从该同次字段验证攻击者及向量。
- 第一轮因过严地要求MC host_ready而提前停止，没有有效样本。第二轮只要求F10关闭并验证真实场景、玩家与模块所有者；host_ready是MC接管条件，不能用于排除正常原生战斗。

截至此记录，MC格挡来源、结算ACK、敌人原生反应请求和双方受击反馈尚未完成。MC导出器已有第三人称红色受击overlay转换；第一人称原版hurt camera tilt尚未在RE相机协议中传输，不能把已有hurtServer调用等同于所有视觉反馈均验收。

## MC实景验收05

用户确认“格挡正常，有音效，受击也能正确扣血”，随后F10关闭、恢复正常。Lua466822 / JAR22004 / DLL5291：6次真实格挡日志均blocked=incoming、blockingCalls=1，HP不变；两次未格挡hurt=true，同击来源actor4/18均匹配，后一击EV6使原生HP1756→1615。新JAR已实际启动，无Mixin初始化错误，剑能力开关已启用。

证据：logs/live-camera-bc6a-20261007/combat-source-guard-active-05.json、combat-source-user-restored-05.json，以及live-guard-feedback-20261007.stdout.log。此结果不替代敌人受击、背后格挡、特殊弹反、粒子/红闪/击退及跨会话ACK验收。

## Credit

上游 SkyCraft：chasmlol，MIT；本工程保留上游许可。鬼武者接口调查、适配及测试记录属于本移植工程，未附带原始游戏文件或 TDB dump。

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯
