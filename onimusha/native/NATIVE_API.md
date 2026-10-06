# Native bridge / Lua adapter interface

The DLL creates `Local\OnimushaMC_v1` at protocol version 12. It registers
`onimusha_mc` when REFramework creates a Lua 5.4 state. Its Lua dependency is the
unmodified Lua 5.4.3 source vendored by the user's installed REFramework commit
`b6baf6b406efc65e077b99cb4d9ad25b0a0a9095`; upgrading REFramework requires checking
the Lua state ABI before rebuilding. This follows REFramework's example plugin,
which links its own matching static Lua library to operate on the callback state.

All positions are MC coordinates in blocks, Y up. The adapter owns conversion
from RE metres and must prove its player/control/camera/hide/collision/HP bindings
before submitting `ready=true`. A missing binding must stay in diagnostic mode.
RE XYZ and MC XYZ use the same axis directions; conversion applies scale and
world-origin tiling without mirroring Z. Fallback world rendering uses right-handed
view/projection matrices with MC right `(-cos(yaw),0,-sin(yaw))` mapping to screen
right. The MC yaw/pitch up vector keeps vertical-pole views finite. F5 front view
reverses the viewing direction and its screen-right basis. Supplied matrices and
HUD rendering keep their existing layout. Terrain and avatar remain CullNone.

* `submit_host(table)` (`tick_host` alias) publishes `x,y,z,yaw,pitch,world_id,epoch,
  teleport_seq,viewport_w,viewport_h,health_current,health_max,health_revision,
  units_per_block,ready,menu,loading`. Optional `flags` and `game_hour`. Returns bool.
  A changed epoch clears old geometry and invalidates collision/camera readiness.
* `read_mc()` (`get_mc_state` alias) returns nil when heartbeat is stale. Otherwise:
  `x,y,z,yaw,pitch,eye_x,eye_y,eye_z,eye_height,fov,camera_mode,camera_distance,flags,
  teleport_ack,frame,on_ground,screen_open,in_world,dead`.
* `drain_events()` (`poll_events` alias) returns exactly-once event array with
  `type,form_id,a,b,c,d,flags,weapon,epoch`. For type 6, `a` is signed fraction of
  maximum host HP; negative is damage, positive heal. `b` is MC health points,
  `flags` damage/heal bits, `weapon`/`epoch` is session collisionEpoch. Ignore stale
  epochs and reject events outside the active session. Host HP stays authoritative.
* `send_hurt({mc_points,kind,attacker_id,flags})` forwards incoming host combat as
  InputType 7 with `a=round(mc_points*100)`, host-unapplied bit 2 set. MC armor and
  shields compute mitigation, then return type 6. Return false leaves the original
  host damage path in charge; the adapter must not skip original damage unless
  queuing succeeds. Do not forward again while committing returned HP.
* `set_enabled(bool)` controls takeover (default false). F10 toggles it.
* `status()` returns `connected,enabled,ready,host_ready,collision_ready,
  not_ready_reason,host_age_ms,mc_heartbeat_age_ms,re_ui_open,re_ui_sampled,
  camera_ready,renderer_ready,gui_cursor_known,gui_cursor_u,gui_cursor_v,
  gui_cursor_raw,raw_look,gui_raw_packets,gui_raw_dx,gui_raw_dy,
  gui_fallback_packets,gui_open_count,look_raw_packets,
  protocol,rejected,render_invalid,sections,textures,overlay_frame,
  error,mapping`.
  Mouse counters accumulate for the DLL lifetime, without per-frame logging.
  GUI RAW packet counts/delta sums prove whether genuine relative input reached
  the bridge; fallback counts include emitted movement only, not center warps.
  `not_ready_reason` reports the first failed existing takeover gate, in its
  original order, or `ready`. UI state is queried only when prior gates pass;
  `re_ui_sampled=false` means `re_ui_open` is the last permitted sample, not a
  newly queried UI value. Missing/future heartbeat or host timestamp has age -1.
  Collision telemetry includes `mc_pid,collision_epoch,collision_generation,
  collision_publish_seq,collision_consumed_seq,collision_batch_end,
  collision_head,collision_tail,collision_ring_valid,collision_pack_ms,
  collision_pack_max_ms,collision_pack_failures,collision_queue_failures,
  collision_failure`. Generations/sequences/byte counters are exact Lua integers.
  Pack time covers synchronous packing, not the whole Lua query or render frame;
  packing and queue failures are separate cumulative counters.
