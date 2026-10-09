# Native death, Minecraft retry and camera-distance fade

2026-10-10. OnimushaWotS 01.000.001 / TDB82 only. Do not reuse these native action or enum contracts in another RE game without new verification.

## Native death handoff

The native hit reaction runs before Minecraft finishes shield/armour mitigation. In the reproduced failure, the final MC percentage event changed native HP from 39 to 0, but the already-selected action remained `PlayerOneHandedDamageAction.cMediumDamage`. `setHealth` and `checkHealthZero` set the zero-HP notification without selecting a death animation. Input, draw and camera restoration had completed; resetting input seals again could not fix this state.

The adapter now queues a handoff only after a confirmed lethal player HP write. It releases takeover, restores owned native state, and waits out menus/scripted scenes. It resolves a `PlayerCommonAction.cDieBase` action from the current player's loaded action list, preferring the current fighting style, and validates its owner and constructed `ace.ACTION_ID`. It never hardcodes the observed category 3 / index 8.

If no native death/revive flow is already active, it calls `cPlayerDieSupporter.reqForceDie(NORMAL, nil)` when the dead type is invalid, then `CharacterBase.requestBaseAction(id, DAMAGE)`. TDB82 enum values NORMAL=0 and DAMAGE=4 are checked. The latter request is essential: force-die alone did not start the animation/UI in the live reproduction. One attempted request is the maximum, including ambiguous SDK errors. Player, health-owner or epoch changes cancel stale work; positive native HP clears pending death work.

Live evidence: the recovery request was accepted, native dying became true, and the user confirmed the native death/retry menu appeared and retry returned to a playable scene. The user subsequently confirmed the installed adapter automatically completed native death and retry. The remaining failure was on the MC client after retry, below.

## MC screen and life state

Minecraft 26.3 `Gui.setScreen(null)` can construct `DeathScreen` internally when the local player is dead. The old HEAD injection only rejected an explicit DeathScreen argument, so the implicit branch bypassed it. An old screen also remained after native HP had recovered.

- Guard the implicit `LocalPlayer.isDeadOrDying` branch only inside `Gui.setScreen`, and retain the explicit-screen guard. Unowned Minecraft players keep their death UI; a native host's temporary disconnection does not transfer death ownership back to MC.
- While native health owns the host player, reject local `respawn()` requests. Native retry owns the location and health; do not recreate the MC player or discard inventory/XP.
- The server continues to mirror confirmed native HP. With valid positive native HP, no loading and no host-dead flag, clear the mirrored player's transient `dead` and `deathTime` fields. The client does the same after receiving positive mirrored HP, then closes a stale DeathScreen.
- Do not gate recovery on F10, collision readiness or `SKY_IN_GAME`: in this protocol the last flag represents control readiness, and is also false in native menus. Such a gate prevents the recovery that readiness itself needs.

The first follow-up still could not move: the client had positive HP, `isDeadOrDying=false`, `dead=false`, but `isAlive=false`, while the server was alive. Minecraft 26.3 **LocalPlayer overrides tickDeath without calling LivingEntity.tickDeath** and removes itself with `RemovalReason.KILLED` on tick 20. The existing common-class injection did not intercept that override. `HostLocalPlayerDeathMixin` now also cancels that local tickDeath while native health owns the player. It preserves the client entity's registration, rather than trying to resurrect a removed object by clearing its removal reason. Restarting only MC replaced the already-removed client instance; no native game restart was needed.

The next actual death/retry still removed the client (`removed-reason.client.txt`: HP20, `isRemoved=true`, `KILLED`; server alive). The override was installed, but its guard depended on the current authoritative-health bit and live heartbeat. A native death/load can temporarily clear those while the zero-HP MC player remains in the same world. The previous 30-tick check kept authority live throughout and therefore missed this gap.

`HostLifeLease` now retains ownership for the exact client player, client level and integrated server identities after one confirmed native claim. Missing HP flags, F10 OFF, native loading and a heartbeat gap do not release it. Changing MC player/world/server or disconnecting the MC world clears it; an unrelated world/UUID cannot inherit it. Server life ownership likewise uses the exact `ServerPlayer`, cleared when its integrated server stops. HP requests still require a current, playable native health session, and client revival still requires fresh authoritative positive HP. Retaining death ownership never authorizes healing from stale state.

