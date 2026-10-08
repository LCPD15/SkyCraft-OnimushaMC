// Actual Minecraft equipment/damage path with an isolated native IPC host.
#include "Bridge.hpp"
#include <Windows.h>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <cstdio>
using namespace omc;
static void command(Bridge&b,const std::string&s){b.input(proto::kInKey,56,1);b.input(proto::kInKey,56,0);Sleep(180);for(char c:s)b.input(proto::kInText,0,c);b.input(proto::kInKey,40,1);b.input(proto::kInKey,40,0);}
int main(){
 Bridge b;if(!b.open(L"Local\\OnimushaMC_ArmorSmoke"))return 2;
 proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
 h.worldId=h.collisionEpoch=h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=3;h.viewportW=854;h.viewportH=480;h.healthCurrent=h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
 proto::ColRegion region{-8,48,-8,31,79,31,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
 proto::ActorRecord enemy{};enemy.formId=1001;enemy.flags=proto::kActorHostile;enemy.x=4;enemy.y=65;enemy.z=8;enemy.width=.8f;enemy.height=1.8f;enemy.healthFrac=1;enemy.level=1;
 RenderStore store;proto::McState mc{};auto start=GetTickCount64();ULONGLONG ready{},lastCol{},nextAction{};unsigned step=0;float deltas[3]{};int counts[3]{};bool chat=false;
 const char* slots[]={"head","chest","legs","feet"};const char* pieces[]={"helmet","chestplate","leggings","boots"};
 while(GetTickCount64()-start<120000){
  auto now=GetTickCount64();b.heartbeat();b.publish_host(h);b.publish_actors(std::span(&enemy,1));auto c=b.collision_status();store.set_cube_context(1,1,c.mcPid,c.generation,c.connected);b.drain_render(store,32ull<<20);
  if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
  for(auto&e:b.events())if(e.type==proto::kEvHealthChange&&e.weapon==1){
   if(e.a<0&&step>=8&&step<=24){int group=std::min(2,int(step-8)/8);deltas[group]+=e.a;counts[group]++;}
   h.healthCurrent=std::clamp(h.healthCurrent+e.a*100,0.f,100.f);++h.healthRevision;
   printf("HEALTH step=%u delta=%f hp=%f\n",step,e.a,h.healthCurrent);fflush(stdout);
  }
  if(b.read_mc(mc)){
   chat|=bool(mc.flags&proto::kMcScreenOpen);if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1){ready=now;nextAction=now+2000;}
   if(ready&&now>=nextAction){
    if(step==0)command(b,"gamemode survival");
    else if(step==1)command(b,"gamerule minecraft:natural_health_regeneration false");
    else if(step<=24){
     const unsigned part=(step-2)%8,group=(step-2)/8;
     if(group>=3)break;
     if(part<4){std::string item=group==0?"air":std::string(group==1?"iron_":"diamond_")+pieces[part];command(b,std::string("item replace entity @s armor.")+slots[part]+" with minecraft:"+item);}
     else if(part==4){h.healthCurrent=100;++h.healthRevision;}
     else if(part==5)b.input(proto::kInHurt,proto::kHurtMelee,1000,1001,proto::kHurtHostUnapplied);
     else if(part==7)printf("GROUP %u result=%.6f events=%d\n",group,deltas[group],counts[group]);
    }else break;
    ++step;nextAction=GetTickCount64()+800;
   }
  }
  Sleep(16);
 }
 const float expected[]={-.5f,-.3f,-.15f};bool pass=step>=25&&chat;
 for(int i=0;i<3;i++)pass=pass&&counts[i]==1&&std::abs(deltas[i]-expected[i])<.001f;
 std::ofstream out("G:/Onimusha_MC_mod/logs/automatic-models-20261008/armor-smoke.json");out<<"{\"passed\":"<<(pass?"true":"false")<<",\"step\":"<<step<<",\"fraction\":["<<deltas[0]<<','<<deltas[1]<<','<<deltas[2]<<"],\"events\":["<<counts[0]<<','<<counts[1]<<','<<counts[2]<<"]}";out.close();
 printf("ARMOR RESULT %d\n",pass);fflush(stdout);ExitProcess(pass?0:1);
}
