"""Changing a held item must not rebuild unchanged body faces at new stream offsets."""
from pathlib import Path
source=Path(__file__).with_name('native_dynamic_regression.py').read_text(encoding='utf-8')
exec(source.split('# OFFLINE MOCK ONLY:')[0])
lua.execute(r'''
local read=json.load_file
json.load_file=function(path)
 if path=='onimusha_native_dynamic_control.json'then return {enabled=true,streams={avatar=true,scene=true,hands=true}}end
 return read(path)
end
sample.cubes={};sample.lights={};dynamic.avatar={};dynamic.scene={};dynamic.hands={}
for i=0,19 do dynamic.avatar[#dynamic.avatar+1]={first=i*6,kind=101+(i%2),x=i,y=6,z=7,qw=1,qx=0,qy=0,qz=0,sx=.5,sy=1}end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
loaded=true;advance(80);assert(#dynamic_rows.avatar==20)
local created_before=created;local destroyed_before=destroyed;local captures_before=captures
for _,p in ipairs(dynamic.avatar)do p.first=p.first+600;p.x=p.x+1 end
advance(1)
assert(#dynamic_rows.avatar==20 and created==created_before and destroyed==destroyed_before and captures==captures_before)
assert(onimusha_native_sections.status().dynamic_reused==20)
print('PASS body-list offset shift reuses all twenty live objects without conversion, rebind or fallback')
-- Swap different kinds at existing keys, exercising a cycle in the remapping.
for _,p in ipairs(dynamic.avatar)do p.kind=p.kind==101 and 102 or 101 end
advance(1);assert(#dynamic_rows.avatar==20 and created==created_before and destroyed==destroyed_before)
assert(onimusha_native_sections.status().dynamic_reused==40)
table.remove(dynamic.avatar);advance(15);assert(#dynamic_rows.avatar==19 and destroyed==destroyed_before+1)
print('PASS cyclic remapping never destroys a reassigned object; only genuinely removed faces retire')

-- New DLL stable identities span flat-list reorders and in-place hurt tint.
dynamic.stable_faces=true
for i,p in ipairs(dynamic.avatar)do p.id=i;p.tint=0xffffffff end
advance(2);created_before=created;destroyed_before=destroyed
local tint_updates=0
for _,b in ipairs(objects)do
 local original=b.mesh.call
 b.mesh.call=function(self,m,...)
  if m=='getMaterialVariableName'then return 'BaseColor' end
  if m=='getMaterialVariableType'then return 4 end
  if m=='setMaterialFloat4'then local _,_,v=...;b.tint=v;tint_updates=tint_updates+1;return end
  return original(self,m,...)
 end
end
for _,p in ipairs(dynamic.avatar)do p.first=p.first+600;p.tint=0xff8c8cff end
advance(1)
assert(created==created_before and destroyed==destroyed_before and tint_updates==19 and #dynamic_rows.avatar==19)
for i,row in ipairs(dynamic_rows.avatar)do assert(row.id==i)end
for _,p in ipairs(dynamic.avatar)do p.tint=0xffffffff;p.sx=.8;p.sy=1.3 end
advance(1)
assert(created==created_before and destroyed==destroyed_before and tint_updates==38)
print('PASS stable face receipts, hurt tint/reset and animated scale never reconstruct objects')
onimusha_native_sections.stop();advance(15,false);assert(not onimusha_native_sections.busy())
''')
