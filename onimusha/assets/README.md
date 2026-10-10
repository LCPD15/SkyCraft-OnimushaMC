# Onimusha unit-box collider

`natives/stm/mod/onimusha_mc/unit_box.rcol.37` is newly generated unit-box geometry for this adapter, not a copied original game collision resource. It has one group, one request set and one Box shape with identity coordinates and half extents `(0.5, 0.5, 0.5)`.

It was serialized and read back through the MIT-licensed [RE-Engine-Lib](https://github.com/kagenocookie/RE-Engine-Lib) using `GameName.oniws`, RCOL version 37 and a copy of this game's local RSZ schema. RE-Engine-Lib and that schema are build inputs outside this Git repository. The generator is `onimusha/tools/UnitBoxCollider`; pass `-p:REELibRoot=<extracted library>` and two program arguments: a copied schema and output filename.

RCOL re-read validates its file structure, not native broadphase registration. The Lua adapter must load the resource, register its actual request IDs, retrieve the native collider and confirm an exact-identity ray hit. If that fails, it leaves block collision updates queued and reports the failure.

Only OnimushaWotS `.rcol.37` is targeted. Other RE games require their own version, RSZ schema, filters and registration validation.

MOD制作：LCPD15/LCPD拉灯

## Public release templates (0.2.0)

`probe/unit_collision.pfb.18` and its USER3 holder describe the tested private
unit collider. They are required by `onimusha_native_blocks.lua`; no original
enemy/level Prefab is distributed. `probe/mc_stone_cube.mdf2.51` contains the
verified neutral environment material parameters and references the host's
existing environment shader and null normal map. It contains no shader code.

Despite its historical filename, `probe/mc_stone_ALBD.tex.251111100` in the
repository is a generated **4×4 monochrome BC7 template**, not a stone texture
from either game. The converter uses its TEX header/layout and writes the
player's runtime-captured Minecraft pixels locally. Cached player appearances
are never included in the public release.
