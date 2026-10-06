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

MOD制作：LCPD15/LCPD拉灯
