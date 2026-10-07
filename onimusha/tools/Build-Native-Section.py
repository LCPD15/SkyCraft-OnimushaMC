"""Offline REN_SECTION/REN_ATLAS -> one Onimusha MESH + MDF + TEX asset set.

Run with Blender --background --factory-startup --disable-autoexec --python-exit-code 1
--python this-file -- ... . No running-game API, installation, or world edit.
This is a format/axis/UV prototype, NOT the production chunk renderer.
MOD制作：LCPD15/LCPD拉灯
"""
import argparse
import ctypes
import hashlib
import importlib
import json
from pathlib import Path
import struct
import sys
import time
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from native_section_input import decode_section, decode_atlas, opaque_support, triangle_frame
from onimusha_raw_tex import write_from_dds, read_dds

_initialized=False

def initialize(a):
    global _initialized,fm,pm,mdf,conv
    if _initialized:return
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(a.addon.parent))
    addon = importlib.import_module(a.addon.name)
    addon.register()
    fm = importlib.import_module(a.addon.name+'.modules.mesh.file_re_mesh')
    pm = importlib.import_module(a.addon.name+'.modules.mesh.re_mesh_parse')
    mdf = importlib.import_module(a.addon.name+'.modules.mdf.file_re_mdf')
    fm.meshFileVersionToNewVersionDict[260209350] = 135
    fm.meshFileVersionToInternalVersionDict[260209350] = 250203152
    fm.meshFileVersionToGameNameDict[260209350] = 'PRAG'
    pm.SIX_WEIGHT_MESH_VERSIONS |= {260209350}
    # Verified Onimusha layout only; process-local adapter, installed add-on stays untouched.
    source = Path(mdf.__file__).read_text(encoding='utf-8')
    source = source.replace('self.MATERIAL_ENTRY_SIZE = 108', 'self.MATERIAL_ENTRY_SIZE = 104')
    source = source.replace('self.textureCount = read_int(file)', 'self.onimushaPropertyValueCount = read_int(file)\n\t\tself.textureCount = read_int(file)')
    source = source.replace('\t\tif version >= 51:\n\t\t\tself.ver51UnknOffset = read_uint64(file)\n', '')
    source = source.replace('\t\twrite_int(file, self.textureCount)', '\t\twrite_int(file, getattr(self, "onimushaPropertyValueCount", sum(len(p.propValue) for p in self.propertyList)))\n\t\twrite_int(file, self.textureCount)')
    source = source.replace('\t\tif version >= 51:\n\t\t\twrite_uint64(file, self.ver51UnknOffset)\n', '')
    exec(compile(source, '<onimusha-mdf51-runtime>', 'exec'), mdf.__dict__)

    ctypes.windll.ole32.CoInitializeEx(None,0)
    conv = importlib.import_module(a.addon.name+'.modules.ddsconv.directx.texconv').Texconv()
    _initialized=True

