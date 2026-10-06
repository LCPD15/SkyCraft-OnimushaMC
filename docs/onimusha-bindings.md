# Onimusha: Way of the Sword runtime bindings

This adapter targets `OnimushaWotS.exe` only. REFramework support for other RE games does not imply their player, health, camera, scene or physics APIs match this game.

## Evidence and verification

The locally unpacked Onimusha RSZ schema confirms the following type names. RSZ records serialized fields and inheritance; it does **not** verify runtime methods, singleton instance paths or correct call semantics.

| Area | Type names found in the local game schema | Runtime checks required |
| --- | --- | --- |
| Player | `app.PlayerManager`, `app.PlayerCharacter`, `app.PlayerController` | Resolve the live playable character, not the menu/gallery model |
| Health | `app.cHealthManager`, `app.PlayerBattleComponent`, `app.BattleComponent` | Current/max HP, safe damage/healing API, native death notification |
| Camera | `app.CameraManager`, `app.PlayerCameraControllerBase`, `app.CameraController` | Camera ownership and FOV; native scripted scene handoff |
| Input/root motion | `app.cPlayerGameInput`, `app.cPlayerCommandController`, `app.cPlayerInputStateSupporter`, `app.cPlayerMotionRootTransStopper` | Suppress player commands/root motion while retaining enemy and health updates |
| Rendering | `via.render.Mesh`, `app.PlayerBodyModelControllerBase` | Hide all playable model parts without disabling player damage/collision |
| Physics | `app.AppRaycastManager`, `via.physics.System`, `via.physics.CastRayQuery`, `via.physics.CastRayResult`, `via.physics.Colliders`, `via.physics.BoxShape` | Terrain extraction and runtime block collider registration, removal and filtering |
| Enemies | `app.EnemyManager`, `app.EnemyCharacter`, `app.EnemyBattleComponent` | Live actor enumeration and damage that triggers native AI/death/drop bookkeeping |

Schema evidence: `G:\游戏MOD\0_自己做的Mod\鬼武者\制作\管理记录\阶段资源整理_20260920\rszoniwots.json` (read-only). No game methods are inferred from the absence/presence of serialized fields.

### Live Onimusha TDB 82 evidence

The loaded scene probe (2026-10-06) established these **actual object references and getter results**:

| Binding | Verified live path / result |
| --- | --- |
| Player | `app.PlayerManager.getControllingPlayerInfo()` → `app.cPlayerManageInfo.get_Character()` → `app.PlayerCharacter` |
| Controller | `app.cPlayerManageInfo.get_Controller()` → `app.PlayerController` |
| HP | `PlayerInfo.get_Context().get_Chara().get_HealthManager()` → `app.cHealthManager`; observed current/max **2000/2000** |
| World identity | `PlayerInfo.get_Context().get_Info().get_StageID()/get_AreaID()` → **20/78** in the loaded scene |
| Camera | `sdk.get_primary_camera()` → `via.Camera`, GameObject `Main Camera`; observed FOV **41 degrees**, aspect **1.77777779** |
| Model parts | `PlayerInfo.get_Context().get_Parts()` → **15** game objects, in addition to the main `Player_00` body |
| Native geometry values | `via.AABB.minpos/maxpos`, `via.Triangle.p0/p1/p2`, `via.OBB.coord/extent` are reflected fields, not hardcoded memory offsets |

Method signatures verified in this TDB include `GameInputManager.sealAllPlayer()`, `CharacterBase.evMotionRootApply(via.vec3,via.Quaternion)`, `cHealthManager.addHealth(int,bool)/setHealth(int)/checkHealthZero()`, and `via.physics.System.getAreaPrimitive(GetAreaPrimitiveQuery)/castRay(CastRayQuery)`. Signature existence is distinct from exercised semantics: terrain query, damage/death reactions, camera axes and collider registration still require their runtime diagnostic or in-game test.

