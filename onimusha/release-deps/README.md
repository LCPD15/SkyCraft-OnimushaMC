# RE Mesh Editor conversion dependency

This directory preserves the tested **RE Mesh Editor 0.66** source tree and its
supporting conversion libraries, authored by NSA Cloud. It is loaded in a
separate Blender process. Source: https://github.com/NSACloud/RE-Mesh-Editor

`RE-Mesh-Editor/LICENSE.GPL` applies to this component. Its DDS converter is
credited to matyalatte / Blender-DDS-Addon in `modules/ddsconv/credit.txt`;
additional library licenses are reproduced in
`modules/ddsconv/directx/THIRD_PARTY_LICENSES.txt`.

The snapshot excludes local bytecode and updater state. It includes the tested
source rather than downloading an unpinned latest version during installation.
Onimusha's format overrides live in `../tools/Build-Native-Section.py`, not as
undocumented edits to the user's installed Blender addon.

The root project's MIT license does not replace this component's license.
