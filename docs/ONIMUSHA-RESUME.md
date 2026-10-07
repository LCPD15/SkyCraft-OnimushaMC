# 继续测试的停点 / Resume checkpoint

2026-10-07。仅适用于 OnimushaWotS 01.000.001 / TDB82 / REFramework b6baf6b406efc65e077b99cb4d9ad25b0a0a9095。其他 RE 游戏必须另行适配。

## 最新结果与下一步

用户已确认 MC 攻击有原生受击效果；修正通用命中范围后再次确认“扣血和反馈正常，暂时没有打不到的敌人”。不要再要求人工采集每种敌人或每招的模板。普通／特殊攻击两套全局资产随机选用，所有敌人共用入口。

第一轮原生反馈：8 次 native queue，execFirstDamage、execThirdDamage、applyHitEffect、applyHitSound 各匹配 8 次，目标包括 Em101_00 和 Em101_50；无手动 HP 补扣。第二轮通用受击范围：14 次 native queue，四个观察点各匹配 14 次；Em102_00（悬浮）、Em107_00、Em105_00 均成功扣血／反馈。用户视觉结果通过。日志 bounds-user-confirmed-* 和 native-feedback-confirmed-* 位于 logs/native-enemy-user-failure-20261007/。

第二轮另有 3 次 HIT_PROJECTILE 命中被旧 10 米试验距离拒绝，并非敌人类型过滤。现已改为近战 10 米、带 projectile/fire 标志的已结算命中 128 米（注册范围）；正常越界拒绝不再标记模块失败。新文件已自动重载到 generation 6 / id 5cb46f80c9e54a01b3728349e510c591，接管关闭，模块 ready=true、无错误。

**当前待用户回复：** 已请用户 F10 开启，在约十几个方块外用弓箭命中一次，随后回安全位置 F10 关闭，确认原角色／操作恢复。不要重复提出同一测试。收到回复后立即保存主适配器和 enemy_hit 状态，核对 native_distance > 10、native_range=128、queued_native 与实际 HP/反馈；再更新本停点。远程修正尚未标记实景通过。

## 自动重载与部署路径

用户已要求免手动 Reset。项目重载器已首次手动加载，此后 5 次自动重载通过（generation 2–6）。源 onimusha/adapter/onimusha_loader.lua 是唯一项目 autorun；4 个模块位于游戏 reframework/data/onimusha_mc/scripts/。**以后只更新这些 payload，不要重新创建旧 autorun，否则会重复装 hook。**

触发：G:/Onimusha_MC_mod/tools/Reload-OnimushaScripts.ps1。先确保用户在安全位置；重载自动关闭接管，等待输入／绘制／FOV 恢复、伤害队列和 hook 离开后切换。无须重新启动游戏或手动 Reset。状态在 onimusha_reload_status.json；匹配请求 id 且 phase=loaded 才是成功。loader 自身或 DLL 更新仍需全框架 Reset／重启，工具不是 REFramework 全局 Reset API。参考 ONIMUSHA-HOT-RELOAD.md。

旧 autorun 和 manifest 已保存在 runtime/test-backups/before-project-loader-20261007-162020/。最近两次 payload 备份 before-damage-bounds-20261007-165523、before-projectile-range-20261007-170137。只读 combat_inventory 控制已关闭。

## 实现边界

原先 Reset 清空临时模板，持久 trial 控制又引用不存在的 [1,2]，原生模块退出并回退直接 HP，造成“扣血但无反馈”。当前 production mode=enabled；从当前玩家拥有的 AttackParamData 解析稳定资产 ID 1/41，并校验 Attack/Rikido/Armor/flags/PercentageDamageType 指纹。每次 createRuntimeParam 生成独立原生参数，Attack=0、FixedAttack=MC伤害×100；目标实体 stockDirectDamage 长重载只调用一次，不额外入队／补扣 HP。任何失败均不能悄悄回退直接血量路径。无需重启后人工播种；热重载后的资产恢复已有实景证据，冷启动／切场景仍待覆盖。

代理范围读取实际 ColliderSwitcher.TYPE_DAMAGE=0 的活动 RequestSet、启用 collidable 的世界 AABB。RSC 的第一个参数是 group ID，不能传 group 索引。近处 32 格内使用有效受击范围的中心／底部；远处或读不到时回退 CharacterController 并明确记录来源。效果位置和距离校验也使用该范围。没有敌人名字白名单；所有已解析 EnemyCharacter/HealthManager 使用同一流程。当前仍为一个聚合 AABB、默认 BODY 部位，不能宣称已完成精确逐部位、装甲弱点、所有 Boss 阶段或全场景覆盖。

## 验证、文件与运行状态

20 个 Lua 回归脚本通过，日志 logs/lua-regression-reload-bounds-20261007.txt。此后仅 native_hit 距离分支变化，该专项 16 组通过。bounds 专项 5 组，reload 专项 10 组；离线检查不替代实景。DLL/JAR 本轮未变，不需用户重启。

- DLL SHA256：5291E47D62D33D9ED8B7B95A9B285256C02E509D18115AAA0F6F104401F44931。
- JAR SHA256：22004EBC1473787436FCD0205EE0A521133B34C8FA055FAF67815EFF40B99A5E。
- main Lua：D2C8CCEA7F689DD0BF0399D47776C09C1ACA987179B7368C6DB5CF4C9ECFB0CB。
- enemy Lua：8951D364F7A058139760708D4B5F897EAB817B3495DD745D4E77602AD728B449。
- 完整磁盘文件清单 runtime/deployment.json；磁盘 hash、加载回执和用户验收应分别记录。

项目 G:/Onimusha_MC_mod/source/SkyCraft，分支 onimusha-bridge，fork LCPD15/SkyCraft-OnimushaMC，未推送。用户 MC 目录 junction 指向工作根。游戏 F:/SteamLibrary/steamapps/common/OnimushaWotS。MC 世界 OnimushaMC-XYZ-v2，启动含 SwordBlocking / StartHidden / QuitWithHost。上次 PID 游戏34456 / Java94796；操作前核实实际路径，禁止仅凭旧 PID 杀进程。电脑自动输入保持停止，真实游戏操作由用户完成。

## 仍未完成

3C、F5、背包鼠标、持续移动无闪回、原生场景 UI 转向跟随、F10 恢复、方块站立／拆除、百分比 HP 和 MC 道具双向治疗已通过。用户确认格挡无掉血且有声音、正常受伤掉血；红闪／击退／火花未逐项确认。4×64 普通金苹果已发放且用户确认，不要重复添加。

原生 NPC 对 MC 方块的碰撞／寻路、真实 RE 深度／光照、处决仍未实现；实验原生 Collider 创建保持关闭。当前 MC 渲染使用私有几何深度，不能声称已进入原生光照。敌人致死奖励、破甲、特殊不可防御／弹反和跨会话事务 ACK 仍待覆盖。候选透明 DLL FC445 从未安装。

MOD制作：LCPD15/LCPD拉灯
