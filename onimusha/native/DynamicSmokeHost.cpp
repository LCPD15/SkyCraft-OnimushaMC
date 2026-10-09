// Actual player, held-item and iron-golem render capture in an isolated MC world.
#include "Bridge.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <set>
#include <cstdio>
using namespace omc;
static void command(Bridge&b,const char*s){b.input(proto::kInKey,56,1);b.input(proto::kInKey,56,0);Sleep(180);for(;*s;s++)b.input(proto::kInText,0,*s);b.input(proto::kInKey,40,1);b.input(proto::kInKey,40,0);}
static void write(const std::filesystem::path&p,const void*h,size_t hs,const void*d,size_t n){std::ofstream f(p,std::ios::binary);f.write(static_cast<const char*>(h),hs);f.write(static_cast<const char*>(d),n);}
int main(int argc,char**argv){
 const bool hands=argc>1&&std::string(argv[1])=="--hands";
 const std::filesystem::path out=hands?L"G:/Onimusha_MC_mod/logs/automatic-models-20261008/real-hands":L"G:/Onimusha_MC_mod/logs/automatic-models-20261008/real-dynamic";std::filesystem::create_directories(out);
 Bridge b;if(!b.open(L"Local\\OnimushaMC_DynamicSmoke"))return 2;
 proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
 h.worldId=h.collisionEpoch=h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=3;h.viewportW=854;h.viewportH=480;h.healthCurrent=h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
 proto::ColRegion region{-8,48,-8,31,79,31,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
 RenderStore store;proto::McState mc{};auto start=GetTickCount64();ULONGLONG ready{},lastCol{},lastReport{},lastView{};int stage=0;std::size_t peakModels{};
 proto::ActorRecord actor{};actor.formId=1001;actor.flags=proto::kActorHostile;actor.x=4;actor.y=65;actor.z=6;actor.width=.8f;actor.height=1.8f;actor.healthFrac=1;actor.level=1;
 double beforePush{},afterPush{},maxZ{};
 std::uint64_t hudBefore{},hudAfter{};OverlayFrame hud;
 const char* commands[]={"gamemode creative","item replace entity @s weapon.mainhand with minecraft:diamond_sword","item replace entity @s weapon.offhand with minecraft:shield","summon minecraft:iron_golem 6 65 6 {NoAI:0b}","setblock 4 65 9 minecraft:torch"};
 while(GetTickCount64()-start<120000){
  auto now=GetTickCount64();b.heartbeat();b.publish_host(h);if(hands)b.publish_actors(std::span(&actor,1));auto c=b.collision_status();store.set_cube_context(1,1,c.mcPid,c.generation,c.connected);
  if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
  b.drain_render(store,32ull<<20);store.latch_pose();store.prepare_dynamic();peakModels=std::max(peakModels,store.blockModels.size());
  if(hands&&ready&&b.overlay(hud)){
   std::uint64_t opaque=0;for(std::size_t i=3;i<hud.rgba.size();i+=4)if(hud.rgba[i]>127)opaque++;
   auto e=now-ready;if(e>19500&&e<20000)hudBefore=opaque;if(e>21500)hudAfter=opaque;
  }
  if(b.read_mc(mc)){
   if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1)ready=now;
   if(ready){auto e=now-ready;
    if(e>10000&&now-lastView>500&&(hands?mc.cameraMode!=0:mc.cameraMode==0)){b.input(proto::kInKey,62,1);b.input(proto::kInKey,62,0);lastView=now;}
    if(hands&&e>=12000&&e<14000)maxZ=std::max(maxZ,mc.z);
    if(hands&&e>15000&&e<17000)actor.z=6-float(e-15000)*.001f;
    if(hands&&e>14000&&e<14500)beforePush=mc.z;
    if(hands&&e>17500)afterPush=mc.z;
    // Only this isolated test host asserts a synthetic native-ready fence, to
    // exercise MC's HUD/hand handoff without touching the installed real game.
    if(hands&&e>20000)h.flags|=proto::kSkyNativeHandsReady;
    if(stage<5&&e>2000+stage*1300)command(b,commands[stage++]);
    else if(stage==5&&e>12000){b.input(proto::kInKey,26,1);stage++;}
    else if(stage==6&&e>14000){b.input(proto::kInKey,26,0);stage++;}
    else if(stage==7&&e>18000){b.input(proto::kInMouseButton,1,1);b.input(proto::kInMouseButton,1,0);stage++;}
    else if(stage==8&&e>22000)break;
   }
  }
  if(now-lastReport>2000){printf("avatar %zu/%zu scene %zu/%zu hands %zu/%zu models %zu playerz %.3f\n",store.nativeAvatar.faces.size(),store.avatar.vertices.size()/6,store.nativeScene.faces.size(),store.scene.vertices.size()/6,store.nativeHands.faces.size(),store.hands.vertices.size()/6,store.blockModels.size(),mc.z);fflush(stdout);lastReport=now;}
  Sleep(16);
 }
 std::set<unsigned>ids;for(auto&f:store.nativeAvatar.faces)ids.insert(f.model);for(auto&f:store.nativeScene.faces)ids.insert(f.model);for(auto&f:store.nativeHands.faces)ids.insert(f.model);
 std::ofstream poses(out/"poses.json");poses<<"[";bool first=true;
 for(int stream=0;stream<2;stream++){const auto&v=stream?store.nativeScene:store.nativeAvatar;for(auto f:v.faces){if(!first)poses<<',';first=false;poses<<"{\"stream\":"<<stream<<",\"model\":"<<f.model<<",\"first\":"<<f.first<<",\"xyz\":["<<f.position[0]<<','<<f.position[1]<<','<<f.position[2]<<"],\"quat_wxyz\":["<<f.rotation[0]<<','<<f.rotation[1]<<','<<f.rotation[2]<<','<<f.rotation[3]<<"],\"scale\":["<<f.scale[0]<<','<<f.scale[1]<<"]}";}}poses<<']';poses.close();
 for(auto id:ids){const auto&m=store.blockModels.at(id);proto::RenSection header{0,0,0,std::uint32_t(m.vertices.size())};write(out/("model_"+std::to_string(id)+".bin"),&header,sizeof(header),m.vertices.data(),m.vertices.size()*sizeof(proto::RenVertex));const auto&t=*store.model_texture(id);proto::RenAtlas a{t.width,t.height};write(out/("texture_"+std::to_string(id)+".bin"),&a,sizeof(a),t.rgba.data(),t.rgba.size());}
 std::ofstream(out/"animated.json")<<"[]";
 const bool pass=stage==8&&(hands?store.nativeHands.faces.size()>=6:store.nativeAvatar.faces.size()>=36)&&store.nativeScene.faces.size()>=36&&peakModels<1024&&store.invalidMessages==0&&(!hands||(maxZ<5.31&&maxZ>4&&beforePush-afterPush>.5&&hudBefore>hudAfter+1000&&hudAfter>100));
 std::ofstream report(out/"result.json");report<<"{\"passed\":"<<(pass?"true":"false")<<",\"avatar_faces\":"<<store.nativeAvatar.faces.size()<<",\"scene_faces\":"<<store.nativeScene.faces.size()<<",\"hands_faces\":"<<store.nativeHands.faces.size()<<",\"hands_total\":"<<store.hands.vertices.size()/6<<",\"peak_models\":"<<peakModels<<",\"unique_appearances\":"<<ids.size()<<",\"max_forward_z\":"<<maxZ<<",\"before_push_z\":"<<beforePush<<",\"after_push_z\":"<<afterPush<<",\"hud_opaque_before\":"<<hudBefore<<",\"hud_opaque_after\":"<<hudAfter<<"}";report.close();printf("DYNAMIC RESULT %d\n",pass);fflush(stdout);ExitProcess(pass?0:1);
}
