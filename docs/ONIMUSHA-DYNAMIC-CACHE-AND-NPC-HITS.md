# 动态缓存与 MC 生物承伤检查

2026-10-10。仅适用于 OnimushaWotS 01.000.001 / TDB82，协议 15。
MOD制作：LCPD15/LCPD拉灯。

## 动态缓存：修正已安装

磁盘转换缓存原本已存在，目录为 `G:/Onimusha_MC_mod/assets/native-models/live/cache-v2`。
本次现场转换器的 jobs=6881、built=4247、cache_hits=1356；同一外观在复测期间未增加转换任务。
动态贴图按资源 Identifier 分配稳定 ID，规则矩形面先归一化再缓存；姿态、均匀受击颜色不进入几何缓存键。

实际反复等待的原因是 Lua 在 F10 关闭或实体消失时销毁了已经加载的 Mesh 实例。
资源 holder 虽然仍在，下一次却要按每帧最多 2 个部件重新创建对象。

现在关闭接管或部件消失时，已完成加载的动态对象隐藏并进入实例池。
按绘制流（身体、手持、场景生物）和外观 ID 复用，恢复时应用当前姿态、颜色和闪白状态，重新确认绘制回执。
新外观仍按原有小批量加载；不会把未加载的新对象冒充为就绪。
池与活动对象共同受数量上限约束，满时淘汰最旧闲置项。
原生场景、epoch、世界、MC 进程或连接 generation 改变时不复用旧场景对象；脚本重载也完整销毁。

验证分为两层：

- 真实进程：56 个手部／手持部件加载后，关闭接管得到 pool=56、active=0；重新接管 pool_hits=56、ready=56，created 仍为 56、removed 仍为 0，无资源错误。原生健康、位置与场景不变。
- 实际 Lua 的 SDK 模拟：50 个身体／NPC 面在一帧内恢复，零创建、零重绑定、零转换；实体移除再创建、列表偏移、场景改变、对象失效与重载清理均覆盖。连同既有材质、TNT 闪白、姿态、加载与清理，共 11 个回归脚本通过。

证据在 `G:/Onimusha_MC_mod/logs/dynamic-pool-npc-20261010/`：
`pool-live-warm.json`、`pool-live-off.json`、`pool-live-resume.json`。
身体／铁傀儡的真实再生成视觉效果尚未由用户复测；不能把模拟测试写成全部实体的实战验收。
首次见到新外观、超出池上限、重启游戏或切换原生场景时，仍需要创建 GPU 对象；磁盘缓存不能保存活的 GPU 对象。

## MC 生物承伤：原因已确认，功能尚未接通

现有原生承伤路径只匹配当前玩家的 `app.cPlayerApplyDamage` 和 `app.cHealthManager`，
随后 `send_hurt` → `IN_HURT` → `SkyCombat.hurtPlayer` → `ServerPlayer.hurtServer`。
铁傀儡等 MC 生物没有注册为原生受击对象，也没有单独的入站命中消息。
它们主动攻击原生敌人走的是另一条已存在的输出路径，不能据此判断反向承伤已经完成。
MC 世界实体导出目前主要服务绘制，其中的 shadow 记录不含完整受击体积、生命状态和会话身份。

已从当前游戏读取到通用接口，不需要逐敌人／逐招制作映射：

| 内容 | 当前游戏接口／字段 |
| --- | --- |
| 原生命中通知 | `app.HitController.notifyHitProc(app.HitInfo)` |
| 攻击者、受击者、原生攻击参数 | `HitInfo.AttackCharacter / AttackOwner / DamageOwner / AttackParamData` |
| 攻击实例去重 | `HitInfo.AttackUniqueID / HitID`，运行数据 `cAttackRuntimeData` |
| 活动攻击与碰撞开关 | `cCharacterAttackInfoSupporter.IsAttackCollisionOn / _AttackCollisionIdEnabled` |
| 攻击碰撞体 | `ColliderSwitcher` 的 `RequestSetCollider`、`AttackColliderInfo`、`Collidable.get_TransformedShape()` |
| 攻击类型与连击间隔 | `cAttackRuntimeParamBase.Attack / MultiHitTimer` 及原始参数 |

这些类型的存在不等于命中与伤害换算已经验证。特别是不能把包围盒重叠直接当成精确攻击命中，
不能将玩家本次扣血复制给附近的 MC 生物，也不能把参数中的 Attack 直接冒充完整的原生结算结果。

当前安全场景 `stage:20:area:78` 的 EnemyCharacter 数量为 0，未采集到有效敌人攻击。
已增加只读、默认关闭、限时限量的 NPC 命中探针；真实游戏中安装和自动到期通过，无异常。
该探针不创建碰撞体、不施加伤害、不回放攻击、不修改原生调用结果、不保存可供回放的原生指针。

下次在有普通敌人的场景，保持接管关闭，短时启用：

```json
{"enabled":true,"id":"npc-natural-hit-unique-id","max_frames":1800,"max_events":64}
```

写入 `reframework/data/onimusha_npc_hit_probe_control.json`，用原角色自然受击一次。
输出 `onimusha_npc_hit_probe_status.json`；可随时设 enabled=false，重复同一 id 不会重新采样。
探针由现有项目重载器承载，不需要新增 autorun 或手工 Reset。

下一步实现需要：验证真实攻击实例与活动碰撞范围的对应关系；把 MC 生物的实际受击体积和会话身份接入；
对重叠目标通过集成服务器 `LivingEntity.hurtServer` 结算，让 MC 自己处理护甲、无敌帧、红闪、击退与死亡。
需要覆盖每个目标的命中去重、多段攻击、过期消息、无效／已死亡实体、玩家排除以及世界切换。
敌人主动把 MC 生物选为仇恨目标是另一项 AI 接入工作，本次未实现。

## 收尾

MC 已通过自身主线程正常保存退出，然后关闭鬼武者；转换器随宿主退出。
三个对应进程均已确认结束，探针已停用，接管默认关闭。
完整世界备份 `G:/Onimusha_MC_mod/runtime/test-backups/after-dynamic-cache-20261010-043643`，
89 个文件逐项 SHA256 核对通过。没有修改背包、生命或经验数据。