* `publish_actors(array)` rows: `id,flags,x,y,z,yaw,width,height,health_frac,level,name`.
  Stable nonzero IDs must map back to the host's live enemies. Maximum 256 rows.
* `publish_collision_tris({epoch,min_x,min_y,min_z,max_x,max_y,max_z,triangles})`
  rows: `ax,ay,az,bx,by,bz,cx,cy,cz,flags`. Inclusive integer block bounds.
  Maximum 100,000 triangles. Triangle winding must be correct for collision.
  Original-world diggable flag is stripped: this release supports adding/removing
  MC blocks, never removal of the original game terrain. Returns bool.
  Native packing splits arbitrary bounds into Fabric's aligned eight-block cells,
  streams both exact triangles and 1/8-block surface occupancy. Empty cells are
  also marked known so Minecraft can safely release its teleport hold. Packing
  rejects more than 1024 cells or 12 million voxel overlap checks in one update.
  Bounds must be finite, ordered, and within +/-30,000,000 blocks; validation
  happens before floating-point-to-integer conversion or region arithmetic.
  Packing finishes before queue capacity is checked for the whole batch,
  including a new-epoch CLEAR and wrap padding. Failure publishes no packet and
  does not advance the successful epoch/sequence. Success copies every packet
  and commits the producer head once; protocol v12 is unchanged.
  A successful return proves complete queue publication, not client consumption.
  Save `collision_publish_seq` plus generation/PID/epoch after success, and wait
  for connected + matching context + `collision_consumed_seq>=target` before
  certifying the new complete coverage. The consumer tail is committed after
  processing its head snapshot, so crossing the batch end proves drain completion.
  It does not prove a subsequent game physics tick ran. Invalid ring counters
  cannot acknowledge a batch and revoke native collision readiness.
  Sequences increase over the DLL lifetime; observed MC PID/fresh-stale link
  changes, host epoch/Lua reset and native mapping reopen advance generation and
  discard old pending proofs without recycling sequence IDs. A new DLL lifetime
  starts new counters; adapter state must not reuse old session proofs.
  Each packet replaces its full aligned eight-block region, including query-edge
  padding. Native does not merge old triangles into MC region packets. While
  waiting for acknowledgement, Lua may retain only same-context old/new complete
  query intersection covering the player's feet/body; different epoch/generation,
  disconnect, or leaving coverage must release control. All refreshed query parts
  must be complete; triangle count truncation must not certify a whole AABB.
* `drain_solids()` returns up to 8192 block changes `{x,y,z,solid}` per call. The
  adapter creates/removes RE collision objects and must retain them until removed.
* `set_camera({view_proj,origin_x,origin_y,origin_z,valid,binding_ready})`. The optional
  matrix has 16 column-major floats and operates on positions relative to origin
  in MC blocks. If unavailable, renderer can derive MC projection; `binding_ready`
  must still reflect a verified original-game camera takeover, not a guess.

Takeover requires enabled + fresh ready host (<500 ms) + collision/camera/GPU readiness
+ live MC heartbeat (<3 s) + MC in world + matching teleport acknowledgement.
Ready host updates with missing/non-finite/zero maximum HP are rejected. GPU
resource preflight does not draw or hide the host, and reset revokes GPU readiness.
Menus/loading/REFramework UI/focus loss release all MC keys/buttons. Escape and G
pass to the original game unless an MC screen is open; O opens MC pause options;
Insert remains REFramework. Mouse deltas use MC sensitivity and inversion.
The window-cursor fallback suppresses host recentering (within one pixel of the
client center) while updating its baseline; fresh routing, focus loss and MC menu
transitions reset that baseline. Native relative raw input remains preferred.
GUI screens use a virtual cursor, initialized at the center when a screen opens
or routing resumes after focus loss. Existing relative RAW mouse packets add
`dx/client_width,dy/client_height` to normalized coordinates, clamped to [0,1].
The bridge does not register a RAW input device or change the game's mouse setup.
Every GUI button sends the cached virtual cursor before the button event; button
LPARAM and the OS cursor cannot move this cache. Returning the virtual cursor to
the center through relative movement permits an actual center click.
Before the first relative RAW packet, legacy WM_MOUSEMOVE can supply relative
deltas using a center baseline and suppressing host recentering. Once RAW arrives,
legacy movement is ignored until routing/focus/menu transition resets its mode,
preventing duplicate movement. The same reset clears the non-GUI RAW look flag so
historical RAW input cannot permanently disable a later fallback session.
GUI-to-GUI updates and client/host viewport resizing preserve normalized cursor
position; leaving GUI or losing routing clears it. Pending center/cache packets
are retried. If a button's cursor or button itself cannot queue, routing resets
and pending ReleaseAll is retried before the next GUI center baseline; this avoids
leaving a held button after losing its button-up event to a full ring.
Both Present and window-message paths retry pending ReleaseAll before forwarding
new input. If the ring remains full, routed MC input is consumed without a new
GUI baseline; focus/F10 handling, Insert, non-GUI Escape/G and unrelated window
messages retain their existing behavior. Recovery does not depend on Present
arriving before the next button message.
The renderer uses this normalized cache rather than polling the OS cursor.
The pinned REFramework WindowsMessageHook invokes DefWindowProc for consumed
messages. The plugin returns false for routed WM_INPUT and never performs a
second system cleanup itself; the actual DLL test fixture mirrors that wrapper.

