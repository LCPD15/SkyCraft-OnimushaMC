// Isolated real-Minecraft test. Never opens the live game mapping or its world.
#include "Bridge.hpp"
#include <Windows.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <cstdio>
using namespace omc;
static void command(Bridge& b,const char* s){
 b.input(proto::kInKey,56,1);b.input(proto::kInKey,56,0);Sleep(180);
 for(;*s;s++)b.input(proto::kInText,0,*s);
 b.input(proto::kInKey,40,1);b.input(proto::kInKey,40,0);
}
int main(){
 const std::filesystem::path out=L"G:/Onimusha_MC_mod/logs/dynamic-sync-soul-20261009/isolated";
 std::filesystem::create_directories(out);Bridge b;if(!b.open(L"Local\\OnimushaMC_PoseSoulSmoke"))return 2;
 proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
 h.worldId=h.collisionEpoch=h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=3;h.viewportW=854;h.viewportH=480;
 h.healthCurrent=h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
 proto::ColRegion region{-8,48,-8,31,79,31,1,0};
 proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
 RenderStore store;proto::McState mc{};auto start=GetTickCount64();ULONGLONG ready{},lastCol{},nextAction{};
 unsigned step{},healEvents{},cHeld{},rightHeld{},released{},movedFrames{},firstFrames{},thirdFrames{};
 double minX=1e6,maxX=-1e6,minZ=1e6,maxZ=-1e6;bool frameSplit=false;
 const char* setup[]={"gamemode creative","clear @s",
 "item replace entity @s weapon.mainhand with minecraft:diamond_axe[minecraft:damage=5]",
 "item replace entity @s inventory.0 with minecraft:cobblestone 60",
 "experience set @s 0 levels","experience set @s 0 points",
 "gamerule minecraft:natural_health_regeneration false","gamemode survival"};
 while(GetTickCount64()-start<120000){
  auto now=GetTickCount64();b.heartbeat();b.publish_host(h);auto c=b.collision_status();store.set_cube_context(1,1,c.mcPid,c.generation,c.connected);
  if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
  const auto before=store.renderPose.frameCounter;b.drain_render(store,32ull<<20);
  frameSplit|=store.renderPose.frameCounter!=before; // Only the game-thread latch may advance it.
  store.latch_pose();store.prepare_dynamic();
  for(const auto&e:b.events())if(e.type==proto::kEvHealthChange&&e.weapon==1){
   if(e.a>0)++healEvents;h.healthCurrent=std::clamp(h.healthCurrent+e.a*100,0.f,100.f);++h.healthRevision;
  }
  if(b.read_mc(mc)){
   if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1){ready=now;nextAction=now+2000;}
   if(ready){
    if(step==10&&(mc.flags&proto::kMcAbsorbSouls))++cHeld;
    if(step==12&&(mc.flags&proto::kMcAbsorbSouls))++rightHeld;
    if(step==11&&!(mc.flags&proto::kMcAbsorbSouls))++released;
    if(step>=13){minX=std::min(minX,mc.x);maxX=std::max(maxX,mc.x);minZ=std::min(minZ,mc.z);maxZ=std::max(maxZ,mc.z);++movedFrames;}
    if(store.renderPose.cameraMode==0&&!store.nativeHands.faces.empty())++firstFrames;
    if(store.renderPose.cameraMode!=0&&!store.nativeAvatar.faces.empty())++thirdFrames;
    if(now>=nextAction){
     if(step<8)command(b,setup[step]);
     else if(step==8){h.healthCurrent=50;++h.healthRevision;}
     else if(step==9)b.input(proto::kInKey,6,1);
     else if(step==10)b.input(proto::kInKey,6,0);
     else if(step==11)b.input(proto::kInMouseButton,3,1);
     else if(step==12){b.input(proto::kInMouseButton,3,0);b.input(proto::kInKey,26,1);}
     else if(step==13){b.input(proto::kInKey,26,0);b.input(proto::kInKey,62,1);b.input(proto::kInKey,62,0);}
     else if(step==14)b.input(proto::kInKey,7,1);
     else if(step==15)b.input(proto::kInKey,7,0);
     else if(step>=16&&step<76){unsigned id=step-15;b.input(proto::kInSoulReward,0,id,1);b.input(proto::kInSoulReward,0,id,1);}
     else if(step==76)b.input(proto::kInSoulReward,0,999,2); // Old/different world receipt.
     else if(step>=78)break;
     ++step;nextAction=now+(step>=16&&step<77?100:1200);
    }
   }
  }
  Sleep(16);
 }
 const bool pass=step>=78&&store.poseFrames&&store.poseLatched>100&&!frameSplit&&!store.invalidMessages
  &&firstFrames>10&&thirdFrames>10&&maxX-minX>1&&maxZ-minZ>1&&cHeld>10&&rightHeld>10&&released>10&&healEvents==10;
 std::ofstream f(out/"host-result.json");
 f<<"{\"passed\":"<<(pass?"true":"false")<<",\"steps\":"<<step<<",\"pose_received\":"<<store.poseReceived
  <<",\"pose_latched\":"<<store.poseLatched<<",\"invalid\":"<<store.invalidMessages<<",\"invalid_type\":"<<store.lastInvalidType<<",\"frame_split\":"<<(frameSplit?"true":"false")
  <<",\"first_frames\":"<<firstFrames<<",\"third_frames\":"<<thirdFrames<<",\"x_travel\":"<<maxX-minX<<",\"z_travel\":"<<maxZ-minZ
  <<",\"c_held\":"<<cHeld<<",\"right_held\":"<<rightHeld<<",\"released\":"<<released<<",\"heal_events\":"<<healEvents<<"}";
 f.close();printf("POSE SOUL RESULT %d steps=%u latched=%llu heal=%u\n",pass,step,store.poseLatched,healEvents);fflush(stdout);ExitProcess(pass?0:1);
}
