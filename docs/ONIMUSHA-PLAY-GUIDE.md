# 鬼武者 × Minecraft 启动与操作

适用当前电脑上的 OnimushaWotS 桥接安装，更新于 2026-10-10。
MOD制作：LCPD15/LCPD拉灯。

## 日常启动

1. 启动鬼武者，进入可操作的游戏场景，先保持 F10 接管关闭。
2. 双击 `G:\游戏MOD\0_自己做的Mod\鬼武者\MC\启动并连接MC.cmd`。
3. 等启动窗口显示 `Connected`，切回鬼武者，关闭暂停菜单，按 F10 开始 MC 接管。再次按 F10 恢复原游戏。

该入口自动打开当前 MC 世界 `OnimushaMC-XYZ-v2`，并启动模型转换器；无需另开服务器或填写 IP。
MC 已在运行时会复用它，重复双击不会再开一个实例。英文目录里的等效入口是
`G:\Onimusha_MC_mod\Start-OnimushaMC.cmd`。

MC 窗口保持可见，可以预览 MC 方块、实体、手持物与界面；鬼武者场景地形不会在 MC 窗口里绘制。
游玩与聊天输入仍在鬼武者窗口中完成，MC 窗口用于预览；连接后直接点击 MC 窗口不会操作角色。
可见预览与发给鬼武者的透明界面分开绘制，因此 MC 的天空不会盖住鬼武者场景。
这条快捷入口使用现有本地开发测试档 LCPD15，不负责微软账号登录或在线多人认证。
若改用 PCL 的正版账号入口，需要另行配置桥接启动参数和玩家身份，不能保证直接沿用当前背包。

## 常用操作

| 操作 | 按键 |
| --- | --- |
| 开启／关闭接管 | F10 |
| MC 背包 | E |
| MC 聊天／命令 | T ／ / |
| 第一、第三人称切换 | F5 |
| 吸魂 | 按住 C，或按住右键 |
| 打开 REFramework | Insert |

聊天中输入 `/gamemode creative` 切创造，输入 `/gamemode survival` 切生存。
`/gamemode adventure` 是冒险模式：普通方块不能放置或拆除，但吃东西、拉弓仍可用。
出现“创造能放、生存似乎不能放”时，先确认实际没有切到 Adventure；此次存档正是这种情况，已恢复 Survival。
关闭 MC 聊天／背包后可操作原游戏菜单；要退出时先按 F10 关闭接管，再正常退出鬼武者。
此入口启用了随宿主退出，MC 会正常保存并退出，请等 Java 进程结束再改存档或安装其他 MOD。

伤害设置在 REFramework → Script Generated UI → Onimusha MC / 鬼武者 MC → Damage / 伤害设置。
五档为 100／500／1000／2000／5000；100 是当前换算基准，500 是它的五倍，不是再乘 500 倍。

## 添加其他 MC MOD

当前实例为 Minecraft **26.3**、Fabric Loader **0.19.5**、Fabric API **0.161.0+26.3**、Java **25**。
MOD 文件夹：`G:\Onimusha_MC_mod\runtime\minecraft\.minecraft\mods`。
世界文件夹：`G:\Onimusha_MC_mod\runtime\minecraft\.minecraft\saves\OnimushaMC-XYZ-v2`。

关闭 MC、备份世界后，放入明确支持 MC 26.3 / Fabric 的 MOD 与其必要依赖，再用同一快捷入口启动。
不要替换现有 `skycraft-onimusha-0.1.0-dev.jar`，也不要把 ATM9 的 Forge MOD 直接放入此实例。

能被 Fabric 加载，不等于所有内容都能完整桥接。目前自动转换覆盖普通方块模型、常规物品与一部分实体／方块实体渲染。
新增配方、普通物品和标准模型方块可以逐个测试；使用特殊渲染、流体、动画贴图、活动机械或独立伤害系统的 MOD 需要额外检查。
鬼武者中的遮挡、光照、敌人碰撞与伤害属于额外同步能力，不能由 MC 内正常运行推断其全部兼容。
部分无法转换的材质会保留 MC 绘制效果。

机械动力目前不能直接装入本实例。本次查到的 [Create Fabric 发布页](https://modrinth.com/mod/create-fabric/versions)
列出 MC 1.20.1／1.19.2／1.18.2；[Create 官方发布页](https://github.com/Creators-of-Create/Create/releases)
列出的新版本对应 MC 1.21.1，其 [加载器声明](https://github.com/Creators-of-Create/Create/blob/mc1.21.1/dev/src/main/templates/META-INF/neoforge.mods.toml)
要求 NeoForge。未找到可直接用于本实例的 MC 26.3 Fabric 版本。

根据当前导出器代码，即使未来有匹配版本，机械动力的特殊绘制、运动装置／列车和它们对鬼武者角色的碰撞
仍需单独适配和实测，不能承诺自动兼容。本次没有安装 Create，也没有修改 MC 版本或现有世界。

## 无法连接时

确认鬼武者已进场景、REFramework 正常加载；先不要重复启动多个 MC。
启动窗口会显示异常，日志在 `G:\Onimusha_MC_mod\logs`，手动启动日志前缀为 `manual-`。
如果显示 MC 已连接但 F10 未生效，先关闭鬼武者暂停菜单，回到可操作场景再试。
