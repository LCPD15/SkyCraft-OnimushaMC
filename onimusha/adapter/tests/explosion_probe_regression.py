"""Exercise the actual passive barrel probe without native mutation."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
src=(Path(__file__).resolve().parents[1]/'onimusha_combat_inventory.lua').read_text(encoding='utf-8-sig')
probe=src[src.index("do\nlocal CONTROL='onimusha_explosion_probe_control.json'"):]
probe=probe.replace('-- END EXPLOSION PROBE', '')
probe=probe.rsplit('\nend',1)[0]+"\n_G.probe_test={state=e,tick=tick,plans=plans}\nend\n"
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
local id=0
function typ(o) return o and o:get_type_definition():get_full_name() end
function fields(o)
 local r={};for n,_ in pairs(o.f or {}) do r[#r+1]={get_name=function() return n end,get_data=function() return o.f[n] end} end;return r
end
function obj(name,methods,f)
 id=id+1;local a=id
 local o={f=f or {},get_address=function() return a end}
 o.get_type_definition=function() return {get_full_name=function() return name end,is_value_type=function() return false end,
  is_a=function(_,n) return name==n or (name=='app.AppShell' and n=='ace.ShellBase') end,
  get_method=function(_,n) return methods[n] and {} or nil end} end
 o.call=function(_,n,...) assert(methods[n],n);assert(not n:match('^set'),'Mutating method forbidden');return methods[n](...) end
 o.get_field=function(_,n) return o.f[n] end
 return o
end
local pos={x=1,y=2,z=3}
go=obj('via.GameObject',{get_Valid=function() return true end,get_Name=function() return 'barrel' end,
 get_Transform=function() return {get_position=function() return pos end} end})
controller=obj('ace.cShellCreateController',{})
mini=obj('app.mcGimmickCreateShell',{}, {['<_ShellCreateController>k__BackingField']=controller})
gm=obj('app.Gm019_001',{get_GameObject=function() return go end}, {_State=0,_McGimmickCreateShell=mini,_ShellCreateController=controller})
sc=obj('via.Scene',{['findComponents(System.Type)']=function(t) return {get_elements=function() return t=='app.Gm019' and {gm} or {} end} end})
local shgo=obj('via.GameObject',{get_Valid=function() return true end,get_Name=function() return 'explosion' end,
 get_Transform=function() return {get_position=function() return pos end} end})
shell=obj('app.AppShell',{get_ShellOwner=function() return go end,get_GameObject=function() return shgo end})
info=obj('app.cShellShootingInfo',{}, {StartPos={x=1,y=2,z=3,w=1}})
control={id='one',enabled=true};enabled=false;hooks={};outputs={};callbacks={}
_G.onimusha_mc={status=function() return {enabled=enabled} end}
json={load_file=function() return control end,dump_file=function(_,value) outputs[#outputs+1]=value end}
re={on_application_entry=function(_,fn) callbacks[#callbacks+1]=fn end,on_script_reset=function(fn) reset=fn end}
local storage={};thread={get_hook_storage=function() return storage end}
sdk={get_tdb_version=function() return 82 end,get_native_singleton=function() return 1 end,
 call_native_func=function() return sc end,is_managed_object=function(x) return type(x)=='table' and x.get_address~=nil end,
 to_managed_object=function(x) return x end,to_int64=function(x) return x end}
sdk.find_type_definition=function(t)
 return {get_runtime_type=function() return t end,get_method=function(_,sig)
  local ret=sig:match('^getExplosionShellID') and 'System.Int32' or
   (sig:match('^shootShell') or sig:match('^createGmShell') or sig:match('^createChildShell')) and 'ace.ShellBase' or 'System.Void'
  return {t=t,sig=sig,get_function=function() return t..sig end,is_static=function() return false end,
   get_return_type=function() return {get_full_name=function() return ret end} end}
 end}
end
sdk.hook=function(m,pre,post) hooks[#hooks+1]={m=m,pre=pre,post=post} end
function findhook(type,name)
 for _,h in ipairs(hooks) do if h.m.t==type and h.m.sig:sub(1,#name)==name then return h end end
 error('Missing hook')
end
""")
lua.execute(probe)
lua.execute(r"""
local e=probe_test.state;probe_test.tick();assert(e.armed and e.status=='armed_read_only' and #hooks==14 and #e.target_list==1)
print('PASS exact reflected plans arm without invoking game mutations')
local h=findhook('ace.cShellCreateController','shootShell')
local other=obj('ace.cShellCreateController',{})
assert(h.pre({[2]=other,[3]=5,[4]=info})==nil);assert(h.post(shell)==shell and #e.events==0)
print('PASS unrelated native shell creation is filtered by current scene ownership')
assert(h.pre({[2]=controller,[3]=5,[4]=info})==nil);assert(h.post(shell)==shell)
assert(#e.events==2 and e.events[1].int_arg==5 and e.events[2].shell.type=='app.AppShell')
assert(e.shells[shell:get_address()] and e.profiles[tostring(gm:get_address())])
assert(e.events[1].argument.fields.StartPos.w==1)
print('PASS barrel creation captures ID, full quaternion and shell identity while preserving returns')
local n=#e.events;enabled=true;h.pre({[2]=controller,[3]=5,[4]=info});assert(h.post(shell)==shell and #e.events==n)
for i=1,30 do probe_test.tick() end;assert(not e.armed and e.status=='takeover_enabled')
print('PASS takeover cancels observation and never skips native calls')
enabled=false;control={id='two',enabled=true};for i=1,30 do probe_test.tick() end
assert(e.armed and #hooks==14)
local g=findhook('app.Gm019_001','getExplosionShellID');g.pre({[2]=gm});assert(g.post(5)==5)
for i=1,631 do probe_test.tick() end
assert(not e.armed and e.status=='capture_complete')
print('PASS rearm does not duplicate hooks and capture stops after explosion tail')
reset();assert(not e.armed and next(e.targets)==nil)
print('PASS reset removes owned references and disarms')
print('EXPLOSION_PROBE_REGRESSION_OK 6 groups')
""")