def build(a):
    initialize(a)
    started = time.perf_counter()
    section_bytes, atlas_bytes = a.section.read_bytes(), a.atlas.read_bytes()
    section = decode_section(section_bytes)
    w,h,rgba = decode_atlas(atlas_bytes)
    if max(w,h)*a.texel_scale > 4096:
        raise ValueError('Prototype output atlas exceeds 4096')
    opaque_support(section,w,h,rgba)
    frames = [triangle_frame(section.vertices[i:i+3]) for i in range(0,len(section.vertices),3)]
    # Include tool/template identities so later generation cannot silently overwrite a loaded resource.
    identity = hashlib.sha256(section_bytes+atlas_bytes+a.material_template.read_bytes()+a.tex_template.read_bytes()
        +Path(__file__).read_bytes()+Path(__file__).with_name('native_section_input.py').read_bytes()
        +str(a.texel_scale).encode()).hexdigest()
    stem = 'section_' + identity[:20]
    output = a.out / stem
    if output.exists():
        report=json.loads((output/'validation.json').read_text(encoding='utf-8'))
        for name,sha in report['files'].items():
            assert hashlib.sha256((output/name).read_bytes()).hexdigest()==sha
        return report


    material = mdf.readMDF(str(a.material_template))
    if len(material.materialList) != 1:
        raise ValueError('Expected the previously verified neutral stone material')
    m = material.materialList[0]
    if m.mmtrPath != 'MaterialShader/Master/Environment/Variation/V_Env_Base_ALP.mmtr':
        raise ValueError('Unverified material shader')
    m.materialName = 'OMC_Section_Mat'
    prefix = 'mod/onimusha_mc/sections/' + stem + '/' + stem
    textures = {t.textureType:t for t in m.textureList}
    textures['BaseDielectricMap'].texturePath = prefix + '.tex'
    if textures['NormalRoughnessMap'].texturePath != 'systems/rendering/NullNormalRoughnessOcclusion.tex':
        raise ValueError('Template retains a non-neutral normal map')
    properties = {p.propName:p.propValue for p in m.propertyList}
    if properties['MetalScale'] != [0.0] or properties['BaseColor'] != [1.0]*4:
        raise ValueError('Template albedo/metal parameters differ from verified material')

    parsed = pm.ParsedREMesh()
    parsed.materialNameList = [m.materialName]
    parsed.bufferHasPosition = parsed.bufferHasNorTan = parsed.bufferHasUV = True
    lod, group = pm.LODLevel(), pm.VisconGroup()
    lod.visconGroupList = [group]
    parsed.mainMeshLODList = [lod]
    positions = np.asarray([v[:3] for v in section.vertices])
    lo,hi = positions.min(0), positions.max(0)
    for i,axis in enumerate('xyz'):
        setattr(parsed.boundingBox.min,axis,float(lo[i]))
        setattr(parsed.boundingBox.max,axis,float(hi[i]))
        setattr(parsed.boundingSphere,axis,float((lo[i]+hi[i])*.5))
    parsed.boundingSphere.r = float(np.linalg.norm(hi-lo)*.5)
    # Split before the 16-bit submesh index limit; all submeshes share one atlas/material/GO.
    for start in range(0,len(section.vertices),65535):
        vertices = section.vertices[start:start+65535]
        sub = pm.SubMesh()
        sub.subMeshIndex = len(group.subMeshList)
        sub.vertexPosList = [v[:3] for v in vertices]  # MC XYZ = RE XYZ, Y up; no mirror or global offset.
        sub.uvList = [(v[3],1-v[4]) for v in vertices]  # Writer flips V; raw MESH retains MC top-first V.
        sub.faceList = [(i,i+1,i+2) for i in range(0,len(vertices),3)]
        normals, tangents = [], []
        for normal,tangent,sign in frames[start//3:(start+len(vertices))//3]:
            normals.extend([normal]*3)
            tangents.extend([tuple(int(round(c*127)) for c in tangent)+(sign*127,)]*3)
        sub.normalList = np.asarray(normals,dtype=np.float32)
        sub.tangentList = np.asarray(tangents,dtype=np.int8)
        group.subMeshList.append(sub)

    output.mkdir(parents=True)
    mesh_path = output/(stem+'.mesh.260209350')
    fm.writeREMesh(fm.ParsedREMeshToREMesh(parsed,260209350),str(mesh_path))
    back = pm.ParsedREMesh()
    back.ParseREMesh(fm.readREMesh(str(mesh_path)))
    subs = [s for l in back.mainMeshLODList for g in l.visconGroupList for s in g.subMeshList]
    np.testing.assert_array_equal(np.asarray([v for s in subs for v in s.vertexPosList]),positions)
    np.testing.assert_allclose(np.asarray([v for s in subs for v in s.uvList]),
                               [(v[3],1-v[4]) for v in section.vertices],atol=0.0005,rtol=0)
    np.testing.assert_allclose(np.asarray([v for s in subs for v in s.normalList]),
                               [f[0] for f in frames for _ in range(3)],atol=0.009,rtol=0)
    assert sum(len(s.faceList) for s in subs) == len(section.vertices)//3
    assert back.materialNameList == [m.materialName] and back.skeleton is None
    for expected,actual in zip(group.subMeshList,subs):
        np.testing.assert_array_equal(actual.faceList,expected.faceList)
    raw = fm.readREMesh(str(mesh_path))
    uv_element = next(e for e in raw.meshBufferHeader.vertexElementList if e.typing==2)
    wire_uv = np.frombuffer(raw.meshBufferHeader.vertexBuffer,dtype='<f2',count=len(section.vertices)*2,
                           offset=uv_element.posStartOffset).reshape(-1,2)
    np.testing.assert_allclose(wire_uv,[(v[3],v[4]) for v in section.vertices],atol=0.0005,rtol=0)
    mdf_path = output/(stem+'.mdf2.51')
    mdf.writeMDF(material,str(mdf_path))
    check = mdf.readMDF(str(mdf_path)).materialList[0]
    assert check.materialName == m.materialName
    assert next(t for t in check.textureList if t.textureType=='BaseDielectricMap').texturePath == prefix+'.tex'

    pixels = np.frombuffer(rgba,dtype=np.uint8).reshape(h,w,4)
    pixels = np.repeat(np.repeat(pixels,a.texel_scale,axis=0),a.texel_scale,axis=1)
    tga = output/(stem+'.tga')
    tga.write_bytes(struct.pack('<BBBHHBHHHHBB',0,0,2,0,0,0,0,0,w*a.texel_scale,h*a.texel_scale,32,0x28)
                   +pixels[:,:,[2,1,0,3]].tobytes())
    dds = conv.convert_to_dds(str(tga),'BC7_UNORM_SRGB',out=str(output),no_mip=True,verbose=False)
    tex_path = output/(stem+'.tex.251111100')
    tex = write_from_dds(dds,tex_path,a.tex_template)
    assert tex['mip_count']==1 and tex['mips']==read_dds(dds)['mips']
    report = dict(offline_validation_passed=True,game_tested=False,source_kind=a.source_kind,
        source_section_sha256=hashlib.sha256(section_bytes).hexdigest(),source_atlas_sha256=hashlib.sha256(atlas_bytes).hexdigest(),
        section=list(section.key),mc_origin=list(section.origin),bounds=[lo.tolist(),hi.tolist()],
        vertices=len(section.vertices),triangles=len(section.vertices)//3,submeshes=len(subs),material_count=1,
        mesh_path=prefix+'.mesh',material_path=prefix+'.mdf2',texture_path=prefix+'.tex',
        limits=['offline only; no runtime connection','opaque, untinted vertices only','one mip; no atlas mip gutters',
                'no animated textures or native emissive','neutral normals; tangent sign still needs live visual check',
                'no overlay suppression until native readiness and revision are acknowledged'],
        seconds=round(time.perf_counter()-started,3),
        files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (mesh_path,mdf_path,tex_path)})
    (output/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return report

if __name__=='__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--addon', type=Path, required=True)
    ap.add_argument('--section', type=Path, required=True, help='REN_SECTION payload including 16-byte header')
    ap.add_argument('--atlas', type=Path, required=True, help='REN_ATLAS payload including 8-byte header')
    ap.add_argument('--material-template', type=Path, required=True)
    ap.add_argument('--tex-template', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--source-kind', choices=['synthetic-fixture', 'runtime-capture'], required=True)
    ap.add_argument('--texel-scale', type=int, choices=[1,2,4,8,16], default=1)
    a = ap.parse_args(sys.argv[sys.argv.index('--')+1:])
    print(json.dumps(build(a),ensure_ascii=False),flush=True)
