"""Bound staged entity rendering, resource-only preload and independent failure cleanup."""
from pathlib import Path
source=Path(__file__).with_name('native_dynamic_regression.py').read_text(encoding='utf-8')
exec(source.split('# OFFLINE MOCK ONLY:')[0])
lua.execute(r'''
local read=json.load_file
control={enabled=true,preload_only=true,max_instances=64,per_frame=2,streams={avatar=true,hands=true,scene=true}}
json.load_file=function(path)if path=='onimusha_native_dynamic_control.json'then return control end;return read(path)end
sample.lights={};sample.cubes={{x=1,y=2,z=3,kind=101}}
dynamic.avatar={};dynamic.scene={};dynamic.hands={};dynamic.hands_complete=true
for i=0,19 do dynamic.avatar[#dynamic.avatar+1]={first=i*6,kind=101,x=5,y=6,z=7,qw=1,qx=0,qy=0,qz=0,sx=.5,sy=1}end
dynamic.hands={{first=0,kind=101,x=1,y=2,z=3,qw=1,qx=0,qy=0,qz=0,sx=.2,sy=.4}}
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(80)
local s=onimusha_native_sections.status()
assert(s.dynamic_streams.avatar.resources_ready==20 and s.dynamic_objects==0 and #dynamic_rows.avatar==0 and #ack_rows==1)
print('PASS preload requests engine-owned resources only; MC dynamic drawing is not suppressed')
control.preload_only=false
for i=1,50 do
 local before=onimusha_native_sections.status().dynamic_created
 advance(1)
 assert(onimusha_native_sections.status().dynamic_created-before<=2)
end
s=onimusha_native_sections.status();assert(s.dynamic_objects==21 and #dynamic_rows.avatar==20 and #dynamic_rows.hands==1)
assert(#ack_rows==1)
print('PASS staged activation never allocates more than two dynamic objects in one frame')
control.enabled=false;advance(45)
assert(onimusha_native_sections.status().dynamic_objects==0 and #dynamic_rows.avatar==0 and #dynamic_rows.hands==0 and #ack_rows==1)
print('PASS disabling only dynamic rendering restores all entity streams without removing native blocks')
control.enabled=true;control.max_instances=6;advance(70)
assert(onimusha_native_sections.status().dynamic_objects==6 and #dynamic_rows.hands==1)
onimusha_native_sections.stop();advance(15,false)
assert(not onimusha_native_sections.busy() and onimusha_native_sections.status().dynamic_pool_cached==6)
for _,b in ipairs(objects)do assert(not b.draw and not b.enabled)end
callbacks.reset();advance(15,false)
print('PASS live instance cap, first-person priority and F10 hidden cache / full reset teardown')
''')
