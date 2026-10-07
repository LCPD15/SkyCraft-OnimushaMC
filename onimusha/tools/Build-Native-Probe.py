"""Build a standalone one-metre cube using Onimusha's verified asset layout.

Run with Blender --background --factory-startup --disable-autoexec --python.
Reference assets are read only. This is an isolated render probe, not MC chunks.
MOD制作：LCPD15/LCPD拉灯
"""
import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import sys
import zipfile
import ctypes
import struct

import bpy
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument('--addon', type=Path, required=True)
ap.add_argument('--reference', type=Path, required=True)
ap.add_argument('--out', type=Path, required=True)
ap.add_argument('--minecraft-jar', type=Path)
ap.add_argument('--tex-template', type=Path)
a = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
sys.dont_write_bytecode = True
sys.path.insert(0, str(a.addon.parent))
addon = importlib.import_module(a.addon.name)
addon.register()
fm = importlib.import_module(a.addon.name + '.modules.mesh.file_re_mesh')
pm = importlib.import_module(a.addon.name + '.modules.mesh.re_mesh_parse')
bm = importlib.import_module(a.addon.name + '.modules.mesh.blender_re_mesh')
mdf = importlib.import_module(a.addon.name + '.modules.mdf.file_re_mdf')
fm.meshFileVersionToNewVersionDict[260209350] = 135
fm.meshFileVersionToInternalVersionDict[260209350] = 250203152
fm.meshFileVersionToGameNameDict[260209350] = 'PRAG'
pm.SIX_WEIGHT_MESH_VERSIONS |= {260209350}

# Process-local MDF51 layout adaptation, never change the installed add-on.
source = Path(mdf.__file__).read_text(encoding='utf-8')
source = source.replace('self.MATERIAL_ENTRY_SIZE = 108', 'self.MATERIAL_ENTRY_SIZE = 104')
source = source.replace('self.textureCount = read_int(file)', 'self.onimushaPropertyValueCount = read_int(file)\n\t\tself.textureCount = read_int(file)')
source = source.replace('\t\tif version >= 51:\n\t\t\tself.ver51UnknOffset = read_uint64(file)\n', '')
source = source.replace('\t\twrite_int(file, self.textureCount)', '\t\twrite_int(file, getattr(self, "onimushaPropertyValueCount", sum(len(p.propValue) for p in self.propertyList)))\n\t\twrite_int(file, self.textureCount)')
source = source.replace('\t\tif version >= 51:\n\t\t\twrite_uint64(file, self.ver51UnknOffset)\n', '')
exec(compile(source, '<onimusha-mdf51-runtime>', 'exec'), mdf.__dict__)

a.out.mkdir(parents=True, exist_ok=True)
reference_mdf = next(a.reference.rglob('sm43_0012_07_a.mdf2.51'))
original_bytes = reference_mdf.read_bytes()
material_file = mdf.readMDF(str(reference_mdf))
report = {'reference': str(reference_mdf), 'reference_sha256': hashlib.sha256(original_bytes).hexdigest(),
          'materials': [{'name': m.materialName, 'shader': m.mmtrPath,
                         'textures': {t.textureType: t.texturePath for t in m.textureList},
                         'properties': {p.propName: p.propValue for p in m.propertyList}}
                        for m in material_file.materialList]}
