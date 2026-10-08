"""Isolated dependency-loader probe waits for fields and owns them until teardown."""
from pathlib import Path
fixture=Path(__file__).with_name('native_object_probe_regression.py').read_text(encoding='utf-8')
exec(fixture.split('lua.execute(probe)')[0])
lua.execute(r'''
local prefix='mod/onimusha_mc/sections/section_0123456789abcdef0123/section_0123456789abcdef0123'
local function holder(t,path)
 local h=obj(t,{get_ResourcePath=function()return path end})
 h.get_reference_count=function()return 1 end;h.read_qword=function()return 400 end
 return h
end
local mh=holder('via.render.MeshResourceHolder',prefix..'.mesh')
local md=holder('via.render.MeshMaterialResourceHolder',prefix..'.mdf2')
dependency_ready=false
sdk.is_managed_object=function()return true end
sdk.create_resource=function()error('Direct resource creation is forbidden in this probe')end
sdk.create_userdata_global=function(t,path)
 assert(t=='app.montage.data.MontagePartsModelData' and path==prefix..'_loader.user')
 local data=obj(t,{})
 data.get_field=function(_,f)
  if not dependency_ready then return nil end
  assert(f=='_Mesh' or f=='_Material');return f=='_Mesh' and mh or md
 end
 return data
end
control={enabled=true,id='userdata1',action='render_userdata',asset_id='section_0123456789abcdef0123',section_min={x=0,y=0,z=0}}
collider_enabled=false
''')
lua.execute(probe)
lua.execute(r'''
frames(45);assert(status.phase=='loading_model_userdata' and render_creates==0 and not status.error)
paused=true;frames(700);assert(status.phase=='loading_model_userdata' and render_creates==0 and not status.error)
paused=false
dependency_ready=true;frames(3);assert(render_creates==1 and not draw)
mesh_ready=true;frames(30)
assert(status.ready and status.holder.factory=='engine_userdata' and draw)
control={enabled=true,id='remove-userdata',action='remove'};frames(45)
assert(not draw and status.destroyed and not status.error and destroys==1)
print('PASS engine-owned Mesh/MDF dependency fields gate display; no direct resource factory or physics')
print('PASS private loader remains owned through display lifetime and deferred teardown')
''')
