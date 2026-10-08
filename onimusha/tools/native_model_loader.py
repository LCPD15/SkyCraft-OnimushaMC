"""Onimusha TDB82 USER3 dependency owner, generated/read back with REE-Lib.

Patch only fixed-width private resource IDs; all RSZ offsets/types stay intact.
No subprocess per model and no overwrite of a resource the engine may cache.
"""
from functools import lru_cache
import hashlib
import os
from pathlib import Path
import re

TEMPLATE_ID='section_00000000000000000000'
TEMPLATE_SHA256='6b8e8ecfa62205139d4348892a9a334ba34864324f974fc3ba6edfb9d5c204ec'
LOADER_VERSION=1

@lru_cache(maxsize=1)
def template():
    data=(Path(__file__).parent/'assets'/(TEMPLATE_ID+'_loader.user.3')).read_bytes()
    if hashlib.sha256(data).hexdigest()!=TEMPLATE_SHA256:
        raise ValueError('Onimusha USER3 loader template hash mismatch')
    assert data.count(TEMPLATE_ID.encode('utf-16le'))==8
    return data

def loader_bytes(asset_id):
    if not re.fullmatch(r'section_[a-f0-9]{20}',asset_id):
        raise ValueError('Invalid private asset ID')
    return template().replace(TEMPLATE_ID.encode('utf-16le'),asset_id.encode('utf-16le'))

def ensure_loader(folder,asset_id):
    path=folder/(asset_id+'_loader.user.3');data=loader_bytes(asset_id)
    if path.exists():
        if path.read_bytes()!=data:raise ValueError('Refuse to overwrite cached loader: '+str(path))
    else:
        temp=path.with_suffix('.3.tmp');temp.write_bytes(data);os.replace(temp,path)
    return path.name,hashlib.sha256(data).hexdigest()

def add_loader(game,asset_id,files):
    folder=game/'natives/stm/mod/onimusha_mc/sections'/asset_id
    if not folder.is_dir():raise ValueError('Missing converted asset directory')
    name,sha=ensure_loader(folder,asset_id)
    return dict(files,**{name:sha})