Hook installation also needs independent proof. In the initial REFramework log, `addHealth` at `0x14063d9b0`, `set_Health` at `0x145a617e0`, and `evMotionRootApply` at `0x1449a0f30` were patched successfully; `setHealth`'s JIT thunk at `0x245049000` failed despite REFramework subsequently printing a generic "Hook added" message. The adapter therefore no longer attempts that failed hook. It reports each method/address/attempt and observed callback counts, and counts real negative player calls separately. The explicitly enabled zero-delta `addHealth(0,false)` test previously observed one player callback with HP unchanged at 2000/2000, but is now **disabled by default**. A zero-delta call establishes dispatch, **not** a successful native-hit → MC-armour → native-death round trip. `setHealth` remains a callable original method for guarded HP commits.

The adapter starts in strict read-only **stage A** and writes compact `onimusha_mc_status.json` diagnostics. It performs no bridge submissions, hooks, health writes, physics allocation or native object creation in that mode. Stage C permits F10 to toggle the native bridge; the UI reflects that runtime state. Player rendering/movement is changed only after terrain, camera, observed control/health hooks, native renderer, connection, MC world and teleport acknowledgement gates pass. It hides the main body **and** the context parts, then restores their original draw states when native control resumes.

Procedural blocks use an actual `via.physics.Collider` linked to a newly created empty GameObject and `via.physics.BoxShape`, with the ground collision filter copied. This is not considered registered merely because allocation succeeds: a temporary block four metres above the player must be hit by a native raycast **with the exact same collider identity**. The test stays near the loaded scene instead of assuming distant objects are exempt from physics culling, uses the explicit origin/direction/distance ray overload, and enables all hits so nearby ceiling geometry cannot mask the test. Failed registration disables/destroys the probe and leaves the native solid-update queue undrained. `RequestSetCollider` is an alternative resource-based API; its presence alone does not provide arbitrary shape insertion.

The first live diagnostic confirmed **8,450 world collision triangles**, zero unsupported values, and the camera's native **-Z** axis (look-at/rotation dot product **-1.0**). Standalone Collider allocation did **not** pass the native raycast test. An experimental fallback attaches `RequestSetCollider` using `mod/onimusha_mc/unit_box.rcol.37`: allocate one group, load its resource holder, await initialization, register the resource's actual group/request-set IDs, and obtain the native collidable from index `(0,0,0)`. This fallback must pass the same identity raycast before block updates are consumed. **Neither native collider route is verified and neither runs in any default stage preset.**

### Crash isolation and staged configuration

At 2026-10-06 00:55:07 the combined experimental build crashed during loading with `C0000005`, an engine access through null at executable offset `0xFC00B1B`. The REFramework stack mentioned work-rate hierarchy and raycast manager updates. The last report contained valid HP/stage, 8,450 terrain triangles and the earlier successful zero-delta hook test; no successful resource collider result was recorded. This does not prove which change caused the crash. Resource collider creation/lifetime and the inactive hook path remain isolation candidates, and the adapter now excludes those paths from the default diagnostic run.

Configuration is read from `reframework/data/onimusha_mc_config.json` every 120 application frames. The source presets can replace that file while the game runs; there is no automatic progression and no user Reset Scripts needed between stages. DLL installation/removal still requires a game restart. A config downgrade releases any existing takeover before returning to passive diagnostics. A cold stage-A run never changes native bridge state.

Hooks already installed in stage C remain patched until REFramework resets scripts or the game restarts. Downgrading makes their callbacks pass native execution through; it does not claim to remove hook code. If a hook itself is an isolation suspect, use a fresh stage-A session rather than treating hot downgrade as equivalent to an unhooked process.

| Preset | Permitted work | Explicitly excluded |
| --- | --- | --- |
| `onimusha/config/onimusha_mc_config.stage-A.json` | Fully initialized player/stage/HP/camera getters and report | Hooks, queries, bridge submissions, control, RCOL/resource loading, GameObject/collider creation |
| `onimusha/config/onimusha_mc_config.stage-B.json` | Verified GetAreaPrimitive query, terrain and actor export, passive host bootstrap | Control/health hooks, event HP writes, hiding/moving, native collider creation |
| `onimusha/config/onimusha_mc_config.stage-C.json` | Stage B plus control hooks after valid player; F10 takeover after runtime gates | Native collider tests and automatic zero-delta HP test |

