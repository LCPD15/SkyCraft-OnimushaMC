"""Replacing the failed timed-rebind scheme: only engine-deserialized holders bind once."""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r"""
sample.cubes={{x=1,y=2,z=3,kind=101}};dependencies_ready=false
mesh_binds=0
local base=create_go
function create_go(name,folder)
 local go=base(name,folder);local b=objects[#objects];local old=b.mesh.call
 b.mesh.call=function(self,m,...)
  if m=='setMesh' then
   local holder=(...);assert(holder.engine_holder);mesh_binds=mesh_binds+1;return
  end
  return old(self,m,...)
 end
 return go
end
""")
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r"""
advance(80);assert(created==0 and mesh_binds==0 and #ack_rows==0)
dependencies_ready=true;advance(80);assert(created==1 and mesh_binds==1 and #ack_rows==0)
loaded=true;advance(10);assert(created==2 and destroyed==1 and mesh_binds==2 and #ack_rows==1)
advance(120);assert(created==2 and mesh_binds==2 and #ack_rows==1)
print('PASS dependency readiness gates GO creation; each preloader/display binds its engine holder once')
onimusha_native_sections.stop();advance(15,false);assert(not onimusha_native_sections.busy())
advance(5);assert(#ack_rows==1 and captures==1)
print('PASS F10 cache reuse retains engine loader and creates only the display object')
""")
