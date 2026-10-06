# MC 伤害换算与平衡 / Minecraft damage balance

2026-10-07，仅适用于本地 OnimushaWotS 01.000.001 / TDB82。此文区分已实施倍率、离线验证和后续方案。其他 RE 游戏必须建立独立伤害与动作适配，不能照搬数值。

## 已实施：当前伤害的十倍

用户要求把当前 MC 对敌人的伤害提升到原先的十倍。配置 `enemy_host_damage_per_mc_point` 从 **10.0 改为 100.0**，Lua 默认值与四份源配置一致；游戏目录中的配置也只修改了这一项，保留 stage C、接管关闭和实验碰撞／血量测试关闭。

当前普通命中的换算为：

```text
native damage = clamp(MC event damage, 0, 1000) × 100
new HP = clamp(floor(current HP - native damage + 0.5), 0, maximum HP)
```

原先 7 点 MC 伤害扣 70 原生 HP，现在扣 700，是十倍。MC 暴击、攻击冷却、附魔等已经进入事件伤害 `a`，不能再按暴击标志重复乘一次。当前代理把同 tick 命中合并后转发；这个事件不是完整的原生 HitInfo，亦不能当作已具备一击一事务的处决协议。

玩家受伤、MC 道具治疗和爱心仍按原生最大 HP 百分比往返，**没有乘这个敌人伤害倍率**。这避免把此次增强变成敌人攻击十倍或食物治疗十倍。

本次离线生产 Lua 回归覆盖：7→700 一次写入；旧倍率10与新100恰好十倍；浮点整数边界；零／负值／无效目标无写入；过量伤害夹到0并调用一次 `checkHealthZero`；原玩家受伤／治疗换算保持原逻辑。最终 BC6A 全部15文件／126组通过，含额外相机回滚回归。新倍率在游戏内的实测留到下次启动，不能从测试夹具推导原生死亡、产魂、破甲或任务奖励已经完成。

**English implementation:** Enemy damage scaling is now 100 native HP per Minecraft damage point, previously 10. This is exactly a tenfold increase. Minecraft critical/cooldown/enchantment adjustments are already in the event amount. Player hurt, healing and heart percentages are unchanged. Offline tests pass; new in-game balance and death/reward behavior remain pending.

## 为什么固定倍率仍可能不合适

已有日志里出现最大 HP 1095 和 3900 的目标。仅作数值示例，同样 7 点 MC 伤害的占比如下；这不是对当前手持武器、所有敌人或 Boss 的实测伤害承诺。

| 记录中的最大 HP | 旧换算70 HP | 新换算700 HP |
|---|---:|---:|
| 1095 | 6.39% | 63.93% |
| 3900 | 1.79% | 17.95% |

固定倍率保持武器差异，实施简单，但不同章节、难度、小怪、精英和 Boss 的 HP 池差异会放大平衡问题。统一让每击扣目标固定百分比也不合适：可能让大 Boss 与普通小怪同样三击死亡，削弱武器成长与敌人耐久差异。不能因为玩家爱心采用百分比，就把对敌伤害也机械改成统一百分比。

## 更合适的三条路线

| 路线 | 换算方式 | 优点与需要验证的边界 |
|---|---|---|
| 固定100，按敌人类别作少量校准 | `MC amount × class scale` | 保留当前已可用路线；先测同武器普通／精英／Boss 的击杀次数，再建立版本与难度明确的小表。没有可靠类别时回退100，不能靠名字猜 Boss |
| 给每类敌人一个 MC 等效耐久 | `MC amount / reference MC HP × native max HP` | 可以表达普通、精英和 Boss 的不同耐久。reference MC HP 是调参目标，不是当前代理的实际生命。不得统一reference，否则所有类型同击杀次数；满血上限变化／阶段切换需要重新认证 |
| 进入真实原生命中流水线 | 合法原生攻击参数与 MC 修正伤害在一个结算点结合 | 才能处理真实受击、力动、破甲、声音、特效及奖励；需要先确认所有者、HitInfo／ApplyParam 初始化和同次伤害生命期。不能把当前直接减血与原生命中同时保留 |

上游 SkyCraft 用 Skyrim 等级公式 `5 + 0.25 × actor level`，再通过认证的 AE `HitData/processHit` 路线。鬼武者未验证一个语义相同的 actor level；不能复制这条等级公式或 Skyrim 的内存布局。使用真实难度／敌人参数须先读到有效字段，不能借匿名序列化字段冒充运行时数值。

推荐先保留用户要求的100，按实际普通敌人和 Boss 测出击杀次数，随后采用类别等效耐久或少量类别倍率。原生命中派发是并行研究的机制问题，不应因为它还未确认而回退此次明确要求的十倍伤害。

## 数值与原生机制必须各算一次

MC 的 `a` 已含自己的修正，未来若再走原生攻击参数，需明确原生防御、难度、部位、暴击与武器成长哪些适用；不能在两边重复应用同一护甲或暴击。也不能为了产生受击反馈再调用会扣血的原生入口。

普通命中、持续伤害、范围伤害、破甲和处决应分别拥有可认证的来源、当前会话、目标身份及结算标识。原协议 EV1 目前没有完整 epoch／命中事务确认；代理会话标记候选减少旧代理残留，却不能证明宿主事件已经完全防重。升级结算时需要接收／结算回执和去重，不能用“成功入队”代替敌人已正确处理。

处决更应采用一套权威：若执行完整原生动作，以其真实命中帧结算为准，同一次事务不要再追加普通 MC 的700 HP；若将来选择 MC 数值驱动，则须精确识别并替换原生同次扣血，不能全局拦截所有原生伤害。具体动作与动画方案见[处决研究](ONIMUSHA-EXECUTION-RESEARCH.md)，伤害入口见[受击研究](ONIMUSHA-COMBAT-RESEARCH.md)。

下次最小验证先用同武器、尽量同样蓄力／冷却条件，对可重复普通目标记录一次攻击前后 HP 与击杀次数；致死时另核对死亡、奖励及 F10 恢复。原生动作样本与格挡样本在接管关闭时单独记录，不能用单纯 HP 下降验证全部机制。

**English recommendation:** Keep the requested scale100 initially, then calibrate ordinary/elite/boss durability from repeatable observations. A class-specific equivalent MC health can normalize large native HP pools without making every boss a three-hit enemy. Native hit dispatch is a separate, ownership-sensitive integration task. Maintain one authority and one settlement for each hit or finisher; do not apply Minecraft criticals, native damage or effects twice.

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯. Based on SkyCraft by chasmlol; retain the upstream MIT license.
