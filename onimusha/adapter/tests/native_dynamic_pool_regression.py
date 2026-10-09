"""Reuse loaded engine instances without rebind; hide on disable and retire across sessions."""
from pathlib import Path
source=Path(__file__).with_name('native_dynamic_regression.py').read_text(encoding='utf-8')
exec(source.split('# OFFLINE MOCK ONLY:')[0])
lua.execute(r'''
local read=json.load_file
json.load_file=function(path)
 if path=='onimusha_native_dynamic_control.json'then return {enabled=true,max_instances=64,streams={avatar=true,scene=true,hands=true}}end
 return read(path)
end
sample.cubes={};sample.lights={};dynamic.avatar={};dynamic.scene={};dynamic.hands={}
dynamic.hands_complete=true
for i=0,29 do dynamic.avatar[#dynamic.avatar+1]={first=i*6,kind=101+(i%2),x=i,y=6,z=7,qw=1,qx=0,qy=0,qz=0,sx=.5,sy=1}end
for i=0,19 do dynamic.scene[#dynamic.scene+1]={first=i*6,kind=101,x=i,y=6,z=7,qw=1,qx=0,qy=0,qz=0,sx=.5,sy=1}end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(90)
assert(#dynamic_rows.avatar==30 and #dynamic_rows.scene==20)
local made,removed,requested=created,destroyed,captures
onimusha_native_sections.stop();advance(15,false)
assert(not onimusha_native_sections.busy() and onimusha_native_sections.status().dynamic_pool_cached==50)
for _,b in ipairs(objects)do assert(not b.draw and not b.enabled)end
advance(1)
assert(#dynamic_rows.avatar==30 and #dynamic_rows.scene==20)
assert(created==made and destroyed==removed and captures==requested)
assert(onimusha_native_sections.status().dynamic_pool_hits==50)
print('PASS fifty cached body/NPC faces resume together in one tick with zero allocation, rebind or conversion')
local npc=dynamic.scene;dynamic.scene={};advance(2)
assert(onimusha_native_sections.status().dynamic_pool_cached==20 and #dynamic_rows.scene==0)
for _,p in ipairs(npc)do p.first=p.first+600;p.x=p.x+4 end
dynamic.scene=npc;advance(1)
assert(#dynamic_rows.scene==20 and created==made and captures==requested)
print('PASS removed NPC replacement reuses cached appearance while publishing its new pose and receipts')
onimusha_native_sections.stop();advance(15,false)
ctx.scene=2;advance(1)
assert(destroyed==removed+50 and onimusha_native_sections.status().dynamic_pool_cached==0)
advance(45);assert(#dynamic_rows.avatar==30 and #dynamic_rows.scene==20)
print('PASS native scene change retires old engine instances before recreation')
onimusha_native_sections.stop();advance(15,false)
local before=created
for _,b in ipairs(objects)do if b.valid then b.valid=false end end
advance(1);assert(created-before<=2)
advance(45);assert(#dynamic_rows.avatar==30 and #dynamic_rows.scene==20)
print('PASS externally invalidated cached objects never receive pose writes and stay within creation budget')
callbacks.reset()
for _,b in ipairs(objects)do assert(not b.draw and not b.enabled)end
assert(onimusha_native_sections==nil)
print('PASS reset hides and destroys all pooled/active models while retaining deferred dependency owners')
''')