material = copy.deepcopy(material_file.materialList[0])
material.materialName = 'OMC_Probe_Mat'
stem = 'unit_cube'
if a.minecraft_jar:
    sys.path.insert(0, str(Path(__file__).parent))
    from onimusha_raw_tex import write_from_dds, read_dds
    Texconv = importlib.import_module(a.addon.name + '.modules.ddsconv.directx.texconv').Texconv
    ctypes.windll.ole32.CoInitializeEx(None, 0)
    conv = Texconv()
    stem = 'mc_stone_cube'
    entry = 'assets/minecraft/textures/block/stone.png'
    with zipfile.ZipFile(a.minecraft_jar) as jar:
        png_bytes = jar.read(entry)
    png = a.out / 'mc_stone_source.png'
    png.write_bytes(png_bytes)
    source_image = bpy.data.images.load(str(png), check_existing=False)
    source_image.colorspace_settings.name = 'Non-Color'
    assert list(source_image.size) == [16, 16]
    pixels = np.rint(np.asarray(source_image.pixels[:]).reshape(16, 16, 4) * 255).astype(np.uint8)
    assert np.all(pixels[..., 3] == 255)
    # Preserve the actual MC texels; upscale by integer nearest neighbour so
    # native bilinear filtering only softens the very edge of each pixel.
    tga = a.out / 'mc_stone_ALBD.tga'
    enlarged = np.repeat(np.repeat(pixels, 16, axis=0), 16, axis=1)
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 256, 256, 32, 8)
    tga.write_bytes(header + enlarged[..., [2, 1, 0, 3]].tobytes())
    dds = conv.convert_to_dds(str(tga), 'BC7_UNORM_SRGB', out=str(a.out), no_mip=False, verbose=False)
    tex = a.out / 'mc_stone_ALBD.tex.251111100'
    verified = write_from_dds(dds, tex, a.tex_template)
    assert verified['mips'] == read_dds(dds)['mips']
    found = []
    for t in material.textureList:
        if t.textureType == 'BaseDielectricMap':
            t.texturePath = 'mod/onimusha_mc/probe/mc_stone_ALBD.tex'
            found.append(t.textureType)
        elif t.textureType == 'NormalRoughnessMap':
            # Stock neutral map already used by this environment shader family.
            # Do not retain the reference wood grain under MC's stone albedo.
            t.texturePath = 'systems/rendering/NullNormalRoughnessOcclusion.tex'
    assert found == ['BaseDielectricMap'], report['materials'][0]['textures']
    for p in material.propertyList:
        if p.propName == 'MetalScale': p.propValue = [0.]
    report['minecraft'] = {'jar': str(a.minecraft_jar), 'entry': entry,
                           'source_sha256': hashlib.sha256(png_bytes).hexdigest(),
                           'texture_sha256': hashlib.sha256(tex.read_bytes()).hexdigest(),
                           'mips': verified['mip_count'], 'raw_bc_readback_passed': True}
material_file.materialList = [material]
material_file.stringList = []
mdf_path = a.out / (stem + '.mdf2.51')
mdf.writeMDF(material_file, str(mdf_path))
back = mdf.readMDF(str(mdf_path))
assert back.materialList[0].materialName == material.materialName
assert back.materialList[0].mmtrPath == material.mmtrPath
assert [(t.textureType, t.texturePath) for t in back.materialList[0].textureList] == [(t.textureType, t.texturePath) for t in material.textureList]
assert reference_mdf.read_bytes() == original_bytes

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
col = bpy.data.collections.new('unit_cube.mesh')
col['~TYPE'] = 'RE_MESH_COLLECTION'
bpy.context.scene.collection.children.link(col)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
obj = bpy.context.object
for old in list(obj.users_collection):
    old.objects.unlink(obj)
col.objects.link(obj)
obj.name = 'Group_0_Sub_0__OMC_Probe_Mat'
for edge in obj.data.edges:
    edge.use_edge_sharp = True
uv = obj.data.uv_layers.active
for face in obj.data.polygons:
    for loop, xy in zip(face.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[loop].uv = xy
mat = bpy.data.materials.new('OMC_Probe_Mat')
obj.data.materials.append(mat)
tri = obj.modifiers.new('Triangles', 'TRIANGULATE')
bpy.ops.object.modifier_apply(modifier=tri.name)
mesh_path = a.out / (stem + '.mesh.260209350')
opts = dict(targetCollection=col.name, selectedOnly=False, exportAllLODs=True,
            exportBlendShapes=False, rotate90=True, useBlenderMaterialName=False,
            preserveBoneMatrices=True, exportBoundingBoxes=False,
            autoSolveRepeatedUVs=True, preserveSharpEdges=True)
assert bm.exportREMeshFile(str(mesh_path), opts) is not False
raw = fm.readREMesh(str(mesh_path))
parsed = pm.ParsedREMesh()
parsed.ParseREMesh(raw)
assert parsed.skeleton is None and not parsed.bufferHasWeight
subs = [s for l in parsed.mainMeshLODList for g in l.visconGroupList for s in g.subMeshList]
assert sum(len(s.faceList) for s in subs) == 12
vertices = np.asarray([v for s in subs for v in s.vertexPosList])
assert np.allclose(vertices.min(0), [-.5, -.5, -.5]) and np.allclose(vertices.max(0), [.5, .5, .5])
assert parsed.materialNameList == ['OMC_Probe_Mat']
report.update(passed=True, triangles=12, bounds=[vertices.min(0).tolist(), vertices.max(0).tolist()],
              files={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [mesh_path, mdf_path]})
(a.out / (stem + '_validation.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(a.out / (stem + '.blend')))
print('ONIMUSHA NATIVE CUBE VALIDATED', flush=True)
