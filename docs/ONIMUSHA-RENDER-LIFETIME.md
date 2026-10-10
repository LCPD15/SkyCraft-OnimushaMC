# Native rendering lifetime regression — 2026-10-10

Applies only to this OnimushaWotS TDB82 / protocol 16 adapter.

## Observed incident

Repeated takeover switches and a long session reduced FPS; all new block and
dynamic appearances eventually stayed in the Minecraft overlay. Captured in
`G:\Onimusha_MC_mod\logs\performance-20261010-164255` before changing the runtime:

- Host PID 23268, worker PID 127944, MC PID 107724.
- Worker alive, exactly **8192 completed captures**; DLL refused every subsequent
  `request_model` because of its lifetime sequence ceiling.
- Lua held **5326 ready resource entries**, despite **0 live draw objects** at the
  recorded failure. The cleanup path retained historical dependencies and scanned
  them on every tick, including repeated stop calls.
- 8192 receipts contained 1631 distinct asset/error/empty keys, with **6561 repeated
  keys**. Some assets were requested over 50 times.
- The worker repeatedly globbed every historical request directory. This was a
  Blender background process, not a missing Python process.

These establish resource/request churn and a hard conversion cutoff. The exact
in-game FPS improvement still requires the same-route user test after installation;
offline timings are not a substitute for game-frame measurements.

## Fix

1. CLEAR/reconnect removes visible instances and readiness receipts but preserves
   the bounded immutable model registry. Identical texture uploads preserve their
   revision and model IDs. Changed texture bytes invalidate the affected models;
   IDs are monotonic and never recycled.
2. Keep an immutable full atlas alongside animated updates, so replaying an
   unchanged atlas after a reconnect does not invalidate static models merely
   because a water/fire tile animated in the meantime.
3. Maintain MC texture IDs by resource identifier across transport resets. Reset
   delivery bookkeeping and resend pixels without renumbering by enumeration order.
4. Native registry evicts cold, unreferenced appearances at its 4096-entry / 64 MiB
   bound. Current section and posed-face references are protected.
5. Lua polls only loading dependencies (at most 8), limits unfinished requests to
   32, reads worker health once per 30 ticks, and attempts at most one capture per
   eligible tick. Repeated disabled ticks do not repeat teardown.
6. Every 120 ticks Lua retains at most 512 older idle resource owners plus live,
   pooled, recently used and deferred-destruction owners. Eviction removes cache
   references; it does not rebind or release a live native Mesh's dependencies.
7. Remove the 8192 lifetime cutoff. The native writer publishes atomic pending
   tickets in `native_models/inbox`; the worker removes each ticket only after its
   result fence succeeds. Old result folders remain directly addressable. A single
   startup recovery scan handles earlier versions/interrupted writes; steady state
   scans only pending tickets. No game-native SDK calls run in the worker.

Native status adds model count/bytes/hits/evictions/issued IDs. Lua status adds
unfinished requests, idle cap, evictions and draw-update timing.

## Validation

- Production Lua in an SDK fixture: 1000 takeover cycles with 50 body/NPC faces,
  no additional creation/capture; repeated stop does not repeat release.
- 2000 historical Lua appearances: no more than 512 idle + 2 live owners after
  settling, all 50 live faces remain ready. Stalled worker bounded to 32 requests.
- Production C++: 1000 full CLEAR/reconnect/texture resend cycles preserve IDs;
  animated-atlas resend and genuine texture changes handled independently.
- 9000 distinct appearances continue registering while cold entries are evicted.
- **8200 actual asynchronous file captures**, with atomic inbox tickets, exceed the
  former limit; test consumer retires its own files after each capture.
- Worker test forbids scanning the historical root in steady state, verifies
  metadata retirement and restart recovery.
- 18 Lua native-render regressions and 18 converter/cache tests passed; Fabric
  build/tests and native mapping and D3D12 tests passed. After the host exited,
  the real DLL Lua API test also passed, including 1200 inactive Present callbacks,
  12 resets and 16 Lua recreations.

## In-game acceptance still required

At the same safe position, compare FPS after initial load and 10–20 F10 cycles.
Then walk/play for several minutes, place/break blocks, switch first/third person,
and spawn a golem. Existing lighting should remain; model IDs/resources should
stabilize for unchanged content, and pending requests should drain. Confirm F10
off restores native control and clears owned drawing/collisions.

Do not increase lifetime ceilings as a workaround, clear disk caches on every
toggle, recreate components on timers, or change the verified resource binding
path to address this regression.
