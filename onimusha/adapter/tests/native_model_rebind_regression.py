"""Initial async holders stay unready; reacquiring holders may unblock the existing hidden mesh; this is a mock, not an engine lifetime test."""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r"""
sample.cubes={{x=1,y=2,z=3,kind=101}}
local counts={}
sdk.create_resource=function(t,path)
 counts[path]=(counts[path] or 0)+1
 local generation=counts[path];local r=obj({})
 r.create_holder=function()local h=obj({});h.generation=generation;return h end
 return r
end
local base=create_go
function create_go(name,folder)
 local go=base(name,folder);local b=objects[#objects];local old=b.mesh.call
 b.mesh.call=function(self,m,...)
  if m=='setMesh'then b.mesh_holder=(...);return end
  if m=='set_Material'then b.material_holder=(...);return end
  if m=='get_MeshReady'then return b.mesh_holder and b.mesh_holder.generation>=2 end
  if m=='get_MaterialReady'then return b.material_holder and b.material_holder.generation>=2 end
  return old(self,m,...)
 end
 return go
end
""")
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r"""
advance(35);assert(created==1 and #ack_rows==0)
advance(25);assert(created==2 and destroyed==1 and #ack_rows==1)
assert(onimusha_native_sections.status().resources_loading==0)
print('PASS holder rebind reuses the cold component; no bulk component replacement')
""")
