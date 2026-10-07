# 鬼武者 MC 项目脚本重载 / Project script hot reload

只适用于当前 OnimushaWotS / TDB82。此功能热更新本项目的 Lua 模块，不能调用 REFramework 的全局 Reset Scripts。固定框架版本的 ScriptRunner::reset_scripts 是私有 C++ 实现，没有可调用的 Lua 重置入口。没有键鼠模拟、DLL 注入或私有地址补丁。

## 安装与使用

唯一项目 autorun：`reframework/autorun/onimusha_loader.lua`。

载荷目录：`reframework/data/onimusha_mc/scripts/`，含 onimusha_mc.lua、onimusha_enemy_hit.lua、onimusha_guard_probe.lua、onimusha_combat_inventory.lua。旧同名 autorun 迁移到项目备份。首次安装 loader 需手动 Reset 或重启；此后更新载荷不需要。loader 自身不在载荷列表内。

用户在安全处停手后，先备份、检查语法／回归，再原子替换 payload，执行：

```powershell
& 'G:\Onimusha_MC_mod\tools\Reload-OnimushaScripts.ps1'
```

工具写一次带唯一 id 的 `onimusha_reload_control.json`，轮询同 id 的 `onimusha_reload_status.json`。`phase=loaded` 才确认已切换；超时不可直接重发，先读取状态。不得在用户战斗中突然自动关闭接管。

## 生命周期

- 请求先落盘 receipt，框架重置／重启后不会重复执行旧请求。
- 关闭接管，等适配器恢复原输入、绘制和 FOV；pending native damage 清空、hook inflight=0，连续三帧安静才更换模块。600 帧仍未满足条件则报告失败。
- 所有新载荷先编译。语法错误保留旧模块；初始化错误清理新模块并恢复上一份可用代码；清理失败停止切换并报告，不能假装成功。
- 每个 RE 回调和原生函数地址只安装一个固定路由，热重载仅切换当前代的 Lua handler。pre/post 保留同一次调用的代次；SKIP_ORIGINAL 和返回值按实际模块保留。不会每次重载追加一套伤害或输入 hook。
- 只读 inventory 探针默认应停用；需要时用独立新 id，且保持接管关闭。

## 已验证与限制

reload_regression.py 实际执行 loader，覆盖 20 次重载不累计 hook、在途回调／伤害等待、恢复门槛、编译失败保留、初始化回滚、清理失败及持久 id；10 组通过。实景首次 Reset 后已连续自动重载到 generation 6，原生伤害资产可重新解析并继续命中。

这不是 DLL/JAR 热替换工具，不会修改 MC 世界或游戏存档。日志中的 loaded 只证明模块加载成功；新的玩法改动仍需单独验收。其他插件和它们的全局 Reset 需求不在此机制范围内。

MOD制作：LCPD15/LCPD拉灯
