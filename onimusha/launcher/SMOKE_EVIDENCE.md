# Minecraft runtime smoke evidence

Date: 2026-10-06 (Asia/Hong_Kong).

A real Minecraft 26.3 client with Fabric Loader 0.19.5, Fabric API 0.161.0+26.3 and the
compiled Onimusha fork was started through `MC-launch-dev.ps1` in the isolated runtime.
It used `Local\OnimushaMC_Smoke` and a standalone native mock host, **not the Onimusha game**.
This was a developer profile with no account credentials; production Microsoft login was not tested.

Observed first run:

- Vanilla/Fabric/SkyCraft resources and mixins initialized without transformation exceptions.
- The MC window hid on connection and the `OnimushaMC` mirror world was created automatically.
- Native mock HP 75/100 produced actual server player Health `15.0f` (7.5 of ten hearts), verified
  through `/data get entity @s Health` in the client/server log.
- The block/item atlas exported at 2048 x 2576 pixels.
- A stone block produced a 36-vertex section mesh; F5 exported a 1,356-vertex player avatar.
- Holding W moved the MC player from z=4 to z=8.313 while remaining on the mock floor at y=65.
- Giving an MC item and opening/closing the MC pause GUI changed the exported state correctly.
- A normal MC sword attack hit proxy enemy 1001 and emitted `EV_HIT_ACTOR` with damage 7.
- The host received 1,020 HUD frames, then exited. Minecraft saved players/worlds and stopped
  approximately five seconds after the host process closed (`-QuitWithHost`).

Local evidence, outside Git:
`logs/minecraft-smoke-1.stdout.log`, `logs/minecraft-smoke-1.stderr.log`,
`logs/minecraft-smoke-1.host.log`.

Observed second run with the saved mirror world:

- The test stone block was removed; exported section count returned from one to zero and the
  native mock confirmed both addition and removal of the MC block's solid occupancy.
- An incoming host attack supplied 3 raw MC damage points with `HURT_HOST_UNAPPLIED`. The MC
  armour pipeline reduced this to 1.38 final points, producing `EV_HEALTH_CHANGE` fraction
  `-0.069`. The native host applied this once: HP 75/100 became 68.1/100, and the actual MC
  server Health query returned `13.62f` twice, confirming no duplicate deduction.
- An explicit Instant Health effect supplied four MC points, producing fraction `+0.2`.
  Confirmed native HP became 88.1/100 and MC Health returned `17.619999f` (floating-point rounding).
- A damage request from collision epoch one was consumed after the host advanced to epoch two.
  The host rejected it; HP remained 88.1/100 and the subsequent MC query remained `17.619999f`.
- Minecraft again saved players/worlds and exited when the mock process closed. No mixin or
  integrated-server startup exceptions occurred.

The second host's original `pass=0` assertion assumed an unarmoured player and hard-coded native
HP 60/80. The observed event fractions and health queries instead demonstrate MC armour reduction;
the native test assertion must compare the actual post-armour percentage, not raw damage.
Second-run evidence: `logs/minecraft-smoke-2.stdout.log`, `logs/minecraft-smoke-2.stderr.log`,
`logs/minecraft-smoke-2.host.log`, `logs/minecraft-smoke-2.host-result.json`.

The corrected native assertion was then run against the actual warm MC client. It reported
`passed=true`, two health changes applied, one stale health change rejected, HP 68.1 / 88.1,
MC solid addition/removal both true, one combat hit, 1,586 HUD frames and zero rejected packets.
The actual MC queries again returned `15.0f`, `13.62f` twice and `17.619999f` twice, followed
by normal save/quit. Evidence: `logs/minecraft-smoke-3.*` and the native agent's final archive.

After these runs, review added guards for reused teleport sequences/epochs after a host restart,
queued hurt from a previous session, collision readiness from an older session and render-store
resends after native world/epoch changes. World-name isolation was also added. The updated JAR
compiled with all 33 tests passing (`logs/fabric-build-reviewed.log`). Its SHA256 is
`09F41F912D7DBF38ACCC9FC16DDA688C3592D6C89DB409AE1E462D01E8C84304`.
These final restart/resend changes were then verified with a focused real-client restart fixture:

- Native mock PID 117248 handed the same mapping to PID 114232; MC remained process 13932.
- Both native processes deliberately used collision epoch one and teleport sequence one.
- The second process withheld new collision for 1,500 ms. The fixture observed 88 samples with
  teleport acknowledgment zero and no early acknowledgment, proving cached old terrain did not
  release the player.
- After fresh geometry arrived, acknowledgment became one and the player stood at the second
  host's new position `(12, 65, 4)`, rather than retaining the first host's moved position.
- The native header regained MC PID 13932. The 2048 x 2576 atlas, existing 36-vertex stone block
  mesh and its exact solid occupancy bit were re-exported to the new process.
- The second host received 502 HUD frames and zero rejected packets. Its JSON reported
  `passed=true`; MC saved `OnimushaMC-Smoke` and quit normally at 02:20:43.

Evidence: `logs/restart-smoke-first.log`, `logs/restart-smoke-second.log`,
`logs/restart-smoke-result.json`, `logs/restart-smoke-client.stdout.log` and `.stderr.log`.
The queued-health generation guard has unit evidence; this focused runtime fixture did not
artificially hold the MC server queue, and no extra test addon was loaded.

The previous task-created test save is preserved at
`runtime/minecraft/test-world-backups/OnimushaMC-smoke-before-world-isolation-20261006`.
Mock tests use the separate `OnimushaMC-Smoke` save. The normal `OnimushaMC` gameplay save was
absent before the separately authorized developer live-game launch, whose logs use the independent
`game-client-20261006` prefix. Mock testing did not modify that live-game world.

This proves the prepared Minecraft runtime, the fork's actual mixin loading and its shared-memory
exports to the mock host. It does **not** prove Onimusha camera takeover, live enemy damage hooks,
native player hiding, native rendering, scene collision or game save compatibility.

## Live developer client checks, 04:57–05:06

The separately authorized local developer launch used the real Onimusha process 49912 and MC
process 111500, `Local\OnimushaMC_v1`, the isolated `OnimushaMC` save and `-QuitWithHost`.
No Microsoft account credentials were used. This is runtime evidence, not a production-login test.
JAR SHA256: `7BF4F2047463984252282420B9239666CA7AEC4DD685BB89E5F46D055C339851`;
the build passed 43 unit tests, including one-time teleport rotation and GUI cursor ownership.

- At 04:58:57, a read-only, stable shared-memory snapshot had host yaw -90 / pitch 0 and MC yaw
  -90 / pitch 0, with epoch and teleport acknowledgment both 1791226301. The previous saved
  pitch -57.75 was replaced on first join by the absolute position-and-rotation teleport.
- At 05:00:51, the Java log received host cursor `(671,575)` twice, followed by a new host cursor
  `(960,540)` before the click. Host viewport, MC logical window and MC framebuffer were all
  1920 x 1080. Java therefore used `(960,540)` and logged the GUI click `(240,135)` in a 480 x
  270 GUI. The latest native cursor packet was already at the centre; the log does not support
  blaming Java viewport scaling for this remaining click issue. Native cursor/input testing
  and the parent task's screenshots are needed to identify where that packet was generated.
- At 05:06:03 the client detected the closed game process, logged `saving and quitting`, then
  saved players, worlds and overworld chunks at 05:06:04 and exited normally.

Evidence: `logs/game-client-cursor-events-20261006.stdout.log` and `.stderr.log`.
After both processes exited, the complete task-created save was copied to
`runtime/minecraft/test-world-backups/OnimushaMC-after-autonomous-20261006`.
All 28 files matched their source SHA256; `level.dat` last wrote at 05:06:04 and has SHA256
`677BBC6662476DD5AF4AD5F3DE061EF025B82EEA187AB46EA0E082F6D0AD05F5`.
The runtime remained stopped after backup. These observations do not establish physical mouse
look, inventory interaction, live combat or native collision as complete; the parent task keeps
the main Onimusha validation record.