The maintenance integration check `onimusha/tools/java/MinecraftDeathSyncCheck.java` runs on the real client thread with takeover OFF. It exercises explicit/implicit death UI interception and a legacy screen, restores all temporary client state before a render frame, and does not change native or server HP. Screen fixtures must go through `Gui.setScreen` with normal Fabric initialization; assigning a newly constructed screen directly caused a test-only MC crash and was removed from the check. A full world backup predates testing.

## Camera-distance dither

The previous `mcCamSys_DitherDepth.isDitherEnableCamera` hook observed zero calls. Native code inspection identified the actual per-frame consumer, `onLateUpdateEnd`. The first candidate called `requestDisable`, but the user still saw fading after 3,783 observed calls. On TDB82 its request Boolean is passed directly into `setEnable`; a successful void request is not evidence of disabled render parameters.

The revised pre-hook captures the actual `_Enable` field, calls the verified `setEnable(false, 0, Linear)` and checks that field. `get_IsEnable` is **not** the setter's immediate readback: native disassembly shows it returns true if `_Enable` is true **or the ease transition is unfinished**. Even a zero-duration transition finishes only when the original consumer runs. The first setter-based candidate therefore recorded false failures and could capture the wrong baseline.

The hook lets the original late-update compute render parameters, records `get_IsEnable` and near/far alpha afterward, then restores the captured `_Enable`. It counts suppression only after the consumer actually reports disabled. The setter updates the controller interpolation state, not the renderer output just computed. The next original frame without takeover resumes native rendering policy. Failed restoration is retained and retried through the reset/fail-open ledger; destroyed owners are released without writes. It never skips the original callback. Camera-distance visual acceptance remains separate from successful setter/readback checks.

This targets camera-distance dither only. It does not suppress enemy death, invisibility or material transparency. The revised late-update hook has live calls with takeover OFF and zero suppression in that state. Near-camera appearance with takeover ON remains a user acceptance check.

## Validation and rollback

- Latest Fabric build and 78 JVM tests passed, including ownership retention through 600 missing-authority ticks and release on player/world/server replacement or world disconnect.
- Final real-client maintenance check passed: implicit and explicit DeathScreen interception, initialized legacy-screen dismissal, dead flag/timer recovery, unchanged HP and unchanged player identity. Receipt `minecraft-live-death-check-final.txt`. The initial check caught an overstrict readiness gate; the revised code also passes while the native pause menu is open.
- Extended real-client check now executes 30 calls to the actual LocalPlayer.tickDeath override at zero HP and then restores health. Entity is not removed, isAlive becomes true, all GUI/retry checks still pass. Receipt `local-death-tick-check-run2.txt`. `MC_LOOK` is a camera mode, not the F10 enable switch; maintenance uses native pause plus the external enabled/active status check.
- The latest real-client check covers 30 normal, 60 missing-authority and 60 disconnected zero-HP ticks, including death UI during both gaps. All 150 retain the entity; restoring native authority/HP leaves `isAlive=true`, `isRemoved=false`, no death screen, unchanged HP and player identity. Receipt `life-lease-live-check.txt`, fresh state `life-lease-after-check.client.txt`. User confirmed WASD and jumping work again. A full native death/retry still needs acceptance after this build.
- During user movement, the corrected dither hook completed 2,254 suppressions with `enabled_during_consumer=false`, both alpha values 1, no error or pending restoration. This verifies the camera consumer path, not the final near-enemy visual result.
- Production Lua regression checks cover fatal HP readback, dynamic action selection, restoration gates, already-running native death/revival, owner/epoch changes, rejected request handling, and camera-only suppression. Combat telemetry and reset restoration tests also passed.
- DLL unchanged. Only adapter Lua and the Fabric JAR changed; the temporary native recovery probe was removed from the installed inventory script.
- Evidence: `G:/Onimusha_MC_mod/logs/death-dither-20261010/`.
- Backup: `G:/Onimusha_MC_mod/runtime/test-backups/death-dither-20261010/`, including a hash-verified 89-file world backup, original Lua and original JAR. Latest pre-lease saved world/JAR/Lua are in its `life-lease/` subfolder. Keep the current user's damage setting when restoring files.

MOD制作：LCPD15/LCPD拉灯
