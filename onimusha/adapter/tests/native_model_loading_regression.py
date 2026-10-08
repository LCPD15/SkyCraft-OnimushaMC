"""Cold resources are bounded; pause time and one broken kind don't revoke good blocks."""
from pathlib import Path
source=Path(__file__).with_name('native_models_regression.py').read_text(encoding='utf-8')
exec(source.rsplit("lua.execute((Path",1)[0])
lua.execute(r'''
local base=create_go
function create_go(name,folder)
 local go=base(name,folder);local old=go.call
 go.call=function(self,m,...)
  if m=='get_Folder'then return obj({get_Path=function()return 'test' end})end
  return old(self,m,...)
 end
 return go
end
paused=false
sdk.get_managed_singleton=function()return obj({get_IsMenuPause=function()return paused end,get_IsPlayerPause=function()return false end})end
sample.cubes={}
for i=1,20 do sample.cubes[i]={x=i,y=2,z=3,kind=100+i}end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_models.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(90)
assert(onimusha_native_sections.status().resources_loading==8 and created==8)
for _,b in ipairs(objects)do assert(not b.enabled and not b.draw)end
paused=true;advance(700)
assert(created==8 and destroyed==0 and next(onimusha_native_sections.status().resource_errors)==nil)
paused=false;sample.foreground=false;advance(700)
assert(created==8 and destroyed==0)
print('PASS at most eight hidden cold resources load; menu and background time do not consume timeout')
sample.foreground=true;loaded=true;advance(180)
assert(#ack_rows==20 and onimusha_native_sections.status().resources_loading==0)
print('PASS all twenty engine-owned appearances become ready without a timed rebind')
local before=captures;local releases_before=released
loaded=false;sample.cubes[21]={x=21,y=2,z=3,kind=121};advance(680)
assert(#ack_rows==20 and not onimusha_native_sections.status().error)
assert(onimusha_native_sections.status().resource_errors['121'] and captures==before+1)
assert(released==releases_before)
advance(680);assert(#ack_rows==20 and captures==before+1)
print('PASS one cold-load timeout preserves every existing receipt and does not loop rebind/rebuild')
onimusha_native_sections.stop();advance(15,false)
assert(not onimusha_native_sections.busy())
''')
