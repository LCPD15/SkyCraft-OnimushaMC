"""Run the production fatal-HP handoff against managed-action/ownership/restore boundaries."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'onimusha_mc.lua').read_text(encoding='utf-8-sig')
body = source[source.index('local function combat_diagnostic('):source.index('local function apply_combat_write(')]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local state,bridge,player,health,entity,die,groups,restore,requests,forced,order,action_type
local function attempt(fn) local ok,v=pcall(fn);if ok then return v end end
local function addr(o) return o and o.id end
local function same(a,b) return a==b end
local function typename(o) return o and o.kind or '' end
local function strictcall(o,n,...) return o:call(n,...) end
local function restoration_pending() return restore end
local function fail_open() state.active=false;order[#order+1]='release' end
local function td(n) return {get_field=function(_,f) return {get_data=function()
 assert(f=='NORMAL' or f=='DAMAGE');return f=='NORMAL' and 0 or 4 end} end} end
ValueType={new=function() return {set_field=function(self,k,v) self[k]=v end} end}
local function action(kind,style,owner)
 return {kind=kind,get_type_definition=function() return {is_a=function(_,base)
  assert(base=='app.PlayerCommonAction.cDieBase');return kind:match('%.cDie$')~=nil end} end,
 get_field=function(_,k) if k=='_OwnerCharacter' then return owner end;if k=='_Style' then return style end;error(k) end}
end
local function setup()
 restore=false;requests=0;forced=0;order={};action_type='app.PlayerOneHandedDamageAction.cMediumDamage'
 health={id=2,hp=39,call=function(self,n,v)
  if n=='get_Health' then return self.hp end;if n=='get_MaxHealth' then return 2000 end
  if n=='setHealth' then if not self.silent then self.hp=v end;return end
  if n=='checkHealthZero' then return end;error(n) end}
 player={id=1};die={call=function(self,n,...)
  if n=='get_IsRequested' then return self.requested or false end
  if n=='get_IsRequestRevive' then return self.revive or false end
  assert(n=='reqForceDie(app.CharacterDeadType.TYPE, via.GameObject)')
  assert(select('#',...)==2 and (...)==0);assert(not state.active)
  forced=forced+1;entity.deadtype=0;order[#order+1]='force' end}
 entity={deadtype=-1,call=function(self,n)
  if n=='get_DieSupporter' then return die end;if n=='get_DeadType' then return self.deadtype end;error(n) end}
 groups={ {action('app.PlayerBasicDamageAction.cDie',0,player)}, {},
  {action('app.PlayerOneHandedDamageAction.cDie',1,player)} }
 local items={get_element=function(_,i) local a=groups[i+1];return {get_elements=function() return a end} end}
 local list={get_field=function(_,k) return k=='_size' and #groups or items end}
 player.call=function(self,n,id,category)
  if n=='get_BaseActionController' then return {get_field=function() return list end} end
  if n=='get_BaseCurrentAction' then return action(action_type,1,player) end
  if n=='get_CharacterEntityHolder' then return {call=function() return entity end} end
  if n=='getActionFromID_Base(ace.ACTION_ID)' then
   if player.bad_id then return action('app.PlayerOneHandedDamageAction.cDie',1,{}) end
   return groups[id._Category+1][id._Index+1]
  end
  assert(n=='requestBaseAction(ace.ACTION_ID, app.CharacterDef.ACTION_REQUEST_CATEGORY)')
  assert(not state.active and not restore and category==4)
  requests=requests+1;order[#order+1]='action';return not self.reject
 end
 state={player=player,health=health,epoch=7,frame=10,health_bypass=0,health_revision=0,active=true}
 bridge={set_enabled=function(v) assert(v==false);order[#order+1]='disable' end}
end
''' + body + r'''
local function fatal() set_native_health(health,-39) end
setup();fatal();assert(state.death_pending and health.hp==0 and requests==0)
process_death_handoff(bridge,0,false,false,false)
assert(requests==1 and forced==1 and state.death_pending.action.category==2)
assert(table.concat(order,',')=='release,disable,force,action')
process_death_handoff(bridge,0,false,false,false);assert(requests==1 and forced==1)
print('PASS confirmed lethal HP releases ownership then requests actual loaded style death once')
setup();health.silent=true;fatal();assert(not state.death_pending)
setup();state.health={id=99};fatal();assert(not state.death_pending)
setup();health.hp=0;fatal();assert(not state.death_pending)
print('PASS failed readback, enemy health, and already-zero HP cannot queue native player death')
setup();fatal();restore=true;process_death_handoff(bridge,0,false,false,false);assert(requests==0)
restore=false;process_death_handoff(bridge,0,false,true,false);assert(requests==0)
process_death_handoff(bridge,0,false,false,true);assert(requests==0)
process_death_handoff(bridge,0,false,false,false);assert(requests==1)
print('PASS restore, menu and scripted scene gates defer mutation')
for _,mode in ipairs({'dying','requested','revive','action'}) do
 setup();fatal();die.requested=mode=='requested';die.revive=mode=='revive'
 if mode=='action' then action_type='app.PlayerCommonAction.cDie' end
 process_death_handoff(bridge,0,mode=='dying',false,false)
 assert(requests==0 and forced==0 and state.death_pending.outcome=='native_flow_observed')
end
print('PASS native death/revive already in progress is never restarted')
for _,mode in ipairs({'player','health','epoch','healed'}) do
 setup();fatal()
 if mode=='player' then state.player={id=99} elseif mode=='health' then state.health={id=99}
 elseif mode=='epoch' then state.epoch=8 end
 process_death_handoff(bridge,mode=='healed' and 1 or 0,false,false,false)
 assert(not state.death_pending and requests==0 and forced==0)
end
print('PASS retry or ownership/session change cancels stale death work')
setup();fatal();player.reject=true
assert(not pcall(process_death_handoff,bridge,0,false,false,false))
process_death_handoff(bridge,0,false,false,false);assert(requests==1 and forced==1)
setup();fatal();player.bad_id=true
assert(not pcall(process_death_handoff,bridge,0,false,false,false));assert(requests==0 and forced==0)
print('PASS rejected request is not retried; invalid action owner fails before any native death mutation')
''')
