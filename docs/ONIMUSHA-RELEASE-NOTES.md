# 0.2.0 — 独立发布版 / Standalone release

MOD制作：LCPD15/LCPD拉灯

基于用户确认可用的当前版本制作。包含原生光照／遮挡、碰撞、战斗、爆炸、吸魂、MC 生物承伤、中文可见 MC 窗口、聊天输入隔离及死亡恢复。
Built from the working version confirmed by the user, including native rendering, collision, combat, explosions, souls, MC mob damage, Chinese visible-window startup, chat isolation and death recovery.

## 本次整理 / Packaging changes

- 全新的独立安装／连接／卸载入口，路径通过设置提供；安装记录、文件哈希校验及恢复备份。
- 完整打包原生显示、碰撞和后台转换需要的资源与依赖；不再使用早期只读阶段 A 配置。
- 可导入 Prism 的 Minecraft 26.3 + Fabric 配置，默认中文、可见窗口；Minecraft 由用户账户及启动器正常下载。
- 附中英双语 MOD 说明、构建、使用和第三方许可，源码与二进制在同一 GitHub Release 发布。

Portable install/connect/uninstall entry points, complete runtime dependencies, a Chinese visible-window Prism profile and bilingual documentation. Existing installations are not modified by the packaging operation itself.

## 最近修复 / Recent fixes included

反复 F10 接管时复用稳定的外观编号，限制闲置资源缓存、并发转换和读取队列，避免历史请求不断累积拖慢帧率或令转换停止。新纹理会正确失效对应模型，不把旧 atlas 当新资源。动态模型缓存跨连接保留，活动对象和原生碰撞仍按场景清理。
Repeated takeover reuses appearance IDs and bounded resource caches. Queue discovery no longer scans all history or stops at a lifetime request count. Texture changes invalidate the correct models; scene objects/collisions retain proper cleanup.

原有回归覆盖包括 1000 次接管生命周期模拟、超过 8192 次转换请求及原生／JVM／Lua 测试。它们是隔离测试，不等同于所有硬件或所有游戏场景的帧率保证。本次发布另验证解压安装、重复安装、卸载恢复、包内模型转换及文件一致性。
Prior isolated regression tests cover repeated takeover and large request counts; they are not universal FPS guarantees. Release validation additionally covers installation, reinstall/uninstall, converter dependencies and archive integrity.

限制见 README；不承诺机械动力或任意 MC 模组、其他 RE 引擎游戏、联网及全套处决系统可用。
See README for compatibility boundaries. No universal third-party mod, other RE game, multiplayer or execution-system support is claimed.
