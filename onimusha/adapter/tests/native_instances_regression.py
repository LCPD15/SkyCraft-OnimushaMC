"""Real production instance module: shared assets/GO, edit readiness and 1280 cap."""
from pathlib import Path
# Reuse only the SDK test double, not the old merged renderer or its assertions.
source=Path(__file__).with_name('native_sections_regression.py').read_text(encoding='utf-8')
exec(source.split("lua.execute((Path")[0])
lua.execute(r'''
local base_json=json.load_file
json.load_file=function(p)
 if p=='onimusha_mc/native_block_library.json'then
  local t={items={}};for i=1,16 do t.items[tostring(i)]={asset_id='section_0123456789abcdef0123'}end;return t end
 return base_json(p)
end
resource_creates=0;local base_resource=sdk.create_resource
sdk.create_resource=function(...)resource_creates=resource_creates+1;return base_resource(...)end
owners={};onimusha_native_blocks={display_owner=function(x,y,z)return owners[x..':'..y..':'..z]end}
-- Match real C++ -> Lua numeric values; integer literals hid JSON "1" versus "1.0".
sample.cubes={{x=1,y=2,z=3,kind=1.0},{x=2,y=2,z=3,kind=1}}
function own(p)
 local go=create_go('owned collider','folder');go:call('set_DrawSelf',true)
 local o={go=go,ready=true};owners[p.x..':'..p.y..':'..p.z]=o;return o
end
for _,p in ipairs(sample.cubes)do own(p)end
ctx.bridge.snapshot_native_instances=function()return sample end
ctx.bridge.ack_native_instances=function(a)ack_rows=a.cubes;acks=acks+1;return ack_ok end
local old_advance=advance
function advance(n,active)
 for i=1,n do old_advance(1,active);for _,b in ipairs(objects) do if b.dying then b.valid=false end end end
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_instances.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(2);assert(created==3 and resource_creates==2 and #ack_rows==0)
assert(not objects[1].enabled and not objects[2].enabled)
assert(not objects[3].draw and not objects[3].enabled) -- only a hidden kind preloader exists yet
loaded=true;advance(1);assert(#ack_rows==2 and objects[1].enabled and objects[2].enabled)
advance(20);assert(created==3 and resource_creates==2 and destroyed==1)
print('PASS float/integer IDs share resources; one hidden preload GO per kind retires when ready')
sample.cubes[1]={x=1,y=2,z=3,kind=3.0};loaded=false;advance(1)
assert(not objects[1].enabled and objects[2].enabled and #ack_rows==1 and resource_creates==4)
loaded=true;advance(1);assert(#ack_rows==2 and objects[1].enabled and created==4)
print('PASS same-cell type change waits for new material and reuses existing Mesh component')
sample.cubes={};advance(12);assert(#ack_rows==0 and not objects[1].enabled and not objects[2].enabled and destroyed==2)
assert(objects[1].valid and objects[2].valid)
assert(not onimusha_native_sections.busy())
print('PASS break/TNT disables display but does not destroy collider-owner GameObject twice')
sample.cubes={};for i=1,1280 do local p={x=i,y=2,z=3,kind=1};sample.cubes[i]=p;own(p)end
local before=onimusha_native_sections.status().created;advance(1)
assert(onimusha_native_sections.status().created-before==4)
advance(320);assert(onimusha_native_sections.status().ready==1280 and #ack_rows==1280 and resource_creates==4)
print('PASS 1280 instances use bounded allocations and shared resources')
onimusha_native_sections.stop();assert(not onimusha_native_sections.busy());advance(2,false)
for _,b in ipairs(objects)do assert(not b.enabled)end
advance(322);assert(#ack_rows==1280 and created==1284 and resource_creates==4)
ack_ok=false;advance(1);assert(not onimusha_native_sections.busy())
print('PASS F10 off/on reuses owner Mesh components; refused receipt restores overlay without destroying physics')
ack_ok=true;sample.epoch=80;advance(1);assert(not onimusha_native_sections.busy());sample.epoch=81
advance(2);advance(2,false);assert(not onimusha_native_sections.busy())
callbacks.reset();assert(onimusha_native_sections==nil and destroyed==2)
print('PASS stale session, stopped host and script reload clean display ownership')
''')

# A cold kind times out independently; previously loaded kinds continue rendering.
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_instances.lua').read_text(encoding='utf-8'))
lua.execute(r'''
sample.cubes={{x=1,y=2,z=3,kind=1.0}};loaded=true;own(sample.cubes[1]);advance(15)
assert(#ack_rows==1)
local cold={x=3,y=2,z=3,kind=4.0};own(cold);sample.cubes[2]=cold
loaded=false;advance(615)
assert(#ack_rows==1 and onimusha_native_sections.status().ready==1)
assert(onimusha_native_sections.status().resource_errors['4']=='Resource preload timeout')
assert(not onimusha_native_sections.status().error)
onimusha_native_sections.stop();advance(12,false);assert(not onimusha_native_sections.busy())
callbacks.reset()
print('PASS cold-kind preload timeout preserves ready kinds and cleans hidden staging objects')
''')
