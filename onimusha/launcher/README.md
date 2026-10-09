# Isolated Minecraft runtime

## Current local shortcut / 当前电脑的一键入口

After Onimusha enters a playable scene, run `G:\Onimusha_MC_mod\Start-OnimushaMC.cmd`
or `G:\游戏MOD\0_自己做的Mod\鬼武者\MC\启动并连接MC.cmd`.
`Connect-OnimushaMC.ps1` opens the existing `OnimushaMC-XYZ-v2` developer test world with
`-ShowWindow -QuitWithHost -SwordBlocking`, starts/reuses the native model worker, and reuses
the verified MC process rather than launching duplicates. Switch back to Onimusha and use F10.
This uses the local development identity; it does not authenticate a Microsoft account.
See [the play guide](../../docs/ONIMUSHA-PLAY-GUIDE.md) for controls, paths and mod compatibility.

The runtime lives outside the Git repository at `G:\Onimusha_MC_mod\runtime\minecraft`.
Minecraft game files and account credentials are not distributed in source releases.

## Production / 正版启动

Open `runtime\minecraft\Plain Craft Launcher 2.exe`, copied from the user's existing PCL EXE.
Its adjacent `.minecraft` contains the isolated profile `OnimushaMC-26.3-Fabric-0.19.5`.
Sign in to your own Microsoft account inside this launcher and select Java 25:
`runtime\jdk25\jdk-25.0.4.1+1\bin\javaw.exe`. Launch that profile; do not select ATM9.
No original PCL configuration, account cache, refresh token or existing save was read/copied.
If another PCL is already running, close it first: PCL uses a global singleton mutex.
PCL also uses shared per-user registry preferences. Copying its EXE isolates the game folder,
not every launcher preference; these scripts do not read account registry values or automate
global PCL settings. Java and login selection remain in PCL's normal user interface.

打开隔离目录里的 PCL，选择 `OnimushaMC-26.3-Fabric-0.19.5`，选择附带的 Java 25，
在这个启动器内自行登录微软正版账号，然后启动。本工程不会读取或复制原启动器的账号信息。

PCL's current primary source `Application.xaml.vb` handles update/GPU/memory/wait arguments;
it does not provide a verified general `--launch` or custom-Minecraft-path CLI. Therefore
`MC-launch-PCL.ps1` opens its normal UI instead of inventing unsupported launch flags.
Source: https://github.com/Meloong-Git/PCL/blob/main/Plain%20Craft%20Launcher%202/Application.xaml.vb

## Development only / 仅开发测试

`MC-launch-dev.ps1 -PrepareOnly` checks the isolated classpath and writes `launch-dev.args`.
`MC-launch-dev.ps1` starts the Fabric developer profile as `LCPD15` without reading account
credentials. This is for local bridge testing, not a replacement for Microsoft authentication,
online multiplayer or a production install. `-ShowWindow` keeps the MC window visible during
testing; the default hides it only once the native host link connects.
`-StartHidden` uses the existing bridge option to hide the client from its first frame while
waiting for an isolated test host, avoiding an extra game window during diagnostics.
`-QuitWithHost` saves and closes Minecraft after the connected host process exits; use it for
the isolated smoke host. The default keeps Minecraft running while a developer restarts the host.
`-WorldName` selects a separate save folder through `-Donimusha.worldName`; the default is
`OnimushaMC`. The isolated `Local\OnimushaMC_Smoke` mapping defaults to `OnimushaMC-Smoke` so test
commands, inventories and blocks cannot alter the gameplay save. Previous test saves are retained
under `runtime\minecraft\test-world-backups` outside the Git repository.
`-LogPrefix game-client-20261006` keeps a live-game run's stdout/stderr separate from mock-test logs.

The scripts use the task-local Java 25 runtime. They do not change PATH, Java registration,
the original launcher, the original modpack or any original saves. Native game/plugin deployment
and readiness are handled separately; prepare scripts do not start or modify Onimusha.

## Provenance

- Vanilla 26.3 client and libraries: official Mojang metadata, checked against published SHA1.
- Asset index 34 and every object: official Mojang hash. Existing PCL asset objects are copied
  read-only only when their SHA1 matches; missing objects are downloaded into `downloads` first.
- Fabric Loader 0.19.5 profile/libraries: official Fabric metadata and published SHA1.
- Fabric API 0.161.0+26.3: official Maven artifact, published SHA1 verified.
- The Onimusha mod JAR is the locally compiled fork; its hash is recorded with build evidence.

MOD制作：LCPD15/LCPD拉灯