All presets retain `enabled=false`, `enable_native_block_colliders=false`, `enable_block_collider_tests=false`, and `enable_health_hook_tests=false`. Do not enable native collider switches as part of core testing. Both native collider switches would have to be explicitly enabled in stage C to enter the experimental resource/object path. Valid native HP getters permit first takeover in a safe area; observed damage-hook counters remain separate evidence. An ordinary native HP change can verify those callbacks without a synthetic damage test. Incoming damage stays native if the MC mitigation event cannot be queued.

An unchanged hot configuration preserves the runtime F10 toggle. Changes to unrelated stage-C tuning also preserve it; an explicit `enabled` preference or runtime-stage change applies the configured switch. Windows can deliver F10 as `WM_SYSKEYDOWN`, so both normal and system key messages are handled, with repeat and key-up consumed without toggling again.

`via.physics.GetAreaPrimitiveQuery` and the returned `via.physics.GetAreaPrimitiveResult` are explicitly promoted to Lua-owned managed references with `add_ref()`. The installed SDK only automatically retains engine-owned objects with a positive reference count. Holding a newly allocated zero-reference object in a Lua table alone did not prevent the game GC from reusing it. The query is kept for the adapter session; each result is held only until its export job completes. Validate the exact types before reuse. Do not force-release an object still used by a job.

Scene epochs and teleport sequence counters persist in the task-owned `onimusha_mc_session.json`, and are reserved at script startup. A Reset Scripts in the same second must not reuse the previous MC acknowledgement. The Minecraft side also detects a new host PID and waits for fresh terrain even if an external host reuses counters.

Minecraft's own collision boxes handle placed blocks for the MC player, whose accepted feet pose moves the host player. The user physically verified support/removal but subsequently confirmed native NPCs are not stopped by those blocks. This is a missing part of the requested interoperation, separate from MC player takeover. The native solid-update queue stays undrained while the experimental native collider sink is disabled; do not describe these blocks as registered RE physics objects.

### Player input seal ownership and release

The captured TDB has `GameInputManager.sealAllPlayer()`, but no verified `unsealAllPlayer`, `unseal` or `resetSeal` counterpart. The adapter therefore keeps an ownership ledger for the exact player-input objects it seals. Before its first seal call in a takeover, it records the reflected Boolean `_SealAll` on objects in `_PlayerInput`, `_PadPlayerInput` and `_MkbPlayerInput`, plus `_IsSealed` on each object's `_Keys`. The ledger deduplicates owners and retains their managed references. It accepts at most 16 inputs per array and 512 keys per input; missing fields, non-Boolean values or failed enumeration stop takeover **before sealing**. It does not touch UI-input arrays, key configuration or other input fields.

The actual captured baseline was mixed: the merged `_PlayerInput` object's `_SealAll` was **false**, the pad object's value was **false**, and the non-empty `_MkbPlayerInput` object's value was **true**. Empty device inputs also appeared in the probe and must not be confused with those actual player arrays. These observations identify field names and demonstrate why clearing every seal to false would be wrong; they are not universal defaults for another session or input object.

`fail_open`, player changes and script reset restore the ledger's **exact saved values**, only for its tracked owners and only after this adapter attempted a seal call. This fixed SDK exposes `REManagedObject:set_field(name, value)` for writes; `REField` has `get_data` but no callable `set_data`. Capture checks that the real managed setter is callable, and release verifies each write by reading the reflected field again. Only confirmed records are released; failed records remain retained for the next `fail_open` retry and prevent a new takeover from overwriting their history. Values already matching the saved state need no write, and repeated successful release is inert. A capture that never reaches sealing performs no restoration writes. A cold stage A does not enter input capture/seal helpers or access these fields; a downgrade from a prior takeover may retry restoration of its existing owned ledger. `onimusha_mc_status.json` reports `input_seals` with array/input/key counts, capture failures, restoration errors and `pending_records`.

