# 原生受击流程调查 / Native hit-reaction research

2026-10-07。仅适用于本地 OnimushaWotS 01.000.001 / TDB82，不能直接套到其他RE游戏。

用户已重新确认MC剑击会扣敌人HP；未显示血条导致过一次误判。当前EV1通过目标ID获取HealthManager，执行setHealth/checkHealthZero，没有走原生受击、特效、声音或破甲流程。不能再用“没有扣血”作为修复前提，也不能将手动减血描述成完整原生战斗。

以下来自本地`onimusha_mc_probe_types.json`和snapshot的`discovered_types`，只是接口存在的证据，不代表已确认执行顺序或安全调用方式：

| 功能 | 真实方法候选 |
|---|---|
| 命中入队 | `app.cStockDamageBase.stockDamage(app.HitInfo)` |
| 直接伤害入队 | `app.cCharacterStockDamage.stockDirectDamage(app.cStockDamageInfoCharacter)` |
| 伤害结算 | `app.cCharacterApplyDamage.apply()` |
| 受击特效 | `app.cCharacterApplyDamage.applyHitEffect(app.cCharacterApplyDamage.cApplyParam)` |
| 受击声音 | `app.cCharacterApplyDamage.applyHitSound(app.cCharacterApplyDamage.cApplyParam)` |
| 受击反应 | `app.cCharacterApplyDamage.applyDamageReaction(app.cCharacterApplyDamage.cApplyParam)` |
| 动作请求 | `app.cCharacterApplyDamageAfter.requestDamageAction(app.BattleInfo.cDamageInfoBase)` |
| 部位伤害结果 | `app.cCharacterApplyDamage.applyPartsDamageResult(app.cCharacterApplyDamage.cApplyParam, app.BattleInfo.cDamageInfoBase)` |

上述方法返回System.Void。猜测的`app.EnemyApplyDamage`和`app.PlayerApplyDamage`在缓存中明确不存在，应使用真实类型继续调查。

所有者可通过`CharacterBase.get_CharacterEntityHolder().get_Entity()`读取，需核对holder.isValid、entity.get_OwnerCharacter，以及伤害模块get_Valid/get_IsDestroy；场景变化后重新解析。`cCharacterEntityBase.stockDirectDamage`还有返回`cStockDamageInfoCharacter`的重载，接收两个GameObject、cAttackRuntimeParamBase和Nullable攻击方向，但两个GO的角色、nullable构造方式及枚举语义尚未知。

下一步是在F10关闭时被动记录一次用户原生轻击：伤害入队、结算、动作请求的实际顺序，以及同帧攻击者、受击者、HP变化和已存在参数的类型/标量。HitInfo/cApplyParam等临时对象不跨帧保留，不创建或裸调不完整参数，不主动重复原生伤害方法。观察清楚后再做受控MC剑击，并验证只结算一次伤害、真实硬直/效果和普通恢复；破甲另需自然样本。

No native reaction entry has been invoked by this research. The listed methods are verified
metadata candidates only. Observe one natural native hit with takeover off before constructing
any request. Do not keep borrowed damage parameters across frames or duplicate HP deductions
when replacing the current direct-health path. Armor break requires a separate natural sample.

## 2026-10-07 普通命中实测

用户要求采用所有敌人共用的受击／格挡处理，不逐敌人、逐招式适配；特殊不可防御／弹反攻击暂缓。

只读样本 `logs/live-camera-bc6a-20261007/combat-flow-user-confirmed-04.json`：原角色轻击一次、小怪普通攻击一次，用户确认已操作。共12条pre/post记录，零读取错误。

| 调用 | 所有者 | HP边界 | 结果 |
|---|---|---|---|
| `cEnemyApplyDamage.execFirstDamage` | 真实敌人实体的伤害模块 | 2700→2700 | 原玩家攻击使用`cAttackRuntimeParamPlayer`，基础Attack100 |
| `cCharacterApplyDamage.applyHitEffect` | 同一敌人、同一UniqueID3 | 2460→2460 | 到特效阶段已经扣240HP；不能用该方法代替伤害入口 |
| `execFirstDamage` / `execSecondDamage` | 当前玩家 | 1671→1671 | 两阶段均未扣血 |
| `execThirdDamage` | 当前玩家、UniqueID4 | 1671→1317 | 包围了实际354HP减量；可为同步HP回调提供同次命中上下文 |
| `applyHitEffect` | 同一玩家、UniqueID4 | 1317→1317 | 在扣血之后调用 |

`cEnemyApplyDamage.applyDamageReaction`本轮调用0次，不能声称已验证该函数是所有敌人的硬直入口。敌人覆写阶段没有调用被hook的基类second/third，本轮也未观察其完整结算边界。只看函数名推断层次或补调方法会有重复扣血、遗漏破甲的风险。

生产Lua466822加入同线程`execThirdDamage`临时上下文：核对当前玩家伤害模块、参数实际引用类型、stock接收者、真实GameObject与当前代理表身份，向现有IN_HURT传通用actor ID。只保存标量到本次调用结束，嵌套未知命中遮住外层来源，epoch／帧／玩家变化或来源未知时回退原generic路径。没有敌人类型或招式分支，也没有主动调用原生动作／特效。9组生产hook回归覆盖方向来源、嵌套、线程、场景、未知对象、队列失败和异常清理；全17个Lua回归脚本通过。安装不等于实景格挡验收。

该改动使Minecraft能够使用真实方向走自己的盾牌规则和常规受击反馈；原生敌人动作／特效仍未接入。旧EV1继续只写一次HP，十倍倍率100不变。不要把MC粒子、声音或HP下降写成原生硬直已经实现。

## 双模板原生命中试验08

用户新增要求：MC命中随机采用普通轻击或特殊攻击的原生影响，两套模板全敌人共用。有效样本native-enemy-two-capture-08.json：普通Attack100/力动150/破甲75，特殊Attack300/力动450/破甲300；自然HP减量分别240和864，声音、特效及enemy execThirdDamage均观察到，零读取错误。复制使用游戏duplicate并保留独立runtime，不能从旧地址重建临时参数。此前get_offset错误导致的三击样本无效；已修正并说明。

只读反汇编确认目标实体stockDirectDamage会自行构建stock并加入StockDamage队列。两个GO为攻击者和攻击物体，目标来自被调用实体。calcDamage真实实现把FixedDamageAttack加入伤害后应用原生倍率/防御相关计算；固定数值不是最终对所有敌人保证扣除的数值。源码用反射ValueType构造Nullable，不依赖写入裸偏移。

onimusha_enemy_hit.lua是显式控制文件arm的单击试验：随机选两模板之一，clone设Attack0/FixedAttack=MC伤害×100，再走一次原生队列；生产适配器不额外写HP。任何入队异常均不重试，不回退直接HP；剩余预算耗尽拒绝额外攻击。10组专项和生产分派回归通过。当前两模板已经捕获，首次MC单击实景仍待用户结果，不声称反馈通过。

模板目前仅本次Lua会话有效；正式版仍需持久资产来源及场景重建。未做原生物理、图形资源或动画强制切换。

MOD制作：LCPD15/LCPD拉灯
