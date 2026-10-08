// Actual MC geometry audit in a separate mapping/world; never controls Onimusha.
#include "Bridge.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <cstdio>
#include <algorithm>
using namespace omc;
static void command(Bridge&b,const char*s){b.input(proto::kInKey,56,1);b.input(proto::kInKey,56,0);Sleep(180);for(;*s;s++)b.input(proto::kInText,0,*s);b.input(proto::kInKey,40,1);b.input(proto::kInKey,40,0);}
int main(int argc,char**argv){
 const std::filesystem::path out=argc>1?std::filesystem::path(argv[1]):std::filesystem::path(L"G:/Onimusha_MC_mod/logs/tnt-pixel-20261009/animation-smoke");std::filesystem::create_directories(out);
 Bridge b;if(!b.open(L"Local\\OnimushaMC_AnimationSmoke"))return 2;
 proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
 h.worldId=h.collisionEpoch=h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=3;h.viewportW=854;h.viewportH=480;h.healthCurrent=h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
 proto::ColRegion region{-8,48,-8,31,79,31,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
 RenderStore store;proto::McState mc{};auto start=GetTickCount64();ULONGLONG ready{},lastCol{},lastSample{};int stage=0;std::size_t hurtFrames{},tntFrames{},whiteFrames{},plainFrames{};float minimum=32,maximum=0;
 std::ofstream samples(out/"frames.jsonl");
 const char*commands[]={"gamemode creative","summon minecraft:iron_golem 8 65 7 {NoAI:1b}","damage @e[type=minecraft:iron_golem,limit=1] 1","summon minecraft:tnt 4 65 7"};
 while(GetTickCount64()-start<120000){auto now=GetTickCount64();b.heartbeat();b.publish_host(h);auto c=b.collision_status();store.set_cube_context(1,1,c.mcPid,c.generation,c.connected);
  if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
  b.drain_render(store,32ull<<20);store.prepare_dynamic();
  if(b.read_mc(mc)){if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1)ready=now;
   if(ready){auto elapsed=now-ready;if(stage<4&&elapsed>2000+stage*2000)command(b,commands[stage++]);if(stage==4&&elapsed>14500)break;}}
  if(ready&&now-lastSample>=16){lastSample=now;bool red=false,tnt=false,white=false;
   samples<<"{\"ms\":"<<(now-ready)<<",\"faces\":[";bool first=true;
   for(const auto&f:store.nativeScene.faces){if(!first)samples<<',';first=false;
    const auto x=f.position[0]+store.scene.origin[0],z=f.position[2]+store.scene.origin[2];
    samples<<"{\"id\":"<<f.id<<",\"model\":"<<f.model<<",\"tint\":"<<f.tint<<",\"white_flash\":"<<(f.whiteFlash?"true":"false")<<",\"sx\":"<<f.scale[0]<<",\"sy\":"<<f.scale[1]<<",\"x\":"<<x<<",\"z\":"<<z<<"}";
    if(f.tint!=0xffffffff)red=true;
    if(stage==4&&x>2&&x<6&&z>5&&z<9){minimum=std::min({minimum,f.scale[0],f.scale[1]});maximum=std::max({maximum,f.scale[0],f.scale[1]});tnt=true;white|=f.whiteFlash;}}
   samples<<"]}\n";if(red)hurtFrames++;if(tnt){tntFrames++;if(white)whiteFrames++;else plainFrames++;}}
  Sleep(8);
 }
 const bool passed=stage==4&&hurtFrames>0&&tntFrames>5&&whiteFrames>5&&plainFrames>5&&minimum<1.05&&maximum>1.15&&store.invalidMessages==0;
 std::ofstream(out/"result.json")<<"{\"passed\":"<<(passed?"true":"false")<<",\"hurt_frames\":"<<hurtFrames<<",\"tnt_frames\":"<<tntFrames<<",\"white_frames\":"<<whiteFrames<<",\"plain_frames\":"<<plainFrames<<",\"min_scale\":"<<minimum<<",\"max_scale\":"<<maximum<<",\"invalid_messages\":"<<store.invalidMessages<<"}";
 samples.close();printf("ANIMATION RESULT %d hurt %zu TNT %zu scale %.6f .. %.6f\n",passed,hurtFrames,tntFrames,minimum,maximum);fflush(stdout);ExitProcess(passed?0:1);
}
