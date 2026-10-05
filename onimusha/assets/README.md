# Onimusha unit-box collider

`natives/stm/mod/onimusha_mc/unit_box.rcol.37` is newly generated unit-box geometry for this adapter, not a copied original game collision resource. It has one group, one request set and one Box shape with identity coordinates and half extents `(0.5, 0.5, 0.5)`.

It was serialized and read back through the MIT-licensed [RE-Engine-Lib](https://github.com/kagenocookie/RE-Engine-Lib) using `GameName.oniws`, RCOL version 37 and a copy of this game's local RSZ schema. RE-Engine-Lib and that schema are build inputs outside this Git repository. The generator is `onimusha/tools/UnitBoxCollider`; pass `-p:REELibRoot=<extracted library>` and two program arguments: a copied schema and output filename.

RCOL re-read validates its file structure, not native broadphase registration. The Lua adapter must load the resource, register its actual request IDs, retrieve the native collider and confirm an exact-identity ray hit. If that fails, it leaves block collision updates queued and reports the failure.

Only OnimushaWotS `.rcol.37` is targeted. Other RE games require their own version, RSZ schema, filters and registration validation.

MOD制作：LCPD15/LCPD拉灯
