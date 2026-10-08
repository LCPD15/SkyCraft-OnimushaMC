#include "Bridge.hpp"
#include "CollisionPacking.hpp"
#include "InputRouting.hpp"
#include "Renderer.hpp"
#include "NativeSectionMailbox.hpp"
#include "vendor/reframework/API.h"
extern "C" {
#include "vendor/lua/lua.h"
#include "vendor/lua/lauxlib.h"
}
#include <Windowsx.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <future>
#include <chrono>

namespace omc {
namespace {
std::mutex mutex;
Bridge bridge;
RenderStore store;
NativeSectionMailbox sectionMailbox;
OverlayFrame overlay;
CameraState camera;
proto::SkyState host{};
proto::McState mc{};
const REFrameworkPluginInitializeParam* api{};
bool enabled=false,ready=false,collisionReady=false,cameraReady=false,routed=false;
std::uint64_t submittedMs{};
std::uint64_t observedCollisionGeneration{};
bool reUiOpen{},reUiSampled{};
HWND window{};
MouseInputRouter mouseRouter;
bool pendingGuiCursor=false;
bool pendingRelease=false;
std::uint16_t surrogate{};
using RegionKey=std::array<std::int32_t,6>;
std::map<RegionKey,std::vector<proto::ColTri>> collisionRegions;
struct PackedTerrain {
    proto::ColRegion region{};
    std::vector<proto::ColTri> triangles;
    std::vector<CollisionPacket> packets;
    std::string error;
    double ms{};
    bool ok{};
};
std::future<PackedTerrain> terrainWorker;
std::uint64_t terrainTicket{},terrainGeneration{},terrainBaseSeq{},terrainPublishedSeq{};
std::uint32_t terrainPid{},terrainEpoch{};
std::string terrainState="idle",terrainError;
void cache_collision(const proto::ColRegion&,std::vector<proto::ColTri>);
void poll_terrain_worker(){
    if(!terrainWorker.valid()||terrainWorker.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return;
    auto result=terrainWorker.get();const auto current=bridge.collision_status();
    bridge.collisionPackMs=result.ms;bridge.collisionPackMaxMs=std::max(bridge.collisionPackMaxMs,result.ms);
    if(current.generation!=terrainGeneration||current.mcPid!=terrainPid||host.collisionEpoch!=terrainEpoch
        ||current.publishSeq!=terrainBaseSeq||!current.connected||!current.ringValid){
        terrainState="discarded";terrainError="Terrain context changed while packing";return;
    }
    if(!result.ok){++bridge.rejected;++bridge.collisionPackFailures;terrainState="failed";
        terrainError=bridge.collisionFailure=bridge.error=result.error;return;}
    if(!bridge.publish_packed_collision(terrainEpoch,std::move(result.packets))){terrainState="failed";terrainError=bridge.collisionFailure;return;}
    cache_collision(result.region,std::move(result.triangles));
    terrainPublishedSeq=bridge.collision_status().publishSeq;terrainState="published";terrainError.clear();
}

double number(lua_State* L,int table,const char* key,double fallback=0){lua_getfield(L,table,key);int valid{};const auto n=lua_tonumberx(L,-1,&valid);lua_pop(L,1);return valid&&std::isfinite(n)?n:fallback;}
bool valid_number(lua_State* L,int table,const char* key,double& value){lua_getfield(L,table,key);int valid{};value=lua_tonumberx(L,-1,&valid);lua_pop(L,1);return valid&&std::isfinite(value);}
bool boolean(lua_State* L,int table,const char* key,bool fallback=false){lua_getfield(L,table,key);const bool v=lua_isnil(L,-1)?fallback:lua_toboolean(L,-1)!=0;lua_pop(L,1);return v;}
void nfield(lua_State* L,const char* key,double n){lua_pushnumber(L,n);lua_setfield(L,-2,key);}
void ifield(lua_State* L,const char* key,std::uint64_t n){lua_pushinteger(L,lua_Integer(n));lua_setfield(L,-2,key);}
void bfield(lua_State* L,const char* key,bool n){lua_pushboolean(L,n);lua_setfield(L,-2,key);}
void sfield(lua_State* L,const char* key,const char* s){lua_pushstring(L,s);lua_setfield(L,-2,key);}
void release();
void sync_collision_generation(const CollisionStatus& state){
    if(!state.ringValid)collisionReady=false;
    if(observedCollisionGeneration==state.generation)return;observedCollisionGeneration=state.generation;
    collisionReady=false;collisionRegions.clear();store.collisionTriangles.clear();++store.collisionRevision;
    if(routed||mouseRouter.known_mode())release();
}
const char* not_ready_reason(const CollisionStatus* supplied=nullptr){
    const auto state=supplied?*supplied:bridge.collision_status();sync_collision_generation(state);reUiSampled=false;
    // Keep the exact former active() gate order and its short-circuited UI query.
    if(!enabled)return "disabled";if(!ready)return "host_not_ready";if(!collisionReady)return "collision_not_ready";
    if(!cameraReady)return "camera_not_ready";if(!renderer::ready())return "renderer_not_ready";
    if(!state.connected)return "mc_disconnected";if(!(mc.flags&proto::kMcInWorld))return "mc_not_in_world";
    if(mc.teleportAck!=host.teleportSeq)return "teleport_ack_mismatch";if(!submittedMs)return "host_missing";
    const auto now=GetTickCount64();if(now<submittedMs||now-submittedMs>=500)return "host_stale";
    if(!(host.flags&proto::kSkyInGame))return "host_not_in_game";if(host.flags&proto::kSkyMenuOpen)return "host_menu";
    if(host.flags&proto::kSkyLoading)return "host_loading";
    if(api&&api->functions){reUiOpen=api->functions->is_drawing_ui();reUiSampled=true;if(reUiOpen)return "reframework_ui";}
    return nullptr;
}
bool active(){return not_ready_reason()==nullptr;}
void release(){pendingRelease=!bridge.input(proto::kInReleaseAll);routed=false;mouseRouter.release();pendingGuiCursor=false;renderer::set_gui_cursor(false);surrogate=0;}
bool retry_pending_release(){if(pendingRelease)pendingRelease=!bridge.input(proto::kInReleaseAll);return !pendingRelease;}
bool publish_gui_cursor(){
    const auto& cursor=mouseRouter.cursor();if(!cursor.known())return false;
    pendingGuiCursor=!bridge.input(proto::kInCursor,0,int(cursor.u()*host.viewportW),int(cursor.v()*host.viewportH));
    if(pendingGuiCursor)return false;renderer::set_gui_cursor(true,cursor.u(),cursor.v());return true;
}
void sync_input_mode(bool gui){
    if(!mouseRouter.sync_mode(gui))return;
    pendingGuiCursor=false;
    if(gui)publish_gui_cursor();else renderer::set_gui_cursor(false);
}
int submit(lua_State* L){
    if(!lua_istable(L,1)){lua_pushboolean(L,false);return 1;}std::scoped_lock lock(mutex);
    proto::SkyState s{};s.flags=std::uint32_t(number(L,1,"flags"));const bool requestedReady=boolean(L,1,"ready");
    double hpCurrent{},hpMaximum{},x{},y{},z{};
    const bool validHealth=valid_number(L,1,"health_current",hpCurrent)&&valid_number(L,1,"health_max",hpMaximum)&&hpMaximum>0&&hpMaximum<1e12&&hpCurrent>=0&&hpCurrent<1e12;
    const bool validPosition=valid_number(L,1,"x",x)&&valid_number(L,1,"y",y)&&valid_number(L,1,"z",z)&&std::abs(x)<30'000'000&&std::abs(y)<30'000'000&&std::abs(z)<30'000'000;
    ready=requestedReady&&validHealth&&validPosition;
    if(ready)s.flags|=proto::kSkyInGame;else s.flags&=~proto::kSkyInGame;
    if(boolean(L,1,"menu"))s.flags|=proto::kSkyMenuOpen;
    if(boolean(L,1,"loading"))s.flags|=proto::kSkyLoading;
    s.flags&=~(1u<<3);s.flags|=(1u<<5)|(1u<<6);if(validHealth)s.flags|=1u<<3;
    s.worldId=std::uint32_t(number(L,1,"world_id"));s.collisionEpoch=std::uint32_t(number(L,1,"epoch"));
    s.posX=number(L,1,"x");s.posY=number(L,1,"y");s.posZ=number(L,1,"z");s.yaw=float(number(L,1,"yaw"));s.pitch=float(std::clamp(number(L,1,"pitch"),-90.0,90.0));
    s.teleportSeq=std::uint32_t(number(L,1,"teleport_seq"));s.viewportW=std::uint32_t(std::clamp(number(L,1,"viewport_w",1920),1.0,double(proto::kMaxOverlayW)));s.viewportH=std::uint32_t(std::clamp(number(L,1,"viewport_h",1080),1.0,double(proto::kMaxOverlayH)));
    s.gameHour=float(number(L,1,"game_hour",12));
    s.healthCurrent=validHealth?float(hpCurrent):0;s.healthMax=validHealth?float(hpMaximum):0;
    s.healthCurrent=std::min(s.healthCurrent,s.healthMax);s.hostUnitsPerBlock=std::clamp(number(L,1,"units_per_block",1),0.001,1000.0);s.healthRevision=std::uint32_t(number(L,1,"health_revision"));
    if(validHealth&&s.healthCurrent<=0)s.flags|=1u<<4;
    if(host.collisionEpoch!=s.collisionEpoch){bridge.invalidate_collision();collisionReady=false;store.clear();store.collisionTriangles.clear();collisionRegions.clear();++store.collisionRevision;cameraReady=false;release();}
    s.flags&=~proto::kSkyNativeHandsReady;
    if(enabled&&ready&&mc.cameraMode==0&&store.hands_ready(GetTickCount64()))s.flags|=proto::kSkyNativeHandsReady;
    host=s;submittedMs=GetTickCount64();const bool ok=bridge.publish_host(s)&&(!requestedReady||ready);if(!active()&&(routed||mouseRouter.known_mode()))release();lua_pushboolean(L,ok);return 1;
}
int read_mc(lua_State* L){
    std::scoped_lock lock(mutex);proto::McState s{};if(!bridge.read_mc(s)){lua_pushnil(L);return 1;}lua_createtable(L,0,28);
    nfield(L,"x",s.x);nfield(L,"y",s.y);nfield(L,"z",s.z);nfield(L,"yaw",s.yaw);nfield(L,"pitch",s.pitch);nfield(L,"eye_x",s.eyeX);nfield(L,"eye_y",s.eyeY);nfield(L,"eye_z",s.eyeZ);nfield(L,"eye_height",s.eyeHeight);nfield(L,"fov",s.fovDeg);nfield(L,"camera_mode",s.cameraMode);nfield(L,"camera_distance",s.cameraDistance);nfield(L,"flags",s.flags);nfield(L,"teleport_ack",s.teleportAck);nfield(L,"frame",double(s.frameCounter));
    bfield(L,"on_ground",s.flags&proto::kMcOnGround);bfield(L,"screen_open",s.flags&proto::kMcScreenOpen);bfield(L,"in_world",s.flags&proto::kMcInWorld);bfield(L,"dead",s.flags&proto::kMcDead);return 1;
}
int drain_events(lua_State* L){
    std::scoped_lock lock(mutex);auto events=bridge.events();lua_createtable(L,int(events.size()),0);int i=1;
    for(const auto& e:events){lua_createtable(L,0,9);nfield(L,"type",e.type);nfield(L,"form_id",e.formId);nfield(L,"a",e.a);nfield(L,"b",e.b);nfield(L,"c",e.c);nfield(L,"d",e.d);nfield(L,"flags",e.flags);nfield(L,"weapon",e.weapon);nfield(L,"epoch",e.weapon);lua_rawseti(L,-2,i++);}return 1;
}
int set_enabled(lua_State* L){std::scoped_lock lock(mutex);enabled=lua_toboolean(L,1)!=0;if(!enabled){release();store.invalidate_native_views();}lua_pushboolean(L,enabled);return 1;}
int send_hurt(lua_State* L){
    if(!lua_istable(L,1)){lua_pushboolean(L,false);return 1;}std::scoped_lock lock(mutex);
    const auto points=std::clamp(number(L,1,"mc_points"),0.0,10000.0);const auto kind=std::uint16_t(std::clamp(number(L,1,"kind"),0.0,3.0));
    const bool ok=active()&&points>0&&bridge.input(proto::kInHurt,kind,std::int32_t(std::llround(points*100)),std::int32_t(number(L,1,"attacker_id")),std::int32_t(number(L,1,"flags"))|4);
    lua_pushboolean(L,ok);return 1;
}
int status(lua_State* L){
    std::scoped_lock lock(mutex);poll_terrain_worker();const auto state=bridge.collision_status();const auto* reason=not_ready_reason(&state);const auto now=GetTickCount64();lua_createtable(L,0,48);
    bfield(L,"collision_async_supported",true);ifield(L,"collision_job_id",terrainTicket);sfield(L,"collision_job_state",terrainState.c_str());
    sfield(L,"collision_job_error",terrainError.c_str());ifield(L,"collision_job_publish_seq",terrainPublishedSeq);
    bfield(L,"connected",state.connected);bfield(L,"enabled",enabled);bfield(L,"ready",reason==nullptr);sfield(L,"not_ready_reason",reason?reason:"ready");
    bfield(L,"host_ready",ready);bfield(L,"collision_ready",collisionReady);bfield(L,"camera_ready",cameraReady);bfield(L,"renderer_ready",renderer::ready());
    nfield(L,"host_age_ms",submittedMs&&submittedMs<=now?double(now-submittedMs):-1);nfield(L,"mc_heartbeat_age_ms",state.heartbeatAgeMs);bfield(L,"re_ui_open",reUiOpen);bfield(L,"re_ui_sampled",reUiSampled);
    ifield(L,"mc_pid",state.mcPid);ifield(L,"collision_epoch",host.collisionEpoch);ifield(L,"collision_generation",state.generation);ifield(L,"collision_publish_seq",state.publishSeq);ifield(L,"collision_consumed_seq",state.consumedSeq);
    ifield(L,"collision_batch_end",state.batchEnd);ifield(L,"collision_head",state.head);ifield(L,"collision_tail",state.tail);bfield(L,"collision_ring_valid",state.ringValid);
    nfield(L,"collision_pack_ms",bridge.collisionPackMs);nfield(L,"collision_pack_max_ms",bridge.collisionPackMaxMs);ifield(L,"collision_pack_failures",bridge.collisionPackFailures);ifield(L,"collision_queue_failures",bridge.collisionQueueFailures);sfield(L,"collision_failure",bridge.collisionFailure.c_str());
    bfield(L,"gui_cursor_known",mouseRouter.cursor().known());nfield(L,"gui_cursor_u",mouseRouter.cursor().u());nfield(L,"gui_cursor_v",mouseRouter.cursor().v());bfield(L,"gui_cursor_raw",mouseRouter.cursor().raw());bfield(L,"raw_look",mouseRouter.raw_look());nfield(L,"gui_raw_packets",double(mouseRouter.guiRawPackets));nfield(L,"gui_raw_dx",double(mouseRouter.guiRawDx));nfield(L,"gui_raw_dy",double(mouseRouter.guiRawDy));nfield(L,"gui_fallback_packets",double(mouseRouter.guiFallbackPackets));nfield(L,"gui_open_count",double(mouseRouter.guiOpens));nfield(L,"look_raw_packets",double(mouseRouter.lookRawPackets));nfield(L,"protocol",proto::kVersion);nfield(L,"rejected",double(bridge.rejected));nfield(L,"render_invalid",double(store.invalidMessages));nfield(L,"sections",double(store.sections.size()));nfield(L,"textures",double(store.textures.size()));nfield(L,"overlay_frame",double(overlay.frameId));sfield(L,"error",bridge.error.c_str());sfield(L,"mapping","Local\\OnimushaMC_v1");return 1;
}
int publish_actors(lua_State* L){
    if(!lua_istable(L,1)){lua_pushboolean(L,false);return 1;}std::scoped_lock lock(mutex);const auto count=std::min(lua_rawlen(L,1),std::size_t(proto::kMaxActors));std::vector<proto::ActorRecord> rows;rows.reserve(count);
    for(std::size_t i=1;i<=count;i++){lua_rawgeti(L,1,lua_Integer(i));if(lua_istable(L,-1)){const int t=lua_gettop(L);proto::ActorRecord r{};r.formId=std::uint32_t(number(L,t,"id"));r.flags=std::uint32_t(number(L,t,"flags"));r.x=float(number(L,t,"x"));r.y=float(number(L,t,"y"));r.z=float(number(L,t,"z"));r.yaw=float(number(L,t,"yaw"));r.width=float(std::clamp(number(L,t,"width",0.6),0.05,100.0));r.height=float(std::clamp(number(L,t,"height",1.8),0.05,100.0));r.healthFrac=float(std::clamp(number(L,t,"health_frac",1),0.0,1.0));r.level=std::uint16_t(std::clamp(number(L,t,"level",1),1.0,65535.0));lua_getfield(L,t,"name");if(const char* n=lua_tostring(L,-1))strncpy_s(r.name,n,_TRUNCATE);lua_pop(L,1);if(r.formId)rows.push_back(r);}lua_pop(L,1);}lua_pushboolean(L,bridge.publish_actors(rows));return 1;
}
int publish_tris(lua_State* L){
    if(!lua_istable(L,1)){lua_pushboolean(L,false);return 1;}std::scoped_lock lock(mutex);proto::ColRegion region{};const char* boundNames[]={"min_x","min_y","min_z","max_x","max_y","max_z"};double boundValues[6]{};
    for(int i=0;i<6;i++)if(!valid_number(L,1,boundNames[i],boundValues[i])||std::abs(boundValues[i])>kMaxCollisionCoordinate){bridge.error="Collision bounds must be finite and within 30 million blocks";lua_pushboolean(L,false);return 1;}
    region.minX=int(boundValues[0]);region.minY=int(boundValues[1]);region.minZ=int(boundValues[2]);region.maxX=int(boundValues[3]);region.maxY=int(boundValues[4]);region.maxZ=int(boundValues[5]);const auto epoch=std::uint32_t(number(L,1,"epoch"));
    lua_getfield(L,1,"triangles");if(!lua_istable(L,-1)||lua_rawlen(L,-1)>100000||epoch!=host.collisionEpoch||region.minX>region.maxX||region.minY>region.maxY||region.minZ>region.maxZ){lua_pop(L,1);lua_pushboolean(L,false);return 1;}
    const int table=lua_gettop(L);const auto count=lua_rawlen(L,table);std::vector<proto::ColTri> tris;tris.reserve(count);const char* names[]={"ax","ay","az","bx","by","bz","cx","cy","cz"};
    for(std::size_t i=1;i<=count;i++){lua_rawgeti(L,table,lua_Integer(i));if(lua_istable(L,-1)){proto::ColTri t{};for(int j=0;j<9;j++)t.v[j]=float(number(L,lua_gettop(L),names[j]));t.flags=std::uint32_t(number(L,lua_gettop(L),"flags"))&~proto::kTriDiggable;tris.push_back(t);}lua_pop(L,1);}lua_pop(L,1);
    if(boolean(L,1,"async")){
        poll_terrain_worker();const auto current=bridge.collision_status();
        if(tris.empty()||terrainWorker.valid()||!current.connected||!current.ringValid){lua_pushboolean(L,false);return 1;}
        region.epoch=epoch;
        try{
            terrainWorker=std::async(std::launch::async,[region,rows=std::move(tris)]() mutable {
                PackedTerrain r;r.region=region;r.triangles=std::move(rows);const auto start=std::chrono::steady_clock::now();
                // Numeric owned copies only. No SDK calls, Lua, shared memory, or rendering on this thread.
                try{r.ok=pack_collision(region,r.triangles,r.packets,r.error);}catch(const std::exception& e){r.error=e.what();}
                r.ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return r;
            });
        }catch(const std::exception& e){bridge.error=e.what();lua_pushboolean(L,false);return 1;}
        ++terrainTicket;terrainGeneration=current.generation;terrainPid=current.mcPid;terrainEpoch=epoch;
        terrainBaseSeq=current.publishSeq;terrainPublishedSeq=0;terrainState="packing";terrainError.clear();
        lua_pushinteger(L,lua_Integer(terrainTicket));return 1;
    }
    const bool ok=!tris.empty()&&bridge.publish_collision(epoch,region,tris);
    sync_collision_generation(bridge.collision_status());
    if(ok)cache_collision(region,std::move(tris));
    lua_pushboolean(L,ok);return 1;
}
void cache_collision(const proto::ColRegion& region,std::vector<proto::ColTri> tris){
        const RegionKey key{region.minX,region.minY,region.minZ,region.maxX,region.maxY,region.maxZ};collisionRegions[key]=std::move(tris);
        auto distance=[](const RegionKey& k){const double x=(double(k[0])+k[3])*0.5-host.posX,y=(double(k[1])+k[4])*0.5-host.posY,z=(double(k[2])+k[5])*0.5-host.posZ;return x*x+y*y+z*z;};
        for(auto it=collisionRegions.begin();it!=collisionRegions.end();){if(it->first!=key&&distance(it->first)>96*96)it=collisionRegions.erase(it);else ++it;}
        auto total=[](){std::size_t n=0;for(const auto& [k,v]:collisionRegions)n+=v.size();return n;};
        while(collisionRegions.size()>32||total()>250000){auto farRegion=collisionRegions.end();double maxDistance=-1;for(auto it=collisionRegions.begin();it!=collisionRegions.end();++it)if(it->first!=key&&distance(it->first)>maxDistance){maxDistance=distance(it->first);farRegion=it;}if(farRegion==collisionRegions.end())break;collisionRegions.erase(farRegion);}
        store.collisionTriangles.clear();store.collisionTriangles.reserve(total());for(const auto& [k,v]:collisionRegions)store.collisionTriangles.insert(store.collisionTriangles.end(),v.begin(),v.end());++store.collisionRevision;collisionReady=true;
}
int drain_solids(lua_State* L){std::scoped_lock lock(mutex);const auto count=std::min(store.solidChanges.size(),std::size_t(8192));lua_createtable(L,int(count),0);for(std::size_t i=0;i<count;i++){const auto& s=store.solidChanges[i];lua_createtable(L,0,4);nfield(L,"x",s.x);nfield(L,"y",s.y);nfield(L,"z",s.z);bfield(L,"solid",s.solid);lua_rawseti(L,-2,lua_Integer(i+1));}store.solidChanges.erase(store.solidChanges.begin(),store.solidChanges.begin()+count);return 1;}
int snapshot_cubes(lua_State* L){
    std::scoped_lock lock(mutex);double x{},y{},z{},radius{},limit{},epoch{};
    if(!lua_istable(L,1)||!valid_number(L,1,"x",x)||!valid_number(L,1,"y",y)||!valid_number(L,1,"z",z)
        ||!valid_number(L,1,"radius",radius)||!valid_number(L,1,"limit",limit)||!valid_number(L,1,"epoch",epoch)
        ||radius<=0||radius>16||limit<1||limit>1280||limit!=std::floor(limit)
        ||std::abs(x)>30'000'000||std::abs(y)>30'000'000||std::abs(z)>30'000'000||epoch!=host.collisionEpoch){lua_pushnil(L);return 1;}
    const auto context=bridge.collision_status();
    store.set_cube_context(host.worldId,host.collisionEpoch,context.mcPid,context.generation,context.connected);
    const auto snapshot=store.nearby_cubes(x,y,z,radius,std::size_t(limit));
    lua_createtable(L,0,9);bfield(L,"ready",store.cubeConnected&&store.cubeCleared);nfield(L,"epoch",store.cubeEpoch);
    nfield(L,"world_id",store.cubeWorld);nfield(L,"mc_pid",store.cubePid);ifield(L,"generation",store.cubeGeneration);
    ifield(L,"revision",store.cubeRevision);ifield(L,"total",snapshot.total);bfield(L,"truncated",snapshot.total>snapshot.rows.size());
    lua_createtable(L,int(snapshot.rows.size()),0);int i=1;
    for(const auto&p:snapshot.rows){lua_createtable(L,0,3);nfield(L,"x",p.x);nfield(L,"y",p.y);nfield(L,"z",p.z);lua_rawseti(L,-2,i++);}
    lua_setfield(L,-2,"cubes");return 1;
}
bool section_key(lua_State*L,SectionKey&k,std::uint64_t&rev){
    double x{},y{},z{},r{},epoch{};
    if(!lua_istable(L,1)||!valid_number(L,1,"sx",x)||!valid_number(L,1,"sy",y)||!valid_number(L,1,"sz",z)
        ||!valid_number(L,1,"revision",r)||!valid_number(L,1,"epoch",epoch)||epoch!=host.collisionEpoch
        ||std::abs(x)>1000000||std::abs(y)>1000000||std::abs(z)>1000000||x!=std::floor(x)||y!=std::floor(y)||z!=std::floor(z)||r<1||r>9007199254740991.||r!=std::floor(r))return false;
    k={int(x),int(y),int(z)};rev=std::uint64_t(r);return true;
}
int snapshot_sections(lua_State*L){
    std::scoped_lock lock(mutex);sectionMailbox.busy();
    lua_createtable(L,0,8);ifield(L,"host_pid",GetCurrentProcessId());bfield(L,"ready",active()&&store.cubeCleared);ifield(L,"world_id",store.cubeWorld);ifield(L,"epoch",store.cubeEpoch);
    ifield(L,"mc_pid",store.cubePid);ifield(L,"generation",store.cubeGeneration);ifield(L,"jobs",sectionMailbox.count());sfield(L,"error",sectionMailbox.error.c_str());
    std::vector<std::pair<double,SectionKey>> rows;
    if(active()&&store.cubeCleared)for(const auto&[k,m]:store.sections){
        double dx=std::max(0.,std::abs(double(k.x)*16+8-mc.x)-8),dy=std::max(0.,std::abs(double(k.y)*16+8-mc.y)-8),dz=std::max(0.,std::abs(double(k.z)*16+8-mc.z)-8);
        const double d=dx*dx+dy*dy+dz*dz;if(d<48*48&&m.vertices.size()<=196608)rows.push_back({d,k});
    }
    std::sort(rows.begin(),rows.end());if(rows.size()>16)rows.resize(16);
    lua_createtable(L,int(rows.size()),0);int index=1;for(const auto&[d,k]:rows){const auto&m=store.sections.at(k);lua_createtable(L,0,5);
        nfield(L,"sx",k.x);nfield(L,"sy",k.y);nfield(L,"sz",k.z);ifield(L,"revision",m.nativeRevision);ifield(L,"vertices",m.vertices.size());lua_rawseti(L,-2,index++);}
    lua_setfield(L,-2,"sections");return 1;
}
int capture_section(lua_State*L){
    std::scoped_lock lock(mutex);SectionKey k;std::uint64_t rev{};
    if(!active()||!section_key(L,k,rev)){lua_pushnil(L);return 1;}
    wchar_t path[32768]{};GetModuleFileNameW(nullptr,path,32768);
    const auto root=std::filesystem::path(path).parent_path()/L"reframework/data/onimusha_mc/native_sections";
    try{const auto id=sectionMailbox.request(root,store,k,rev);if(id.empty())lua_pushnil(L);else lua_pushstring(L,id.c_str());}
    catch(const std::exception&e){sectionMailbox.error=e.what();lua_pushnil(L);}return 1;
}
int ack_section(lua_State*L){
    std::scoped_lock lock(mutex);SectionKey k;std::uint64_t rev{};bool ok=false;
    if(active()&&section_key(L,k,rev)){
        lua_getfield(L,1,"mask");std::size_t len{};const char*hex=lua_tolstring(L,-1,&len);
        if(hex&&len>0&&len<=16384&&len%2==0){
            std::vector<std::uint8_t>mask;mask.reserve(len/2);bool valid=true;
            auto digit=[](char c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;};
            for(std::size_t i=0;i<len;i+=2){const int a=digit(hex[i]),b=digit(hex[i+1]);if(a<0||b<0){valid=false;break;}mask.push_back(std::uint8_t(a*16+b));}
            if(valid)ok=store.accept_native_section(k,rev,mask,GetTickCount64());
        }lua_pop(L,1);
    }lua_pushboolean(L,ok);return 1;
}
int release_section(lua_State*L){
    std::scoped_lock lock(mutex);SectionKey k;std::uint64_t rev{};
    if(lua_isnoneornil(L,1))store.invalidate_native_views();
    else if(section_key(L,k,rev)){auto it=store.nativeViews.find(k);if(it!=store.nativeViews.end()&&it->second.sourceRevision==rev)store.nativeViews.erase(it);}
    return 0;
}
int capture_model(lua_State*L){
    std::scoped_lock lock(mutex);double model{},epoch{};
    if(!active()||!lua_istable(L,1)||!valid_number(L,1,"model",model)||!valid_number(L,1,"epoch",epoch)||epoch!=host.collisionEpoch||model<1||model>UINT32_MAX||model!=std::floor(model)){lua_pushnil(L);return 1;}
    wchar_t path[32768]{};GetModuleFileNameW(nullptr,path,32768);
    const auto root=std::filesystem::path(path).parent_path()/L"reframework/data/onimusha_mc/native_models";
    const auto priority=number(L,1,"priority",1)==0?0u:1u;
    try{const auto id=sectionMailbox.request_model(root,store,std::uint32_t(model),priority,boolean(L,1,"white_flash"));if(id.empty())lua_pushnil(L);else lua_pushstring(L,id.c_str());}
    catch(const std::exception&e){sectionMailbox.error=e.what();lua_pushnil(L);}return 1;
}
int snapshot_instances(lua_State*L){
    std::scoped_lock lock(mutex);const bool valid=active()&&store.cubeCleared;const auto rows=valid?store.nearby_instances(mc.x,mc.y,mc.z):std::vector<NativeCube>{};
    lua_createtable(L,0,8);ifield(L,"host_pid",GetCurrentProcessId());bfield(L,"ready",valid);ifield(L,"world_id",store.cubeWorld);ifield(L,"epoch",store.cubeEpoch);ifield(L,"mc_pid",store.cubePid);ifield(L,"generation",store.cubeGeneration);
    bfield(L,"foreground",window&&GetForegroundWindow()==window);nfield(L,"radius",128);
    lua_createtable(L,int(rows.size()),0);int i=1;for(auto p:rows){lua_createtable(L,0,4);nfield(L,"x",p.x);nfield(L,"y",p.y);nfield(L,"z",p.z);nfield(L,"kind",p.kind);lua_rawseti(L,-2,i++);}lua_setfield(L,-2,"cubes");
    const auto lights=valid?store.nearby_lights(mc.x,mc.y,mc.z):std::vector<NativeLight>{};
    lua_createtable(L,int(lights.size()),0);i=1;for(auto p:lights){lua_createtable(L,0,5);nfield(L,"x",p.x);nfield(L,"y",p.y);nfield(L,"z",p.z);nfield(L,"color",p.color);nfield(L,"level",p.level);lua_rawseti(L,-2,i++);}lua_setfield(L,-2,"lights");return 1;
}
int ack_instances(lua_State*L){
    std::scoped_lock lock(mutex);bool ok=false;
    if(active()&&lua_istable(L,1)&&number(L,1,"epoch",-1)==host.collisionEpoch){
        lua_getfield(L,1,"cubes");const int table=lua_gettop(L);const auto count=lua_rawlen(L,table);
        if(lua_istable(L,table)&&count<=1280){std::vector<NativeCube>rows;bool valid=true;
            for(std::size_t i=1;i<=count;i++){
                lua_rawgeti(L,table,i);double x{},y{},z{},kind{};const int t=lua_gettop(L);
                if(!lua_istable(L,t)||!valid_number(L,t,"x",x)||!valid_number(L,t,"y",y)||!valid_number(L,t,"z",z)||!valid_number(L,t,"kind",kind)
                    ||std::abs(x)>16000000||std::abs(y)>16000000||std::abs(z)>16000000||kind<1||kind>UINT32_MAX||x!=std::floor(x)||y!=std::floor(y)||z!=std::floor(z)||kind!=std::floor(kind))valid=false;
                if(valid)rows.push_back({int(x),int(y),int(z),std::uint32_t(kind)});lua_pop(L,1);
            }if(valid)ok=store.accept_instances(rows,GetTickCount64());
        }lua_pop(L,1);
    }lua_pushboolean(L,ok);return 1;
}
int snapshot_dynamic(lua_State*L){
    std::scoped_lock lock(mutex);store.prepare_dynamic();lua_createtable(L,0,3);
    ifield(L,"epoch",store.cubeEpoch);bfield(L,"ready",active()&&store.cubeCleared);bfield(L,"stable_faces",true);
    auto push=[&](const char*name,const Mesh&m,const DynamicNativeView&v,bool visible){
        lua_createtable(L,visible?int(v.faces.size()):0,0);int i=1;
        if(visible)for(const auto&f:v.faces){lua_createtable(L,0,17);ifield(L,"first",f.first);ifield(L,"kind",f.model);ifield(L,"id",f.id);ifield(L,"tint",f.tint);bfield(L,"white_flash",f.whiteFlash);
            nfield(L,"x",f.position[0]+(name[0]=='a'?mc.x:m.origin[0]));nfield(L,"y",f.position[1]+(name[0]=='a'?mc.y:m.origin[1]));nfield(L,"z",f.position[2]+(name[0]=='a'?mc.z:m.origin[2]));
            nfield(L,"qw",f.rotation[0]);nfield(L,"qx",f.rotation[1]);nfield(L,"qy",f.rotation[2]);nfield(L,"qz",f.rotation[3]);nfield(L,"sx",f.scale[0]);nfield(L,"sy",f.scale[1]);lua_rawseti(L,-2,i++);}
        lua_setfield(L,-2,name);
    };
    push("avatar",store.avatar,store.nativeAvatar,mc.cameraMode!=0);push("scene",store.scene,store.nativeScene,true);
    push("hands",store.hands,store.nativeHands,mc.cameraMode==0);bfield(L,"hands_complete",store.nativeHands.faces.size()*6==store.hands.vertices.size());return 1;
}
int ack_dynamic(lua_State*L){
    std::scoped_lock lock(mutex);bool ok=active()&&lua_istable(L,1)&&number(L,1,"epoch",-1)==host.collisionEpoch;
    const bool stable=ok&&boolean(L,1,"stable_faces");
    std::map<std::uint32_t,std::uint32_t> rows;
    if(ok){lua_getfield(L,1,"faces");const auto count=lua_rawlen(L,-1);ok=lua_istable(L,-1)&&count<=512;
        for(std::size_t i=1;ok&&i<=count;i++){lua_rawgeti(L,-1,i);double first{},model{};const auto t=lua_gettop(L);
            ok=lua_istable(L,t)&&valid_number(L,t,stable?"id":"first",first)&&valid_number(L,t,"kind",model)&&first>=(stable?1:0)&&first<=(stable?double(UINT32_MAX):1'999'999.)&&model>=1&&model<=UINT32_MAX&&first==std::floor(first)&&model==std::floor(model);
            if(ok)ok=rows.emplace(std::uint32_t(first),std::uint32_t(model)).second;lua_pop(L,1);
        }lua_pop(L,1);
        if(ok)ok=store.accept_dynamic(boolean(L,1,"hands")?2:boolean(L,1,"avatar")?1:0,rows,GetTickCount64(),stable);
    }lua_pushboolean(L,ok);return 1;
}
int set_camera(lua_State* L){
    if(!lua_istable(L,1)){lua_pushboolean(L,false);return 1;}std::scoped_lock lock(mutex);CameraState c{};c.origin[0]=number(L,1,"origin_x");c.origin[1]=number(L,1,"origin_y");c.origin[2]=number(L,1,"origin_z");c.valid=boolean(L,1,"valid");lua_getfield(L,1,"view_proj");bool matrix=lua_istable(L,-1)&&lua_rawlen(L,-1)==16;if(matrix){for(int i=0;i<16;i++){lua_rawgeti(L,-1,i+1);int ok{};const double v=lua_tonumberx(L,-1,&ok);if(!ok||!std::isfinite(v))matrix=false;c.viewProj[i]=float(v);lua_pop(L,1);}}lua_pop(L,1);c.valid=c.valid&&matrix;camera=c;cameraReady=boolean(L,1,"binding_ready",c.valid);lua_pushboolean(L,cameraReady);return 1;
}
void on_lua(lua_State* L){
    const auto v=lua_version(L);if(v!=504){api->functions->log_error("OnimushaMC: incompatible Lua ABI %f",v);return;}
    static const luaL_Reg functions[]={{"submit_host",submit},{"tick_host",submit},{"read_mc",read_mc},{"get_mc_state",read_mc},{"drain_events",drain_events},{"poll_events",drain_events},{"set_enabled",set_enabled},{"send_hurt",send_hurt},{"status",status},{"publish_actors",publish_actors},{"publish_collision_tris",publish_tris},{"drain_solids",drain_solids},{"set_camera",set_camera},{nullptr,nullptr}};
    luaL_newlib(L,functions);lua_pushcfunction(L,snapshot_cubes);lua_setfield(L,-2,"snapshot_full_cubes");
    lua_pushcfunction(L,snapshot_sections);lua_setfield(L,-2,"snapshot_sections");lua_pushcfunction(L,capture_section);lua_setfield(L,-2,"capture_section");
    lua_pushcfunction(L,ack_section);lua_setfield(L,-2,"ack_section");lua_pushcfunction(L,release_section);lua_setfield(L,-2,"release_section");
    lua_pushcfunction(L,snapshot_instances);lua_setfield(L,-2,"snapshot_native_instances");lua_pushcfunction(L,ack_instances);lua_setfield(L,-2,"ack_native_instances");
    lua_pushcfunction(L,capture_model);lua_setfield(L,-2,"capture_native_model");
    lua_pushcfunction(L,snapshot_dynamic);lua_setfield(L,-2,"snapshot_native_dynamic");lua_pushcfunction(L,ack_dynamic);lua_setfield(L,-2,"ack_native_dynamic");
    lua_setglobal(L,"onimusha_mc");api->functions->log_info("OnimushaMC: Lua bridge registered; takeover disabled until adapter passes bindings");
}
void on_lua_destroyed(lua_State*){std::scoped_lock lock(mutex);enabled=ready=collisionReady=cameraReady=false;store.invalidate_native_views();bridge.invalidate_collision();release();host.flags=0;bridge.publish_host(host);}
void on_present(){
    std::scoped_lock lock(mutex);bridge.heartbeat();
    const auto context=bridge.collision_status();store.set_cube_context(host.worldId,host.collisionEpoch,context.mcPid,context.generation,context.connected);
    bridge.drain_render(store);bridge.overlay(overlay);bridge.world_entities(store.worldEntities);const bool have=bridge.read_mc(mc);
    const bool inputReady=retry_pending_release();
    if(enabled&&bridge.alive())renderer::prepare();
    const bool takeover=have&&active();
    if(takeover&&window&&GetForegroundWindow()==window){if(inputReady){sync_input_mode((mc.flags&proto::kMcScreenOpen)!=0);if(pendingGuiCursor)publish_gui_cursor();}}
    else if(routed||mouseRouter.known_mode())release();
    if(takeover){
        // Pose packets can advance between Lua's game-thread transform update and
        // Present. Reuse only same slot+appearance receipts, for at most 150ms.
        if(store.nativeAvatar.expires||store.nativeScene.expires||store.nativeHands.expires){store.prepare_dynamic();const auto now=GetTickCount64();store.partition_dynamic(store.avatar,store.nativeAvatar,now);store.partition_dynamic(store.scene,store.nativeScene,now);store.partition_dynamic(store.hands,store.nativeHands,now);}
        renderer::render(store,overlay,mc,camera);
    }
}
void on_reset(){std::scoped_lock lock(mutex);renderer::reset();}
std::uint16_t scan_sdl(WPARAM key,LPARAM lparam){
    if(key>='A'&&key<='Z')return std::uint16_t(key-'A'+4);if(key>='1'&&key<='9')return std::uint16_t(key-'1'+30);if(key=='0')return 39;
    if(key>=VK_F1&&key<=VK_F12)return std::uint16_t(key-VK_F1+58);
    const bool ext=(lparam&(1ll<<24))!=0;
    switch(key){case VK_RETURN:return ext?88:40;case VK_ESCAPE:return 41;case VK_BACK:return 42;case VK_TAB:return 43;case VK_SPACE:return 44;case VK_OEM_MINUS:return 45;case VK_OEM_PLUS:return 46;case VK_OEM_4:return 47;case VK_OEM_6:return 48;case VK_OEM_5:return 49;case VK_OEM_1:return 51;case VK_OEM_7:return 52;case VK_OEM_3:return 53;case VK_OEM_COMMA:return 54;case VK_OEM_PERIOD:return 55;case VK_OEM_2:return 56;case VK_CAPITAL:return 57;case VK_INSERT:return 73;case VK_HOME:return 74;case VK_PRIOR:return 75;case VK_DELETE:return 76;case VK_END:return 77;case VK_NEXT:return 78;case VK_RIGHT:return 79;case VK_LEFT:return 80;case VK_DOWN:return 81;case VK_UP:return 82;case VK_CONTROL:return ext?228:224;case VK_MENU:return ext?230:226;case VK_SHIFT:return ((lparam>>16)&255)==0x36?229:225;case VK_LWIN:return 227;case VK_RWIN:return 231;default:return 0;}
}
bool on_message(void* hwnd,unsigned int message,unsigned long long wparam,long long lparam){
    std::scoped_lock lock(mutex);window=static_cast<HWND>(hwnd);
    if(message==WM_KILLFOCUS||message==WM_ACTIVATEAPP&&!wparam){release();return true;}
    const auto toggle=f10_key_action(message,wparam,lparam);
    if(toggle!=ToggleKeyAction::pass){if(toggle==ToggleKeyAction::toggle){enabled=!enabled;release();if(!enabled)store.invalidate_native_views();}return false;}
    const bool route=active()&&GetForegroundWindow()==window;
    if(!route){if(routed||mouseRouter.known_mode())release();return true;}
    const bool screenOpen=(mc.flags&proto::kMcScreenOpen)!=0;
    // A failed release must precede new GUI baselines and routed input, even
    // when the next window message arrives before Present. Keep system messages
    // and the existing original-game/REFramework shortcut exceptions passing.
    if(!retry_pending_release())return !captured_input_message(message,wparam,screenOpen);
    sync_input_mode(screenOpen);routed=true;
    switch(message){
    case WM_KEYDOWN:case WM_KEYUP:case WM_SYSKEYDOWN:case WM_SYSKEYUP:{
        const bool down=message==WM_KEYDOWN||message==WM_SYSKEYDOWN;
        // Preserve REFramework Insert and original game Escape/interact keys while no MC menu.
        if(wparam==VK_INSERT||(!(mc.flags&proto::kMcScreenOpen)&&(wparam==VK_ESCAPE||wparam=='G')))return true;
        if(wparam=='O'&&!(mc.flags&proto::kMcScreenOpen)){if(down&&!(lparam&(1ll<<30)))bridge.input(proto::kInOpenMenu);return false;}
        const auto sc=scan_sdl(WPARAM(wparam),LPARAM(lparam));if(sc)bridge.input(proto::kInKey,sc,down?1:0);return false;
    }
    case WM_CHAR: {
        const auto ch=std::uint32_t(wparam);if(ch<32||ch==127)return false;if(ch>=0xD800&&ch<=0xDBFF){surrogate=std::uint16_t(ch);return false;}
        if(ch>=0xDC00&&ch<=0xDFFF&&surrogate){bridge.input(proto::kInText,0,0x10000+((surrogate-0xD800)<<10)+(ch-0xDC00));surrogate=0;}else if(ch<0xD800||ch>0xDFFF){bridge.input(proto::kInText,0,int(ch));surrogate=0;}return false;
    }
    case WM_LBUTTONDOWN:case WM_LBUTTONUP:case WM_RBUTTONDOWN:case WM_RBUTTONUP:case WM_MBUTTONDOWN:case WM_MBUTTONUP:case WM_XBUTTONDOWN:case WM_XBUTTONUP:{
        const bool down=message==WM_LBUTTONDOWN||message==WM_RBUTTONDOWN||message==WM_MBUTTONDOWN||message==WM_XBUTTONDOWN;
        if(mc.flags&proto::kMcScreenOpen){
            // Captured button LPARAM may already be the host's center. The
            // virtual cursor is authoritative, including an intentional center click.
            if(!publish_gui_cursor()){release();return false;}
        }
        const auto button=message==WM_LBUTTONDOWN||message==WM_LBUTTONUP?1:message==WM_MBUTTONDOWN||message==WM_MBUTTONUP?2:message==WM_RBUTTONDOWN||message==WM_RBUTTONUP?3:GET_XBUTTON_WPARAM(wparam)==XBUTTON1?4:5;
        // Never leave a held button behind when the bounded input ring fills.
        // release() retries ReleaseAll from Present as soon as space is available.
        if(!bridge.input(proto::kInMouseButton,std::uint16_t(button),down?1:0))release();return false;
    }
    case WM_MOUSEWHEEL:bridge.input(proto::kInScroll,0,GET_WHEEL_DELTA_WPARAM(wparam));return false;
    case WM_MOUSEMOVE:{
        POINT p{GET_X_LPARAM(lparam),GET_Y_LPARAM(lparam)};RECT rect{};GetClientRect(window,&rect);
        const auto delta=mouseRouter.legacy_move(p.x,p.y,rect.right-rect.left,rect.bottom-rect.top);
        if(delta.send){if(screenOpen)publish_gui_cursor();else bridge.input(proto::kInLookDelta,0,delta.x,delta.y);}return false;
    }
    case WM_INPUT:{
        // The pinned REFramework WindowsMessageHook calls DefWindowProc when
        // this callback returns false, including RIM_INPUT system cleanup.
        RAWINPUT ri{};UINT bytes=sizeof(ri);
        if(GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam),RID_INPUT,&ri,&bytes,sizeof(RAWINPUTHEADER))!=UINT(-1)&&ri.header.dwType==RIM_TYPEMOUSE&&!(ri.data.mouse.usFlags&MOUSE_MOVE_ABSOLUTE)){
            RECT rect{};GetClientRect(window,&rect);
            const auto delta=mouseRouter.raw_delta(ri.data.mouse.lLastX,ri.data.mouse.lLastY,rect.right-rect.left,rect.bottom-rect.top);
            if(delta.send){if(screenOpen)publish_gui_cursor();else bridge.input(proto::kInLookDelta,0,delta.x,delta.y);}
        }return false;
    }
    default:return true;
    }
}
}
}
extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* v){v->major=REFRAMEWORK_PLUGIN_VERSION_MAJOR;v->minor=REFRAMEWORK_PLUGIN_VERSION_MINOR;v->patch=0;v->game_name="ONIMUSHA_WOTS";}
extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* p){
    if(!p||!p->functions||!p->renderer_data)return false;omc::api=p;
    if(!omc::bridge.open()){p->functions->log_error("OnimushaMC: %s",omc::bridge.error.c_str());return false;}
    omc::renderer::initialize(p);
    const bool ok=p->functions->on_lua_state_created(omc::on_lua)&&p->functions->on_lua_state_destroyed(omc::on_lua_destroyed)&&p->functions->on_present(omc::on_present)&&p->functions->on_device_reset(omc::on_reset)&&p->functions->on_message(omc::on_message);
    p->functions->log_info("OnimushaMC: native bridge protocol %u initialized; F10 takeover toggle",omc::proto::kVersion);return ok;
}
