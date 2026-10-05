# Onimusha MC Fabric bridge

This fork preserves SkyCraft's Minecraft movement, F5 cameras, inventory, combat, block meshes,
items and transparent HUD. It targets **Onimusha: Way of the Sword only**; RE engine versions and
type names must be validated separately for any other game. Upstream credit: chasmlol / SkyCraft,
MIT. Onimusha adaptation credit: LCPD15/LCPD拉灯.

## Runtime and isolation

- Minecraft Java 26.3; Fabric Loader 0.19.5 or later; Fabric API 0.161.0+26.3; Java 25.
- Mod resource ID stays `skycraft`; do not also install upstream SkyCraft into the same instance.
- Isolated world name: `OnimushaMC`; isolated mapping: `Local\OnimushaMC_v1`, protocol version 12.
- Optional developer overrides: `-Donimusha.link=...`, `-Donimusha.unitsPerBlock=1.0`.
- Native terrain destruction is disabled. Normal placed Minecraft blocks remain placeable,
  mineable, droppable and collidable. This version has no e4mc relay dependency.

## Native state extension

Offsets relative to `OFF_SKY_STATE` (0x100) are identical in the C++ header and Java `Proto`:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x40 | float | Native current HP |
| 0x44 | float | Native maximum HP |
| 0x48 | double | Native engine units per MC block; host must calibrate all coordinates consistently |
| 0x50 | uint32 | Native HP revision, for diagnostics |
| 0x54 | uint32 | Reserved |

`SkyState` is 0x58 bytes, still within the reserved 0x100-byte region. Additional flags:
bit 3 authoritative HP; bit 4 native death; bit 5 native terrain protected; bit 6 MC owns look.
The host must not assert authoritative HP when maximum HP is zero, missing or non-finite.

## Health and damage contract

MC always uses ten base hearts (20 points):

`MC health = clamp(native current HP / native maximum HP, 0, 1) * 20`

Native snapshots are authoritative; neither joining, respawning, loading player NBT nor natural
Minecraft regeneration may restore native health. Explicit item/effect healing uses requests.
MC health boosts do not enlarge the ten-heart base display. Native death and save reload own the
respawn lifecycle; Minecraft does not drop inventory, remove its player after death or open its
own Respawn screen.

For Minecraft falls, lava, poison, etc., the standard MC damage pipeline calculates shield/armour
effects. The final `setHealth` mutation is intercepted and sent as `EV_HEALTH_CHANGE` (type 6):

| Event member | Meaning |
| --- | --- |
| formId | 0 |
| a | Signed fraction of **native maximum HP**, negative damage / positive healing |
| b | Signed MC health points (`a * 20`), diagnostic |
| c, d | 0 |
| flags | 1 damage / 2 healing |
| weapon (last uint32, +0x1C) | Collision epoch; reject events from another world/session |

The host applies `a * current_native_maximum` to native current HP through a recursion guard.
It must validate the epoch, finite values and gameplay readiness before accepting the request.
The MC heart display only changes when a subsequent host snapshot confirms the native result.
The Java side additionally captures the native process generation and collision epoch before
queuing a host attack on the server thread. Work from an earlier load/restart is rejected even if
the new process starts its epoch at one again. Teleport/readiness is reset on a new host generation,
and cached collision from an older generation cannot release the player.

For an incoming native attack to use **MC armour/shields**, the adapter must intercept the
native HP deduction **before it happens**, suppress that original deduction, and send input
type 7 (`IN_HURT`) with `HURT_HOST_UNAPPLIED` (bit 2, value 4):

- `a = round(nativeDamage / nativeMaximum * 20 * 100)`; damage points are already MC units.
- `code = HurtKind`, `b = attacker actor ID`, `c = HurtFlags | 4`.
- MC applies armour, shields and invulnerability, then posts the type-6 health request.
- Native damage that already changed HP must **not** carry flag 4. Such notifications are ignored
  for HP because their result is already present in the native snapshot.

An adapter that cannot prove a pre-deduction hook must leave native incoming damage intact and
report that MC defence is unavailable; it must never both apply native damage and flag it as
unapplied. Upstream `EV_PLAYER_DIED` must not kill the Onimusha player.

## Look input

When host flag bit 6 is set, MC owns yaw/pitch. Input type 9 (`IN_LOOK_DELTA`) carries raw signed
mouse pixel deltas in `a` and `b`; the normal MC mouse handler applies MC sensitivity/inversion.
On first join, a new host, or a changed teleport sequence, the existing host `yaw/pitch` fields
set both current and previous local view angles once. The integrated server sends an absolute
position-and-rotation teleport, so a saved MC view cannot override the new host view. Normal
MC-controlled frames preserve mouse look. Host yaw is wrapped and pitch clamped to [-90, 90];
non-finite components fall back to zero. The adapter must publish its intended initial view
(currently horizontal zero angles); deriving the native camera view is an adapter responsibility.
Input type 4 remains absolute viewport cursor coordinates for GUI interaction.
Its coordinates are normalized by the host viewport and converted to MC's logical
`Window.getScreenWidth/Height`, independently of framebuffer pixels or Windows DPI scaling.
The latest GUI position is replayed before mouse buttons because vanilla GUI changes recenter
the hidden mouse. Absolute GUI packets arriving after a screen closes do not turn the camera;
relative look packets arriving while a GUI is open do not move its inventory cursor.

## Build and verification

Set `JAVA_HOME` to a Java 25 JDK, then run `gradlew.bat build`. Optional local Maven mirror:
`ONIMUSHA_MAVEN_MIRROR`; Maven artifacts and checksums must come from official Fabric/Mojang
repositories. The mirror only avoids proxy transport issues; it does not change dependency
versions. Output: `build/libs/skycraft-onimusha-0.1.0-dev.jar`.

Unit tests cover native HP percentage conversion, invalid values, prevention of automatic
healing, explicit-heal limits, protocol byte layout, teleport-view ownership/bounds, GUI cursor
scaling/replay and the upstream ray/triangle collision
math. Passing these tests does not prove native scene collision, rendering hooks, camera
ownership, shield hit routing or save compatibility; those require live Onimusha tests.
The mirror save defaults to `OnimushaMC`; `-Donimusha.worldName=OnimushaMC-Smoke` isolates test
inventories, commands and placed blocks. This fork's authoritative HP contract currently supports
the local integrated-server owner; upstream multiplayer guests do not have this new HP protocol.
Native epoch/world changes clear their render store, so the MC exporter resends loaded blocks,
their solid occupancy and avatar data even when the MC level object itself remains unchanged.
