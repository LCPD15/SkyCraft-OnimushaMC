"""A single display bind exception must not clear already accepted native instances."""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r'''
local base=create_go
function create_go(name,folder)
 local go=base(name,folder);local b=objects[#objects];local old=b.mesh.call
 if name=='OMC_Model_3:2:3' then
  b.mesh.call=function(self,m,...)
   if m=='setMesh' then error('simulated failed new appearance') end
   return old(self,m,...)
  end
 end
 return go
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(40);assert(#ack_rows==2)
local a,b=objects[2],objects[3];local releases_before=released
sample.cubes[3]={x=3,y=2,z=3,kind=102};advance(80)
local s=onimusha_native_sections.status()
assert(#ack_rows==2 and a.draw and b.draw and a.valid and b.valid)
assert(not s.error and s.resource_errors['102']:find('simulated failed new appearance'))
assert(released==releases_before and s.count==2)
print('PASS new appearance bind exception retires only its object; old native blocks and receipts survive')
onimusha_native_sections.stop();advance(15,false);assert(not onimusha_native_sections.busy())
''')
