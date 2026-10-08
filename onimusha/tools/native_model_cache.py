"""Persistent Onimusha model cache, keyed by content and converter identity, never session IDs."""
import hashlib
import json
from pathlib import Path
import re
from native_worker_io import atomic_json


class ModelCache:
    def __init__(self, root, fingerprint):
        self.root=Path(root)
        self.index=self.root/'cache-v2'
        self.fingerprint=fingerprint
        self.index.mkdir(parents=True,exist_ok=True)
        self.digests={}

    def digest_file(self,path):
        path=Path(path);stat=path.stat();version=(stat.st_size,stat.st_mtime_ns)
        cached=self.digests.get(path)
        if cached and cached[0]==version:return cached[1]
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if len(self.digests)>=1024:self.digests.clear()
        self.digests[path]=(version,digest)
        return digest

    def key(self,raw,atlas_path,animated,white_flash=False):
        data=dict(schema=2,game='OnimushaWotS-TDB82',converter=self.fingerprint,
                  model=hashlib.sha256(raw).hexdigest(),atlas=self.digest_file(atlas_path),
                  animated=sorted(animated),white_flash=bool(white_flash))
        return hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()

    def _valid_files(self,value):
        asset=value.get('asset_id','');files=value.get('files',{})
        if not re.fullmatch(r'section_[a-f0-9]{20}',asset) or not isinstance(files,dict):return False
        expected={asset+ext for ext in ('.mesh.260209350','.mdf2.51','.tex.251111100')}
        if set(files)!=expected:return False
        return all(re.fullmatch(r'[a-f0-9]{64}',sha) and self.digest_file(self.root/asset/name)==sha
                   for name,sha in files.items())

    def load(self,key):
        if not re.fullmatch(r'[a-f0-9]{64}',key):raise ValueError('Invalid cache key')
        try:
            value=json.loads((self.index/(key+'.json')).read_text(encoding='utf-8'))
            if value.get('key')!=key or value.get('converter')!=self.fingerprint:return None
            if value.get('schema')!=2 or not self._valid_files(value):return None
            return value
        except (OSError,ValueError,TypeError,AttributeError):return None

    def store(self,key,asset,files,details):
        if not re.fullmatch(r'[a-f0-9]{64}',key):raise ValueError('Invalid cache key')
        value=dict(schema=2,key=key,converter=self.fingerprint,asset_id=asset,files=files,details=details)
        if not self._valid_files(value):raise ValueError('Cannot cache incomplete or changed resources')
        return atomic_json(self.index/(key+'.json'),value)


def converter_fingerprint(tool_dir,templates,addon,blender_version):
    """Changes to pixel sampling, RE format code, templates or writer invalidate old entries."""
    tool_dir=Path(tool_dir);addon=Path(addon)
    paths=[tool_dir/name for name in ('native_model_input.py','native_section_input.py',
        'Build-Native-Section.py','onimusha_raw_tex.py')]
    paths+=list(templates)
    # Include the writer version without depending on its installation directory.
    paths+=[addon/name for name in ('__init__.py','modules/mesh/file_re_mesh.py',
        'modules/mesh/re_mesh_parse.py','modules/mdf/file_re_mdf.py','modules/ddsconv/directx/texconv.py')]
    identity=hashlib.sha256(('OnimushaWotS-TDB82/mesh260209350/mdf51/tex251111100/texel4/'+blender_version).encode())
    for p in paths:identity.update(hashlib.sha256(Path(p).read_bytes()).digest())
    return identity.hexdigest()
