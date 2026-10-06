# 夜间工作与研究入口 / Overnight work and research

2026-10-07。仅适用于本地鬼武者 OnimushaWotS 01.000.001 / TDB82，其他 RE 引擎游戏需要独立适配。用户已休息，今晚不要求 Reset Scripts、F10、受击或重启操作；自动电脑输入保持停止。游戏与 MC 已正常退出，测试世界及鬼武者存档已做逐文件校验备份。

## 本次交付与证据边界

| 工作 | 完成的内容 | 尚未完成／需真实场景验证 |
|---|---|---|
| 原生血条／图标转向 | 被动时序记录定位到 `app.CameraManager.lateUpdate` 结束时覆写相机；候选在认证 owner、会话、相机就绪后重放相机，并记录失败回滚 | 上个实测版本转向仍失败；新候选不能写成已修复 UI。当前身份与测试数见[停点记录](ONIMUSHA-RESUME.md) |
| 敌人伤害十倍 | 配置10→100，只影响 MC 对敌伤害；原玩家百分比爱心与治疗不变 | 新伤害平衡、致死／奖励及原生受击效果 |
| 光照与遮挡 | 核对上游真实 scene depth/HDR／灯光路线，列鬼武者资源、状态、渲染阶段和原生 Mesh/MDF 两条接入路径 | 真实 RE depth、灯光、阴影和后处理尚未接入；透明 pass 候选只改善 MC 内部遮挡 |
| 原生角色碰撞与寻路 | 区分 MC 碰撞、原生 character contacts/filter 和 AI 绕路，列注册／卸载／移除的身份与生命周期验证 | 原生单位 RCOL 注册仍未通过；导航动态障碍／敌人请求接口未找到完整证据，实验 allocator 保持关闭 |
| 更合适的伤害 | 比较固定倍率、分类等效耐久和真实原生命中；说明暴击、护甲及动作结算不得重复 | 根据可重复普通／精英／Boss 样本校准；有效原生命中参数构造 |
| 处决／一闪动画 | 核对原生动作、目标、grapple、命中帧、力动、相机与吸魂候选；设计唯一伤害事务和 MC 动画同步 | 具体动作自然样本、合法请求、隐藏原角色时的 MC 动画与安全归还 |
| 盾／剑格挡 | MC 剑组件、真实 blocked amount 观测和去重粒子候选；原生 guard 与声音／特效入口调查 | 候选未部署；可选剑能力默认关闭，受控命中的盾观测独立。可信攻击方向、原生反馈及零伤害结算回执尚缺 |

今晚新增研究文档没有主动调用游戏动作、创建原生对象或新增运行中探针。静态接口存在、编译通过与测试夹具通过都不能替代游戏验收。

## 完整研究文件

- [光照、深度与渲染接入](ONIMUSHA-RENDER-RESEARCH.md)：真实深度只读消费、HDR 前 pass、合法 Mesh/MDF、灯光采样四条路线与最小实验。
- [碰撞与寻路](ONIMUSHA-COLLISION-PATH-RESEARCH.md)：碰撞注册、角色接触、导航绕路、拆除与场景变化，含原 SkyCraft 三层机制区别。
- [伤害换算与平衡](ONIMUSHA-DAMAGE-BALANCE.md)：已实施100倍率，后续分类耐久方案与一击一次原则。
- [处决、动作与伤害](ONIMUSHA-EXECUTION-RESEARCH.md)：真实签名、动作／目标身份、原生权威结算和 MC 动画方案。
- [格挡](ONIMUSHA-GUARD-RESEARCH.md)：默认盾方向／延迟、剑能力、原生 guard 观察与结算缺口。
- [原生受击流程](ONIMUSHA-COMBAT-RESEARCH.md)：当前直接改 HP 与完整命中流水线的差别。

## 明天的验证顺序

先验证已经安装的相机 Lua 与伤害配置，保持现有已测 DLL/JAR，减少变量：启动进入场景、连接原测试世界，在安全处测试转视角时任务图标／血条是否跟随，再测试 F10 恢复。新倍率使用同武器普通目标比较 HP 变化；不要把有伤害与有受击反馈合为一个结论。

之后按需安装独立 Java／透明绘制候选。格挡需要 F10 关闭时的一次自然原生正面格挡与普通受击，处决需用户所指动作的自然样本；探针应先编写并完成离线检查，再另行提出具体操作，不让用户凭文档反复无目的受击。碰撞／真实渲染融合先取得有效对象或资源证据，继续停用此前未通过的创建路径。

详细文件哈希、已安装与未部署的区别、备份和真实通过项见[停点记录](ONIMUSHA-RESUME.md)与[验证表](ONIMUSHA-VALIDATION.md)。研究结果属于下一步的具体实施依据，不代表完整互通 MOD 已经完成。

**English checkpoint:** The user is asleep; no manual actions or computer automation are requested tonight. Damage scaling is changed10→100, with player heart/healing percentages unchanged. Camera replay and independent Java/render candidates have offline evidence, while live UI, native hit/guard/finisher behavior, true scene lighting/depth and NPC collision/pathing remain distinct acceptance tasks. Read the linked research and the exact installed/candidate identities before resuming.

MOD制作：LCPD15/LCPD拉灯

Mod by: LCPD15 / LCPD拉灯. Based on chasmlol's SkyCraft; retain the upstream MIT license.