Native draw baselines must be Boolean, and the original and replacement FOV must be finite positive numbers before the adapter writes them. Draw/FOV release confirms the result by reading it back, retains failed originals, and retries while holding takeover off. The FOV record retains the actual original camera object rather than restoring a later camera selected during a scene change. `visual_restore` reports pending draw/FOV records and their errors. Position writes explicitly pass the SDK's `no_dirty=false` argument.

The real Lua 5.4 fixture verifies mixed false/true restoration, repeated release, capture without sealing, refusal on reflection failure and a cold stage-A run without input-field access. **Ordinary F10 release was physically verified with DLL 2B64 / Lua D233:** the user confirmed the original character, movement and menu controls returned; the report had no input/draw/FOV pending records or recovery errors. Passing Esc or G through the Windows message hook alone does not establish menu recovery. The newer coordinate build still requires its own release retest; input-owner replacement and permanent setter failure remain separate limitations.

The earlier adapter saved no input-seal ledger. If that version already left a session stuck, Reset Scripts cannot reconstruct the prior values or their owners. Without an existing ledger from before that takeover, recover with a **clean game restart**; do not substitute the old probe's mixed baseline for the current objects' missing history.

Enemy enumeration resolved 23 live component/context/health chains in the physical stage0/area0 run. It currently searches `get_CurrentScene` only, although the TDB also exposes `get_MainScene` and `get_Scenes`; scene counts are needed before expanding it. Enabled/visible checks are still needed to exclude preloaded inactive enemies. Input arrays/key objects being replaced during an active takeover also need a measured identity-change check before adding a replacement-owner strategy. Neither multi-scene coverage nor replacement-owner support is claimed by the current adapter.

## Read-only probe

`onimusha/adapter/onimusha_mc_probe.lua` gathers method signatures, field names and bounded object graphs using REFramework's documented reflection APIs. It installs no hooks and writes no game object fields.

Install the probe into `reframework/autorun/` and start the game. It waits 120 frames before gathering metadata. `UpdateBehavior` then records a runtime snapshot every 300 frames, including after a save is loaded.

Reports under the game's `reframework/data/`:

- `onimusha_mc_probe_types.json`: known type metadata and TDB version.
- `onimusha_mc_probe_snapshot.json`: latest runtime references plus metadata for discovered object types.
- `onimusha_mc_probe_snapshot_1.json` through `_30.json`: bounded history, while the latest snapshot continues updating.

The probe is independent of the native bridge. Its reports distinguish a missing type, null singleton, null player, and present objects. Menu-only captures cannot establish a working player binding.
When `onimusha_mc` is present the probe returns immediately; the adapter owns the smaller runtime report and avoids repeatedly dumping large reflection graphs.

## Native bridge contract

The bridge exposes `onimusha_mc` to the Lua environment:

- `submit_host(state)`: MC-space player feet, orientation, scene ID, epoch, viewport, and native HP current/max.
- `read_mc()`: latest stable MC pose, camera and state flags, or nil if disconnected.
- `drain_events()`: bounded MC combat/health events.
- `send_hurt(event)`: queue pre-deduction native damage for MC armour/shield mitigation; native damage is suppressed only when queuing succeeds.
- `publish_actors(actors)`: native enemy proxy descriptions.
- `publish_collision_tris(region)`: native collision triangles in MC coordinates.
- `drain_solids()`: placed/removed MC block collision updates.
- `set_camera(camera)`: projection matrix and viewport for native world rendering.
- `set_enabled(enabled)`, `status()`: connection/control gates and diagnostics.

One host unit initially equals one Minecraft block, assuming RE's world metre convention. Calibrate this in game; asset formatting is not sufficient evidence of metre scale.