Actual in-game GUI acceptance still requires a real relative mouse test of this
virtual-cursor build. The earlier absolute-event build selected the wrong slot
after the host replaced its button coordinates with the center. Automated DLL
callback tests cover virtual-cache ordering and transitions; pure router tests
cover RAW accumulation/clamping/deduplication. They do not manufacture a genuine
OS HRAWINPUT packet, prove the game supplies one, or verify physical GUI clicks.
Absolute desktop automation may use the legacy fallback and cannot establish
physical relative-input acceptance. Use status packet/delta counters to distinguish
missing relative input from GUI position/Java scaling failures.

The renderer reads native-managed meshes, textures, avatar/scene, collider triangles
and a deep copy of the triple-buffer HUD. Invalid ring packets, NaN movement,
texture lengths, and out-of-range draw batches are rejected within bounded loops.

Build and tests: CMake / Visual Studio 2026 x64, Release, `ctest -C Release`.
The mapping test launches an independent native process to emulate the MC peer;
it is not proof of live Onimusha engine integration.

`omc_runtime_smoke_host.exe 120` exercises the real Fabric client through the
isolated `Local\OnimushaMC_Smoke` mapping. It publishes a collision floor, two
enemy proxies, and 75/100 authoritative HP; drives movement, GUI, a melee hit,
block creation/removal, armor-mitigated damage, healing, and epoch rejection.
Its result/logs are written under `G:\Onimusha_MC_mod\logs`. Launch the developer
client with `-MappingName 'Local\OnimushaMC_Smoke' -QuitWithHost`; neither executable
opens the live game mapping. The host preserves its dead PID so the client saves
and exits through its normal watchdog.

The recorded real-client run in `logs\smoke-roundtrip-pass` passed: MC health was
15 for host 75/100; 3 raw incoming points became 1.38 after MC armor, host HP became
68.1 and two MC queries both returned 13.62; a four-point MC heal made host HP
88.1 / MC 17.62. An old-epoch damage response was rejected without changing HP.
Block meshes and solid notifications appeared and were removed, avatar/HUD/input
and enemy hit events were received, and the client saved and quit. This verifies
the Fabric/IPC/native data path with a simulated host, not actual Onimusha
camera/control/hide/combat/collider integration.

The minimal DLL-only test must keep Minecraft and the Lua takeover adapter off.
Expected status is `enabled=false,connected=false,ready=false,host_ready=false,
collision_ready=false,camera_ready=false,renderer_ready=false`; textures, sections,
and overlay frame remain zero. Initialization stores the renderer API pointer and
registers callbacks without creating graphics or game physics resources. Inactive
Present reads only owned data/shared memory; graphics preflight requires both an
enabled bridge and a live MC heartbeat. The plugin never calls RE SDK object or
physics constructors. The DLL API test executes 1200 inactive Present calls,
12 device resets, and 16 Lua state recreations with poisoned external GPU/SDK
pointers, proving these paths do not dereference them or query host UI state.

`omc_restart_smoke_host.exe` is a separate test-only fixture with a 120-second
total deadline. It hands the isolated Smoke mapping between two distinct native
PIDs while one real MC client stays alive, reuses epoch/teleport sequence 1,
changes the second spawn, and delays fresh collision by 1500 ms. Recorded evidence
in `logs\smoke-host-restart-pass` verifies 88 held acknowledgement-zero samples,
then acknowledgement 1 at (12,65,4), renewed MC PID, and re-export of the atlas,
pre-existing stone mesh/solid mask and HUD. The final host exit triggers normal
MC save/quit. This test does not exercise actual Onimusha or queued health events
across a host restart.
