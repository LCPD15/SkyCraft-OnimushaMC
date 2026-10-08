"""Automatic-model receipts and display ownership, using the production Lua module."""
from pathlib import Path
source=Path(__file__).with_name('native_sections_regression.py').read_text(encoding='utf-8')
exec(source.split("lua.execute((Path")[0])
lua.execute(r'''
json.load_file=function(path)
 if path=='onimusha_mc/native_models/worker.json' then return {state='ready',host_pid=777,alive_at=os.time()} end
 return results[path]
end
owners={};onimusha_native_blocks={display_owner=function(x,y,z)return owners[x..':'..y..':'..z]end}
sample.cubes={{x=1,y=2,z=3,kind=101.0},{x=2,y=2,z=3,kind=101}}
ctx.bridge.snapshot_native_instances=function()return sample end
ctx.bridge.ack_native_instances=function(a)ack_rows=a.cubes;acks=acks+1;return ack_ok end
ctx.bridge.capture_native_model=function(a)
 captures=captures+1;local id='777_100_'..captures
 results['onimusha_mc/native_models/'..id..'/result.json']={id=id,ok=true,model=a.model,
 epoch=81,world=9,mc_pid=1234,generation=1,asset_id='section_0123456789abcdef0123',loader_version=1}
 return id
end
local old_advance=advance
dependencies_ready=true
sdk.create_resource=function()error('Unsafe direct resource path must not be used')end
sdk.is_managed_object=function(h)return h and h.engine_holder==true end
sdk.create_userdata_global=function(t,path)
 assert(t=='app.montage.data.MontagePartsModelData')
 local prefix=path:gsub('_loader.user$','')
 local mh=obj({get_ResourcePath=function()return prefix..'.mesh' end});mh.engine_holder=true
 local md=obj({get_ResourcePath=function()return prefix..'.mdf2' end});md.engine_holder=true
 local data=obj({})
 data.get_field=function(_,f)
  if not dependencies_ready then return nil end
  assert(f=='_Mesh' or f=='_Material');return f=='_Mesh' and mh or md
 end
 return data
end
function advance(n,active)
 for i=1,n do old_advance(1,active);for _,b in ipairs(objects)do if b.dying then b.valid=false end end end
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(30);assert(captures==1 and #ack_rows==0 and created==1)
assert(not objects[1].draw and not objects[1].enabled)
loaded=true;advance(15);assert(#ack_rows==2 and created==3 and destroyed==1)
assert(objects[2].p.x==-8.5 and objects[2].p.y==-17.5 and objects[2].p.z==-26.5)
print('PASS unknown model IDs auto-capture once; nonfull models get owned display at calibrated block center')
advance(10);assert(captures==1 and created==3)
sample.cubes={};advance(15);assert(#ack_rows==0 and destroyed==3 and not onimusha_native_sections.busy())
print('PASS two appearances share conversion; removal destroys only display-owned objects')
sample.cubes={{x=1,y=2,z=3,kind=101}}
local go=create_go('physics','folder');owners['1:2:3']={go=go,ready=true}
advance(3);assert(#ack_rows==1)
local display=objects[5];assert(display.draw and not objects[4].draw)
owners['1:2:3']=nil;objects[4].valid=false;advance(3)
assert(display.valid and display.draw and #ack_rows==1)
onimusha_native_sections.stop();advance(12,false);assert(destroyed==4 and not display.valid and not objects[4].enabled)
print('PASS independent display survives nearby collider retirement; disabling destroys only owned display')
advance(3);assert(#ack_rows==1 and captures==1)
sample.cubes[2]={x=2,y=2,z=3,kind=102};advance(20)
assert(captures==2 and #ack_rows==2)
sample.epoch=80;advance(15);assert(onimusha_native_sections.status().count==0)
sample.epoch=81;callbacks.reset();assert(onimusha_native_sections==nil)
print('PASS distinct model requests, F10 cache reuse, stale epoch and reset cleanup')
''')
