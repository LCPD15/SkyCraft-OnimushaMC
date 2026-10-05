# 继续测试的停点 / Resume checkpoint

保存时间：2026-10-06。仅适用于本地鬼武者 `OnimushaWotS` 01.000.001、TDB 82，以及固定 REFramework 提交 `b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。

用户授权自行测试，并要求工具无法控制时停下等待。当前已按该要求停止实景操作。游戏 PID 49912 与隔离 MC PID 111500 已正常退出，MC 自动保存。游戏安装配置为只读阶段 A、enabled=false，控制钩子、地形查询、新增原生碰撞对象及血量修改测试均关闭。用户现有游戏文件、其他角色 MOD、账号和原 PCL 安装未被替换。

The user authorized autonomous testing until computer control became unreliable. Testing is now stopped. The host and isolated Minecraft client exited normally; Minecraft saved its world. The installed configuration selects read-only stage A with takeover, hooks, terrain queries and experimental tests disabled.

## 保存的内容 / Saved work

- 工作根目录：`G:\Onimusha_MC_mod`；用户指定 MC 目录中的 `Onimusha_MC_mod` 是指向此处的 junction。
- 源码：`source/SkyCraft`，分支 `onimusha-bridge`。上游与 fork remote 均保留。
- 编译文件及开发包：`dist/`；安装追踪：`runtime/deployment.json`。
- 最后实景日志：`logs/game-cursor-events-20261006/` 及 `logs/game-client-cursor-events-20261006.stdout.log`。
- 测试后世界备份：`runtime/minecraft/test-world-backups/OnimushaMC-after-autonomous-20261006`，28 个文件 SHA256 全部一致。测试前世界备份仍保留。

## 通过与未通过 / Evidence boundary

实景通过：场景正常加载、地形读取 9,822 三角形、HUD/剑盾显示、原角色隐藏、首次 yaw/pitch 同步、普通 F10 关闭后原角色及 FOV 恢复；输入 123 字段写回并回读成功。Fabric 43 项测试通过；原生 IPC/GPU/API 专项和 Lua 回归已执行。

未通过：背包第一格点击被本体居中成第五格。完整视角控制、持续行走、游戏敌人战斗、心形血量的实景伤害往返、方块建造拆除及碰撞、菜单/过场/场景切换恢复均未完整验收。新增原生实体方块碰撞保持实验停用。不能将 mock host、合成 GPU 帧或代码实现当作游戏验收。

Live evidence covers loading, rendering, initial rotation and ordinary release. Inventory clicks remain unresolved, and full movement/camera/combat/building acceptance is pending. Experimental native block collider allocation stays disabled.

## 下次继续 / Next session

1. 先验证最新 Lua 的失败恢复重试及 DLL 的单次 WM_INPUT 清理补丁；这两项保存后的修正尚无实景结果。
2. 在 MC GUI 打开/关闭时只读探查本体 cursor-lock、GUI/相对输入状态及消息来源，找到可验证的释放绑定后再修改。不要把所有中心点击都改成旧位置。
3. 用真实鼠标或支持相对移动、持续按键的工具验证3C。当前 Sky接口仅短按和绝对位置操作，不能据此判定真实鼠标路径成功或失败。
4. 保留原游戏存档和隔离 MC 世界备份，再依次测试普通敌人、血量百分比、建造/拆除及场景转换。敌人目前只枚举当前场景；输入对象运行中替换也仍需专门证据。

Retest the post-run restoration/WM_INPUT changes first. Investigate the native cursor-lock state without guessing coordinates, then validate relative mouse and sustained keys before combat, health and building tests. Preserve both host and isolated Minecraft saves.

MOD制作：LCPD15/LCPD拉灯