`EV_HEALTH_CHANGE` carries a signed fraction of **native max HP**. Apply accepted changes to the current native HP only in the same scene/session epoch. Minecraft displays `clamp(current / max, 0, 1) * 20` health points, or ten hearts. Native HP is authoritative; Minecraft's base health amount never replaces the native health pool.
For protocol version 12, the health event epoch is exposed by `drain_events()` as `weapon`; it is not a health revision counter. The adapter guards its own HP writes against damage hooks and retains fractional HP remainders rather than discarding them.

World coordinates now preserve XYZ handedness: `(RE x, RE y, RE z)` divided by the configured metre/block scale, with a stage tile offset. The former `(x,y,-z)` reflection matched forward movement but reversed screen-right/strafe and mouse yaw in the physical test. For the measured local -Z camera, native camera yaw is `180 - MC yaw` and pitch is `-MC pitch`; the hidden native player's local +Z heading uses `-MC yaw`. Unknown camera axes refuse takeover. The fallback renderer uses RH view and projection together, with Minecraft's screen-right basis `(-cos(yaw),0,-sin(yaw))`.

Stage/area pairs have persistent separate MC tiles of 8192 blocks so overlapping native coordinates in different locations do not share placements. A tile extent guard prevents uncalibrated scenes from crossing into another location's tile. F5 offsets use the same MC eye/yaw/pitch/distance contract in Lua and the renderer. Changing the world basis requires fresh epoch/teleport acknowledgement and collision export; old reflected-basis MC placements must not be silently reused. The physical retest uses the separate `OnimushaMC-XYZ-v2` world and preserves `OnimushaMC` plus its backups.

坐标方向修复只适用于此处实测的鬼武者相机：XYZ 方向保持一致，只转换单位及场景 tile；原反射坐标下的 MC 存档仍保留。Lua 的位置/前向/右向/F5 往返回归与 native 矩阵/GPU 左右投影检查已通过；8D90 DLL / 1A6F Lua 随后由用户确认方向、四向移动、跳跃、墙/台阶碰撞、F5和两格背包点击均正常。5291 DLL / AD35 Lua 的持续移动交接随后通过，24次刷新无失败或地形退出。MC剑扣敌人HP后来由用户重新确认；原生受击反馈仍缺失。原生NPC碰撞、真实深度/光照以及整个桥接仍未完成。

2026-10-07：被动B274时序hook在真实场景定位到 `app.CameraManager.lateUpdate()` 返回时primary被覆写成原生方向/FOV41。`reflectGameCameraToCameraComponent`虽有调用但exact owner匹配0，四项投影方法0调用，不把它们当作已找到的UI入口。候选只在认证外层lateUpdate post重放MC相机的primary三项及同owner六项，不重跑player/HP/input/terrain。独立审阅还发现失败时primary位置/旋转应按该帧事务回滚，最终版本与回归数见[停点记录](ONIMUSHA-RESUME.md)；实际转向UI跟随仍待用户复测。

The renderer draws exported MC 3D geometry at Present through a private D3D11-on-12 context. Its D32 buffer is reconstructed from nearby native collision triangles. It is not the RE scene depth buffer, does not include all rendered scenery or dynamic actors, and cannot receive native lighting or shadows. See [engine integration gaps](ONIMUSHA-ENGINE-INTEGRATION.md) for the original SkyCraft comparison and required host-specific work.

The adapter must fail open: if Minecraft disconnects, a binding becomes invalid, a loading/menu/scripted scene owns control, or required collision data is absent, release native input/camera/render overrides. No synthetic flat floor, no invented HP and no assumption that a copied method name from another RE game works here.

## References

- [REFramework SDK](https://refdocs.praydog.com/api/sdk.html)
- [Type reflection](https://refdocs.praydog.com/api/types/RETypeDefinition.html)
- [Method reflection](https://refdocs.praydog.com/api/types/REMethodDefinition.html)
- [Transform operations](https://refdocs.praydog.com/api/types/RETransform.html)
- [Callback phases](https://refdocs.praydog.com/api/re.html)
- [Lua file sandbox](https://refdocs.praydog.com/api/fs.html)
