"""TNT flash has independent cached MDF ownership, without new live face instances."""
from pathlib import Path
source=Path(__file__).with_name('native_dynamic_regression.py').read_text(encoding='utf-8')
exec(source.split('# OFFLINE MOCK ONLY:')[0])
lua.execute(r'''
local read=json.load_file
json.load_file=function(path)
 if path=='onimusha_native_dynamic_control.json'then return{enabled=true,streams={scene=true}}end
 return read(path)
end
local capture=ctx.bridge.capture_native_model
ctx.bridge.capture_native_model=function(a)
 local id=capture(a);local result=results['onimusha_mc/native_models/'..id..'/result.json']
 result.white_flash=a.white_flash
 if a.white_flash then result.asset_id='section_1123456789abcdef0123' end
 return id
end
sample.cubes={};sample.lights={};dynamic.avatar={};dynamic.hands={};dynamic.stable_faces=true
dynamic.scene={{id=101,first=0,kind=101,x=1,y=2,z=3,sx=1,sy=1,qw=1,qx=0,qy=0,qz=0,white_flash=true}}
local base=create_go
live_binds=0;material_binds=0
function create_go(name,folder)
 local go=base(name,folder);local b=objects[#objects];local call=b.mesh.call
 local go_call=go.call
 go.call=function(self,m,...)
  local value=go_call(self,m,...)
  if m=='get_Transform' then
   local tc=value.call
   value.call=function(self,m,...)
    if m=='get_Scale' then return b.scale end
    return tc(self,m,...)
   end
  end
  return value
 end
 b.mesh.call=function(self,m,...)
  if name:match('^OMC_Dynamic_') and m=='setMesh' then live_binds=live_binds+1 end
  if name:match('^OMC_Dynamic_') and m=='set_Material' then material_binds=material_binds+1;b.mdf=(...):call('get_ResourcePath') end
  return call(self,m,...)
 end
 return go
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(100)
assert(#dynamic_rows.scene==1 and live_binds==1 and captures==2)
local instance
for _,b in ipairs(objects)do if b.valid and b.name=='OMC_Dynamic_scene:101' then instance=b end end
assert(instance and instance.mdf:find('section_1123'))
local before=created;local cap=captures;local mat=material_binds
for i=1,12 do
 dynamic.scene[1].white_flash=i%2==0
 dynamic.scene[1].sx=.5+i*.1;dynamic.scene[1].sy=1+i*.01
 advance(1);assert(#dynamic_rows.scene==1 and instance.draw and live_binds==1)
end
assert(created==before and captures==cap and material_binds==mat+12)
assert(math.abs(instance.scale.x-1.7)<1e-6 and math.abs(instance.scale.y-1.12)<1e-6)
print('PASS cached white/base MDF alternates with continuous pose/receipt and no conversion or Mesh replacement')
dynamic.scene={};advance(15);assert(instance.valid and not instance.draw and not instance.enabled and not onimusha_native_sections.busy())
assert(onimusha_native_sections.status().dynamic_pool_cached==1)
onimusha_native_sections.stop();advance(15,false)
callbacks.reset();advance(15,false);assert(not instance.valid)
print('PASS TNT removal caches the hidden object; reset retires it with dependency ownership intact')
''')
