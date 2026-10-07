"""Production native draw sink: delayed readiness, exact receipts, edits and cleanup."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
objects={};created=0;destroyed=0;loaded=false;acks=0;released=0;ack_ok=true;results={};captures=0
function obj(methods)
 return {add_ref=function(self)return self end,release=function()end,
 call=function(_,m,...)assert(methods[m],m);return methods[m](...)end}
end
function create_go(name,folder)
 assert(folder=='folder');created=created+1
 local b={valid=true,draw=false,enabled=false};local go
 b.mesh=obj({set_Enabled=function(v)b.enabled=v end,set_StaticMesh=function(v)assert(v==false)end,
 setMesh=function()end,set_Material=function()end,set_RenderOutputID=function(v)assert(v==31)end,
 set_DrawShadowCast=function(v)assert(v)end,get_MeshReady=function()return loaded end,
 get_MaterialReady=function()return loaded end,get_MaterialNum=function()return 1 end})
 go=obj({get_Valid=function()return b.valid end,set_DrawSelf=function(v)b.draw=v end,
 get_Transform=function()return{set_position=function(_,p) b.p=p end}end,
 ['createComponent(System.Type)']=function(t)assert(t=='via.render.Mesh');return b.mesh end})
 b.go=go;objects[#objects+1]=b;return go
end
sdk={get_tdb_version=function()return 82 end,
 create_resource=function(t,p)local r=obj({});r.create_holder=function()return obj({})end;return r end,
 find_type_definition=function(t)return {get_runtime_type=function()return t end,get_method=function(_,m)
  return {call=function(_,_,...)
   if m=='create(System.String, via.Folder)'then return create_go(...)end
   assert(m=='destroy(via.GameObject)');local go=...;for _,b in ipairs(objects)do
    if b.go==go then assert(not b.draw and not b.enabled);destroyed=destroyed+1;b.dying=true;return end end
   error('foreign object')
  end}
 end}end}
Vector4f={new=function(x,y,z,w)return{x=x,y=y,z=z,w=w}end}
json={load_file=function(path)
 if path=='onimusha_mc/native_sections/worker.json'then return{state='ready',host_pid=777,alive_at=os.time()}end
 return results[path]
end}
callbacks={};re={on_application_entry=function(_,fn)callbacks.tick=fn end,on_script_reset=function(fn)callbacks.reset=fn end}
log={error=function(e)last_error=e end}
sample={ready=true,host_pid=777,epoch=81,world_id=9,mc_pid=1234,generation=1,jobs=0,
 sections={{sx=1,sy=2,sz=3,revision=10,vertices=3}}}
ctx={bridge={snapshot_sections=function()return sample end,capture_section=function(a)
 captures=captures+1;last_capture=a;return '777_100_'..captures end,
 ack_section=function(a)acks=acks+1;assert(a.mask=='01');return ack_ok and sample.sections[1] and a.revision==sample.sections[1].revision end,
 release_section=function()released=released+1 end},units=1,scene=1,epoch=81,world_id=9,mc_pid=1234,generation=1,folder='folder',
 to_native=function(x,y,z)return{x=x-10,y=y-20,z=z-30}end}
function advance(n,active)
 for i=1,n do if active~=false then onimusha_native_sections.update(ctx)end;callbacks.tick() end
 assert(not last_error,last_error)
end
function result(revision)
 results['onimusha_mc/native_sections/777_100_'..captures..'/result.json']={id='777_100_'..captures,ok=true,revision=revision,
 section={1,2,3},epoch=81,world=9,mc_pid=1234,generation=1,mask='01',asset_id='section_0123456789abcdef0123',seconds=.4}
end
function reap()for _,b in ipairs(objects)do if b.dying then b.valid=false end end;advance(12,false)end
''')
lua.execute((Path(__file__).resolve().parents[1]/'onimusha_native_sections.lua').read_text(encoding='utf-8'))
lua.execute(r'''
advance(20);assert(captures==1 and created==0 and acks==0)
result(10);advance(15);assert(created==1 and acks==0 and not objects[1].draw)
assert(objects[1].p.x==6 and objects[1].p.y==12 and objects[1].p.z==18)
loaded=true;advance(2);assert(objects[1].draw and objects[1].enabled and acks>0)
assert(onimusha_native_sections.status().ready==1)
print('PASS background capture + delayed native readiness + calibrated section placement precede overlay receipt')
advance(20);assert(created==1 and captures==1)
sample.sections[1].revision=11;advance(1);assert(destroyed==1 and not objects[1].draw)
advance(20);result(11);advance(15);assert(created==2 and onimusha_native_sections.status().ready==1)
print('PASS block edit removes stale native drawing before replacement receipt')
sample.sections={};advance(1);assert(destroyed==2 and onimusha_native_sections.status().count==0)
reap();assert(not onimusha_native_sections.busy())
print('PASS explosion/empty section removes native draw and holds wrappers through deferred destroy')
sample.sections={{sx=1,sy=2,sz=3,revision=11,vertices=3}};advance(2)
assert(created==3 and captures==2)
onimusha_native_sections.stop();assert(not objects[3].draw);reap();assert(not onimusha_native_sections.busy())
print('PASS F10 off clears native object; F10 resume reuses unchanged conversion without duplicate jobs')
advance(2);assert(created==4)
ack_ok=false;advance(1);assert(not objects[4].draw)
reap();ack_ok=true
advance(2);sample.epoch=80;advance(1);assert(onimusha_native_sections.status().count==0)
reap();sample.epoch=81
print('PASS receipt refusal and stale session both remove native geometry')
advance(2);advance(2,false);assert(onimusha_native_sections.status().count==0)
reap();advance(2);callbacks.reset();assert(onimusha_native_sections==nil)
print('PASS missing host tick and project reset clean up owned display objects')
''')
