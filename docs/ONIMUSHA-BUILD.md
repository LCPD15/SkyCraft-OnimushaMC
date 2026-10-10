# 构建说明 / Build instructions

**MOD制作：LCPD15/LCPD拉灯**。以下从本仓库根目录运行，仅构建鬼武者分支，不构建原 SkyCraft 的 Skyrim/SKSE 插件。
Run commands from this repository's root. These build the Onimusha adapter, not the original Skyrim plugin.

## 工具链 / Toolchain

Windows x64；Visual Studio 2022 Build Tools（MSVC C++、Windows SDK）；CMake ≥3.24；Java JDK 25；Python 3.10+。转换验证额外需要 Blender 5.2。Gradle Wrapper 固定 9.7.1。

Minecraft 26.3、Fabric Loader 0.19.5、Fabric API 0.161.0+26.3 由 `fabric/gradle.properties` 定义；Loom 当前固定入口为 `1.18-SNAPSHOT`（上游快照依赖可能变化，不能承诺将来字节级可重复构建）。REFramework API 头和 Lua 源码已随仓库固定，REFramework API 修订为 `b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`。
Dependencies are pinned in the project except the documented Loom snapshot. The published checksum manifest identifies the exact release binaries; future rebuilds are not promised byte-identical.

## 编译与测试 / Compile and test

```powershell
$env:JAVA_HOME='C:\Path\To\jdk-25'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
Push-Location fabric
.\gradlew.bat test build
if ($LASTEXITCODE) { throw 'Fabric build failed' }
Pop-Location
cmake -S onimusha -B onimusha/build -A x64
cmake --build onimusha/build --config Release
ctest --test-dir onimusha/build -C Release --output-on-failure
```

输出 / Outputs:
- `onimusha/build/Release/OnimushaMC.dll`
- `fabric/build/libs/skycraft-onimusha-0.2.0.jar`

原生测试会创建自己的共享内存／离屏渲染环境。不要把测试程序当游戏插件安装。主程序、DLL 和 MC JAR 必须使用同一协议版本（本版 16）。
Native tests use isolated bridge/rendering contexts. Install only the plugin and matching MC JAR, not smoke-test executables. This release uses protocol 16.

## 打包 / Package

准备官方 Fabric API 0.161.0+26.3 JAR：[固定下载](https://cdn.modrinth.com/data/P7dR8mSH/versions/bNnaTiuM/fabric-api-0.161.0%2B26.3.jar)。打包器会检查固定 SHA-512，不接受任意同名文件。源码自带 RE Mesh Editor 0.66 快照和许可、独立碰撞与加载模板；不需要作者电脑上的工具目录。
Obtain the pinned Fabric API JAR above. The packager checks its SHA-512. Converter source, license notices and authored format templates are included in this repository.

```powershell
python onimusha/release/Build-PublicPackage.py --native-dll onimusha/build/Release/OnimushaMC.dll --fabric-jar fabric/build/libs/skycraft-onimusha-0.2.0.jar --fabric-api C:/Downloads/fabric-api-0.161.0+26.3.jar --output dist/v0.2.0
```

正式打包要求 Git 工作区干净，生成独立游戏安装包、Prism MC 实例包及每文件 SHA-256 清单。不覆盖已有输出目录，不部署到游戏。开发验证可加 `--allow-dirty`，正式发布不能使用这个选项。
Final packaging requires a clean Git tree and new output directory. `--allow-dirty` is only for local validation. Packaging never installs into the game.

源码快照 / Source snapshot:
```powershell
git archive --format=zip --prefix=SkyCraft-OnimushaMC/ --output=dist/OnimushaMC-v0.2.0-source.zip v0.2.0
```

`SOURCE-IDENTITY.json` 记录提交、版本、协议及 DLL/JAR 校验值；GitHub Release 附带源码 ZIP 和总 SHA256SUMS。
The release identifies its commit and compiled hashes and includes source plus SHA256SUMS.

## 模板与隔离验证 / Templates and isolated validation

资源格式仅针对鬼武者：MESH 260209350、MDF2 51、TEX 251111100（行对齐原始 BC 数据）、RCOL 37、PFB 18、USER 3。不得将它们作为其他 RE 游戏的通用参数。

`onimusha/assets` 的碰撞盒／Prefab／USER 是私有路径资源，`onimusha/tools/assets` 是依赖加载模板；TEX 模板是重新生成的 4×4 单色 BC7 数据，不含 MC 或鬼武者美术贴图。MDF 保存中性材质参数，引用用户游戏自带 shader 和空法线。Blender 转换器把运行中的 MC 模型与贴图转换到这些格式。

`onimusha/tools/UnitBoxCollider` 和 `NativeModelLoader` 保存可选 RCOL／模型 USER 模板生成源码（需要 REE-Lib 与本机游戏 RSZ schema）；碰撞 Prefab 使用随库提供的已验证模板。正常构建直接使用这些模板，无需游戏解包。第三方 RE Mesh Editor 在独立 Blender 进程加载，其源码和 GPL 许可保留在 `onimusha/release-deps`。

用解压后的包运行隔离打包测试（伪游戏目录，不修改真实游戏）：
Run packaging integration checks against an extracted package without touching your real game:
```powershell
python onimusha/release/Test-PublicPackage.py --package dist/v0.2.0/OnimushaMC-v0.2.0-win64 --blender 'C:/Path/To/blender.exe'
```

旧 `onimusha/tools` 下的开发部署／采样脚本包含作者测试路径，仅供研究；公开安装入口是 `onimusha/release`。不要直接运行历史 Install-*、Grant-* 脚本作为正常安装方式。
Historical developer scripts may contain local lab paths. Use the public release installer rather than those scripts.
