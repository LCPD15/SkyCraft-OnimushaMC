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

## MC 生物承伤：原始原因记录（接入结果见下方 2026-10-10 实现）

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

## 2026-10-10 13:53 实际命中补采与后续批量测试

用户重新启动游戏并在 MC 接管时受击。此前三次实际扣血为 160、160、360，
经 `cHealthManager.addHealth` → `send_hurt` → `SkyCombat.hurtPlayer` → `ServerPlayer.hurtServer`
结算，再回写原生血量 2000→1840→1680→1320，回读一致。

13:53:55 的专用探针实际命中记录已与健康日志对齐：

- frame=50241，`Em514_00` → `Player_00`，AttackUniqueID=77，HitID=42；
  HitInfo 与 cAttackRuntimeData 内的两个编号一致。
- 攻击碰撞体启用，类型为 `via.physics.ContinuousCapsuleShape`；已取得变换后 AABB，命中点在该包围盒内。
  这不代表已经取得完整胶囊形状或完成 MC 生物的精确相交判定。
- 同帧原生伤害 -213，以 maxHP=2000 换算为 MC 2.13 点；MC hurtServer 接受，下一帧原生血量
  1320→1107，回读一致。其他入站请求有 hurtServer=false，不能把所有入站请求计为实际扣血。
- 此时 HitInfo.AttackParamData 为空；AttackData 是 AttackParamEnemy，AttackRuntimeData 是 cAttackRuntimeData。
  尚未验证最终攻击参数的取得阶段，不得声称已得到可用于所有 MC 生物的完整伤害公式。

证据：`G:/Onimusha_MC_mod/logs/npc-hit-check-20261010-1337/` 下
`native-hit-capture.json`、`after-onimusha_mc_status.json`、`minecraft-after-capture.log`、`correlation.json`。
探针捕获后已自动停用，等待辅助进程已退出。没有修改生命值、执行攻击、重启游戏或接通 NPC 承伤。

用户要求减少零散测试。下一轮先把观察入口/返回阶段、伤害运行参数、精确变换形状、活动窗口、
原生与 MC 结算日志以及恢复状态统一采样并完成离线验证，再一次性发操作清单。
同一轮覆盖普通受击、格挡、连续命中、铁傀儡位于攻击范围内/外和 F10 恢复；
观察铁傀儡被攻击与让敌人主动以铁傀儡为目标仍需区分。
等待用户操作期间使用明确的墙钟等待窗口，实际采样再按事件数与持续时间限量；
不要仅用短帧数从“通知用户”时开始倒计时，导致实际操作之前到期。无需再为这条已捕获命中请求补测。

## 2026-10-10 凌晨收尾（后续已由用户重新启动）

MC 已通过自身主线程正常保存退出，然后关闭鬼武者；转换器随宿主退出。
三个对应进程均已确认结束，探针已停用，接管默认关闭。
完整世界备份 `G:/Onimusha_MC_mod/runtime/test-backups/after-dynamic-cache-20261010-043643`，
89 个文件逐项 SHA256 核对通过。没有修改背包、生命或经验数据。

## 2026-10-10 MC 生物承伤实现（protocol 16）

仅适用于上述鬼武者版本。新的第八个 payload `onimusha_npc_damage.lua` 读取敌人本体及武器子
ColliderSwitcher 中**已经注册**的攻击组；Enabled=true 本身不代表正处于攻击窗口。
忽略常驻的 gimmick-contact/action-break 组、死亡拥有者和指定原生目标的专用攻击。
通过 cAttackRuntimeData 的 AttackUniqueID 查当前 AttackParamSupporter.findAttackParamByKey；
真实 onHitAttackPreProcess 的只读反汇编确认查表键是 UniqueID，并非碰撞组编号。
敌人拥有的 AppShell 尝试走同一攻击组读取，参数来自当前 cShellAttackInfo.AttackParam。
玩家拥有的原生 TNT/爆炸 shell 排除，避免与 MC 已有爆炸承伤重复。

协议尾部新增独立、4096 条／每条192字节的宿主→MC 数值环，不改变原有区段偏移；
DLL/JAR 必须同时升级。传输当前／前一帧胶囊、球体或 OBB 的真实形状，附带攻击／命中编号、
伤害、连续命中间隔和上限。无 SDK 指针跨进程。MC 服务器先做范围筛选，再作胶囊距离／连续运动
判定或 OBB 的15轴相交判定；不会仅凭包围盒重叠算命中。未经支持的自定义形状直接跳过。

实际承伤对象为 MC LivingEntity，排除玩家及原生敌人的代理。每个目标独立去重；同一挥击的多个
碰撞形状和多个采样帧只算一次，多段攻击按原生 MultiHitTimer（秒）和 MaxCount 执行，仍尊重 MC
无敌帧。使用 LivingEntity.hurtServer 结算，MC 自身处理护甲、抗性、受击反馈、死亡及相关模组事件。
铁傀儡的原版击退抗性保留。F10、暂停、场景／epoch／连接变化、宿主死亡和资源重载均关门；
超过250ms的攻击丢弃，关闭映射或重新打开不会重放残留消息。

伤害单位：`当前原生攻击参数 Attack / 原生玩家最大血量 × 20`，然后由目标 MC 护甲／抗性减伤。
没有借用玩家这次实际受伤，也没有把它复制给附近生物；不继承原生玩家自身防御或其他原生结算
修正，因此**不是完整复刻鬼武者玩家的最终伤害公式**。REFramework 的100/500/1000/2000/5000
设置仍只影响 MC→原生敌人的输出伤害，不能反向放大生物承伤。

验证：

- 85 项 JVM 测试通过。新增真实 DLL/Lua API 校验、环满／非法数据／会话与关闭重开测试；
  Lua 导出器回归覆盖注册门控、所有支持形状、参数查表、shell 拥有者及玩家爆炸排除。
- 独立 MC 存档和独立 Windows 共享内存进程实测：每16ms重复发送同一挥击，铁傀儡只扣一次
  100→96；20护甲目标100→98.88，5米外目标不变；另一挥击96→92；关闭通道后不扣血；
  致死攻击正常死亡，玩家始终20。结果 `NPC_DAMAGE_SMOKE_RESULT passed=true`。
- 当前鬼武者内对正式导出器进行只读预检，9个胶囊／球体成功转换，实际原生参数读取得到结果；
  一个未初始化球体半径无效被拒绝。场景暂停且没有活动挥击，故没有发布伤害。
- 存档、进程、日志和安装收据统一在 `logs/npc-incoming-20261010/`，隔离测试没有修改用户原世界。

尚待实战验收：真实敌人挥击穿过铁傀儡的伤害／反馈，多段攻击和敌人 projectile/shell。
独立 MC 通道成功不等于这些原场景均已通过；短于采样窗口、特殊自定义形状可能漏判。
目前 shell 的 MC DamageSource 统一按 mob_attack 处理，不声明特殊元素／弹反／处决效果映射完成。
**敌人主动选择铁傀儡作为仇恨目标尚未实现**；测试时应让敌人的攻击轨迹经过铁傀儡。
同一轮集中测试范围内／外、连续两次挥击、玩家格挡与受击、F10恢复，不再逐项要求补采。
