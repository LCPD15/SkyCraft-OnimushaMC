"""Execute the adapter's actual seal lifecycle helpers in Lua 5.4."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/"onimusha_mc.lua").read_text(encoding="utf-8-sig")
fragment=source[source.index("local function capture_player_input_seals()"):source.index("local function fail_open(reason)")]
lua=LuaRuntime(unpack_returned_tuples=True)
run=lua.execute(r"""
local state
field_reads=0;field_writes=0;native_seals=0
local function required(fn,label) local ok,result=pcall(fn);if not ok then error(label..': '..tostring(result)) end;return result end
local function fields(obj) return obj.metadata end
local function typename(obj) return obj.name end
local function addr(obj) return obj.identity end
local function method(obj,name) return name=='sealAllPlayer' and obj.sealAllPlayer or nil end
local function strictcall(obj,name) obj[name](obj) end
local function object(identity,name,field_name,original)
 local obj={identity=identity,name=name,value=original}
 local f={get_name=function() return field_name end,get_type=function() return {get_full_name=function() return 'System.Boolean' end} end,
  get_data=function(_,o) field_reads=field_reads+1;return o.value end}
 obj.metadata={f};obj.add_ref=function() return obj end
 obj.get_field=function(self,key) field_reads=field_reads+1;return self[key] end
 obj.set_field=function(self,key,value)
  assert(key==field_name and type(value)=='boolean')
  field_writes=field_writes+1;self.value=value
 end
 return obj
end
local function managed_array(name,values)
 return {name=name,values=values,
  get_size=function(self) return self.count or #self.values end,
  get_element=function(self,index)
   assert(index>=0 and index<self:get_size() and index==math.floor(index))
   return self.values[index+1]
  end,
  get_elements=function() error('C++ vector conversion must not be used for input capture') end}
end
local function setup()
 field_reads=0;field_writes=0;native_seals=0
 local inputs,keys={},{}
 local manager={}
 for i,name in ipairs({'_PlayerInput','_PadPlayerInput','_MkbPlayerInput'}) do
  local input=object('input'..i,'app.Input','_SealAll',i==3)
  inputs[#inputs+1]=input
  local ka={object('falsekey'..i,'ace.cKeyBase','_IsSealed',false),object('truekey'..i,'ace.cKeyBase','_IsSealed',true)}
  for _,key in ipairs(ka) do keys[#keys+1]=key end
  input._Keys=managed_array('ace.cKeyBase[]',ka)
  manager[name]=managed_array('app.Input[]',{input})
 end
 manager.get_field=function(self,name) field_reads=field_reads+1;return self[name] end
 manager.sealAllPlayer=function()
  native_seals=native_seals+1
  for _,obj in ipairs(inputs) do obj.value=true end
  for _,obj in ipairs(keys) do obj.value=true end
 end
 state={input=manager}
 return inputs,keys
end
"""+fragment+r"""
return function()
 local inputs,keys=setup()
 seal_player_inputs();assert(native_seals==1)
 assert(state.input_seal_diagnostic.inputs==3 and state.input_seal_diagnostic.keys==6)
 restore_player_input_seals()
 assert(inputs[1].value==false and inputs[2].value==false and inputs[3].value==true)
 for i,key in ipairs(keys) do assert(key.value==(i%2==0)) end
 assert(field_writes==5) -- Only the two false input flags and three false key flags changed.
 local reads,writes=field_reads,field_writes
 restore_player_input_seals();assert(field_reads==reads and field_writes==writes)
 print('PASS exact false/true restoration and idempotent release')
 inputs,keys=setup();capture_player_input_seals()
 reads,writes=field_reads,field_writes
 restore_player_input_seals();assert(field_reads==reads and field_writes==writes and native_seals==0)
 print('PASS captured but never sealed does not restore')
 inputs,keys=setup();keys[1].metadata={}
 local ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('before sealing',1,true) and native_seals==0 and field_writes==0)
 assert(state.input_seal_diagnostic.captured==false)
 assert(inputs[1].value==false and inputs[3].value==true)
 print('PASS reflection failure refuses native seal')
 inputs,keys=setup();state.input._PlayerInput.count=17
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('array size',1,true) and native_seals==0 and field_writes==0)
 assert(state.input_seal_diagnostic.captured==false)
 print('PASS oversized managed input array refuses native seal')
 inputs,keys=setup();inputs[1]._Keys.count=513
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('array size',1,true) and native_seals==0 and field_writes==0)
 print('PASS oversized managed key array refuses native seal')
 inputs,keys=setup();state.input._PlayerInput.count=1;state.input._PlayerInput.values={}
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('Missing player input object',1,true) and native_seals==0 and field_writes==0)
 print('PASS null managed input slot refuses native seal')
 inputs,keys=setup();state.input._PlayerInput.name='app.Input'
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('array type',1,true) and native_seals==0 and field_writes==0)
 print('PASS non-array type refuses native seal')
 inputs,keys=setup();keys[1].set_field=nil
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('REManagedObject.set_field',1,true) and native_seals==0 and field_writes==0)
 print('PASS missing real managed setter refuses native seal')
 inputs,keys=setup();seal_player_inputs()
 inputs[1].set_field=function() field_writes=field_writes+1 end
 restore_player_input_seals()
 assert(#state.input_seal_diagnostic.errors==1 and state.input_seal_diagnostic.restore_writes==4)
 assert(state.input_seal_diagnostic.errors[1]:find('write failed readback',1,true))
 assert(state.input_seals and #state.input_seals.records==1 and state.input_seal_diagnostic.pending_records==1)
 ok,err=pcall(seal_player_inputs)
 assert(not ok and tostring(err):find('restoration remains pending',1,true) and native_seals==1)
 inputs[1].set_field=function(self,key,value)
  assert(key=='_SealAll' and type(value)=='boolean');field_writes=field_writes+1;self.value=value
 end
 restore_player_input_seals()
 assert(not state.input_seals and inputs[1].value==false and state.input_seal_diagnostic.pending_records==0)
 assert(state.input_seal_diagnostic.restore_writes==1)
 print('PASS failed input restore retains only failed owner and retry succeeds')
end
""")
run()
# Exercise the complete cold stage-A script, including discovery failure and reset.
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
callbacks={};mutation_calls=0;input_reads=0;input_writes=0;files={onimusha_mc_config={runtime_stage='A'}}
local function prohibit() mutation_calls=mutation_calls+1;error('mutation attempted') end
local saved={['onimusha_mc_config.json']={runtime_stage='A',diagnostic_only=true}}
json={load_file=function(name) return saved[name] end,dump_file=function(name,value) saved[name]=value end}
log={info=function() end,error=function() end}
sdk={get_managed_singleton=function() return nil end,get_tdb_version=function() return 82 end,
 hook=prohibit,create_instance=prohibit,create_resource=prohibit}
re={on_pre_application_entry=function(_,fn) callbacks.pre=fn end,on_application_entry=function(_,fn) callbacks.frame=fn end,
 on_draw_ui=function(fn) callbacks.ui=fn end,on_script_reset=function(fn) callbacks.reset=fn end}
imgui={tree_node=function() return false end}
onimusha_mc={status=function() return {enabled=false,connected=false} end,set_enabled=prohibit,submit_host=prohibit,set_camera=prohibit}
""")
lua.execute(source)
lua.execute('for i=1,600 do callbacks.pre();callbacks.frame() end;callbacks.ui();callbacks.reset();assert(mutation_calls==0 and input_reads==0 and input_writes==0)')
print('PASS cold stage A 600frames and reset never touch input flags')
print('INPUT_SEAL_REGRESSION_OK')
