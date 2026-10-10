# 第三方许可与来源 / Third-party licenses and provenance

- **SkyCraft** — chasmlol，MIT；[原仓库](https://github.com/chasmlol/SkyCraft)。保留根目录 LICENSE。Onimusha adaptation / MOD制作：LCPD15/LCPD拉灯。
- **REFramework API + Lua 5.4.3** — MIT；完整许可见源码 `onimusha/native/THIRD-PARTY-NOTICES.txt`，发布包 `third-party/native-NOTICES.txt`。REFramework 插件运行时本体由用户单独安装。
- **RE Mesh Editor 0.66** — NSA Cloud，[上游](https://github.com/NSACloud/RE-Mesh-Editor)，GPL；对应源码及 LICENSE.GPL 随独立转换器一起提供。该组件保留自己的许可，不属于根目录 MIT 授权范围。
- **texconv / DirectXTex and dependencies** — RE Mesh Editor 的 `modules/ddsconv/directx/THIRD_PARTY_LICENSES.txt` 保留完整许可。本包包含该已验证依赖树及 Windows 转换库。
- **Fabric API 0.161.0+26.3** — Apache-2.0；[源码](https://github.com/FabricMC/fabric)，其 JAR 内许可与副本随 MC 实例提供。Fabric Loader 由启动器正常获取。
- **RE-Engine-Lib** — [kagenocookie/RE-Engine-Lib](https://github.com/kagenocookie/RE-Engine-Lib)，MIT，仅用于生成／检查私有单位碰撞和 USER/PFB 模板；运行包不含 REE-Lib 二进制或游戏 schema。

Blender、Prism、Java、Minecraft、鬼武者和 REFramework 本体均未捆绑。由用户从各自来源安装，适用各自许可。
Blender, Prism, Java, Minecraft, Onimusha and the REFramework runtime are not redistributed in this package.

本包不含商业游戏模型、用户贴图缓存、用户存档、账号令牌或测试日志。私有 TEX 模板只含重新生成的单色 BC7 块；MDF 只提供中性材质参数并引用游戏本体的 shader。运行时生成的 MC 外观缓存保留在用户电脑，不上传到仓库。
No commercial game models, user appearance cache, saves, credentials or test logs are bundled. Generated appearance caches remain local.
