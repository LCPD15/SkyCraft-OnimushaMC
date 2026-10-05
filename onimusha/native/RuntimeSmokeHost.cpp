#include "Bridge.hpp"
#include <Windows.h>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <io.h>
#include <share.h>

namespace {
using namespace omc;
void text(Bridge& link,const char* command){link.input(proto::kInKey,56,1);link.input(proto::kInKey,56,0);Sleep(200);for(const auto* c=command;*c;c++)link.input(proto::kInText,0,*c);link.input(proto::kInKey,40,1);link.input(proto::kInKey,40,0);}
void key(Bridge& link,std::uint16_t code){link.input(proto::kInKey,code,1);link.input(proto::kInKey,code,0);}
void tga(const std::filesystem::path& path,const OverlayFrame& f){
    if(f.rgba.empty()||f.width>65535||f.height>65535)return;std::ofstream out(path,std::ios::binary);std::uint8_t header[18]{};header[2]=2;header[12]=std::uint8_t(f.width);header[13]=std::uint8_t(f.width>>8);header[14]=std::uint8_t(f.height);header[15]=std::uint8_t(f.height>>8);header[16]=32;header[17]=8|((f.flags&1)?0:32);out.write(reinterpret_cast<char*>(header),18);for(std::size_t i=0;i<f.rgba.size();i+=4){const char p[]={char(f.rgba[i+2]),char(f.rgba[i+1]),char(f.rgba[i]),char(f.rgba[i+3])};out.write(p,4);}
}
}
int wmain(int argc,wchar_t** argv){
    unsigned seconds=argc>1?std::clamp(unsigned(_wtoi(argv[1])),15u,120u):120u;
    const std::filesystem::path logs=L"G:\\Onimusha_MC_mod\\logs";std::filesystem::create_directories(logs);FILE* file=_wfsopen((logs/L"runtime-smoke-host.log").c_str(),L"w",_SH_DENYNO);if(!file)return 3;_dup2(_fileno(file),_fileno(stdout));fclose(file);setvbuf(stdout,nullptr,_IONBF,0);
    std::ofstream(logs/L"runtime-smoke-host.pid")<<GetCurrentProcessId();
    Bridge link;if(!link.open(L"Local\\OnimushaMC_Smoke")){printf("ERROR %s\n",link.error.c_str());return 2;}
    printf("READY PID=%lu mapping=Local\\OnimushaMC_Smoke timeout=%us; real MC/Fabric IPC test, not Onimusha runtime verification\n",GetCurrentProcessId(),seconds);
    proto::SkyState host{};host.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;host.worldId=1;host.collisionEpoch=1;host.teleportSeq=1;host.posX=4;host.posY=65;host.posZ=4;host.viewportW=854;host.viewportH=480;host.healthCurrent=75;host.healthMax=100;host.healthRevision=1;host.hostUnitsPerBlock=1;host.gameHour=12;
    proto::ColRegion region{-8,48,-8,15,79,15,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,16,16,65,-8},proto::kTriTerrain},{{16,65,-8,-8,65,16,16,65,16},proto::kTriTerrain}};
    proto::ActorRecord enemies[2]{};for(unsigned i=0;i<2;i++){auto& a=enemies[i];a.formId=1001+i;a.flags=proto::kActorHostile|proto::kActorInCombat;a.x=float(i?7:4);a.y=65;a.z=float(i?9:8);a.width=0.8f;a.height=1.8f;a.healthFrac=1;a.level=1;strcpy_s(a.name,i?"Smoke enemy B":"Smoke enemy A");}
    RenderStore store;OverlayFrame hud;proto::McState mc{};const auto started=GetTickCount64();std::uint64_t worldAt{},lastPrint{},lastCollision{},frames{};bool moved=false,gui=false,atlas=false,mesh=false,avatar=false,healthQuery=false,solidAdded=false,solidRemoved=false;double startX{},startZ{};unsigned stage=0,hits=0,healthEvents=0,staleHealthEvents=0;float hpAfterHurt=-1,hpAfterHeal=-1,damageFraction=0,healFraction=0;
    while(GetTickCount64()-started<std::uint64_t(seconds)*1000){
        const auto now=GetTickCount64();link.heartbeat();link.publish_host(host);link.publish_actors(enemies);
        if(now-lastCollision>2000){if(!link.publish_collision(host.collisionEpoch,region,tris))printf("collision publish failure: %s\n",link.error.c_str());lastCollision=now;}
        link.drain_render(store,32ull<<20);if(link.overlay(hud)){++frames;if(frames==1)tga(logs/L"runtime-smoke-first-overlay.tga",hud);}
        atlas=atlas||!store.atlas.rgba.empty();mesh=mesh||!store.sections.empty();avatar=avatar||!store.avatar.vertices.empty();
        for(const auto& s:store.solidChanges){solidAdded=solidAdded||s.solid;solidRemoved=solidRemoved||!s.solid;}store.solidChanges.clear();
        if(link.read_mc(mc)){
            gui=gui||bool(mc.flags&proto::kMcScreenOpen);
            if(!worldAt&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1){worldAt=now;startX=mc.x;startZ=mc.z;printf("MC WORLD ready ack=%u pos=%.3f %.3f %.3f hostHP=%.1f/%.1f expectedMCpoints=15\n",mc.teleportAck,mc.x,mc.y,mc.z,host.healthCurrent,host.healthMax);}
            if(worldAt){const auto elapsed=now-worldAt;moved=moved||std::hypot(mc.x-startX,mc.z-startZ)>0.2;
                if(stage==0&&elapsed>2000){text(link,"data get entity @s Health");healthQuery=true;stage++;printf("ACTION health query (expected 15.0f)\n");}
                else if(stage==1&&elapsed>3500){text(link,"setblock 4 65 10 minecraft:stone");stage++;printf("ACTION create test MC block\n");}
                else if(stage==2&&elapsed>5000){text(link,"give @s minecraft:stone 4");key(link,62);stage++;printf("ACTION give MC item + F5 third person\n");}
                else if(stage==3&&elapsed>6500){link.input(proto::kInKey,26,1);stage++;printf("ACTION W held 1s\n");}
                else if(stage==4&&elapsed>7500){link.input(proto::kInKey,26,0);link.input(proto::kInLookDelta,0,10,0);stage++;}
                else if(stage==5&&elapsed>9000){link.input(proto::kInMouseButton,1,1);link.input(proto::kInMouseButton,1,0);stage++;printf("ACTION MC melee at proxy\n");}
                else if(stage==6&&elapsed>10500){link.input(proto::kInOpenMenu);stage++;printf("ACTION open MC pause\n");}
                else if(stage==7&&elapsed>12000){key(link,41);stage++;printf("ACTION close MC pause\n");}
                else if(stage==8&&elapsed>14000){text(link,"setblock 4 65 10 minecraft:air");stage++;printf("ACTION remove MC block\n");}
                else if(stage==9&&elapsed>15500){link.input(proto::kInHurt,proto::kHurtMelee,300,1001,proto::kHurtHostUnapplied);stage++;printf("ACTION incoming host-unapplied MC damage 3 raw points; MC armour determines mitigated EV6 fraction\n");}
                else if(stage==10&&elapsed>17250){hpAfterHurt=host.healthCurrent;text(link,"data get entity @s Health");stage++;printf("HEALTH after hurt host=%g expectedFromMCArmour=%g; queryexpectedMC=%g\n",hpAfterHurt,75+100*damageFraction,hpAfterHurt/5);}
                else if(stage==11&&elapsed>18750){text(link,"data get entity @s Health");stage++;printf("ACTION duplicate-damage check health query (expected unchanged %g MC points)\n",host.healthCurrent/5);}
                else if(stage==12&&elapsed>20250){text(link,"effect give @s minecraft:instant_health 1 0");stage++;printf("ACTION explicit MC instant-health +4points expected+20nativeHP\n");}
                else if(stage==13&&elapsed>21750){hpAfterHeal=host.healthCurrent;text(link,"data get entity @s Health");stage++;printf("HEALTH after heal host=%g expected=%g; queryexpectedMC=%g\n",hpAfterHeal,hpAfterHurt+20,hpAfterHeal/5);}
                else if(stage==14&&elapsed>23250){
                    link.input(proto::kInHurt,proto::kHurtMelee,200,1001,proto::kHurtHostUnapplied);Sleep(300);
                    host.collisionEpoch=2;host.teleportSeq=2;host.posX=mc.x;host.posY=mc.y;host.posZ=mc.z;link.publish_host(host);link.publish_collision(2,region,tris);stage++;printf("ACTION session epoch2 before consuming old epoch1 MC hurt event; reject stale response\n");
                }
                else if(stage==15&&elapsed>25000){text(link,"data get entity @s Health");stage++;printf("HEALTH after staleevent host=%g expectedUnchanged=%g query=%g\n",host.healthCurrent,hpAfterHeal,hpAfterHeal/5);}
                else if(stage==16&&elapsed>26500){link.input(proto::kInReleaseAll);stage++;tga(logs/L"runtime-smoke-final-overlay.tga",hud);printf("ACTIONS complete\n");}
                if(stage==17&&elapsed>29000)break;
            }
        }
        for(const auto& e:link.events()){
            printf("EVENT type=%u id=%u a=%g b=%g flags=%u epoch/weapon=%u\n",e.type,e.formId,e.a,e.b,e.flags,e.weapon);
            if(e.type==proto::kEvHitActor){++hits;for(auto& enemy:enemies)if(enemy.formId==e.formId)enemy.healthFrac=std::max(0.0f,enemy.healthFrac-e.a*0.05f);}
            if(e.type==proto::kEvHealthChange){if(e.weapon==host.collisionEpoch){++healthEvents;if(e.a<0)damageFraction+=e.a;else healFraction+=e.a;host.healthCurrent=std::clamp(host.healthCurrent+e.a*host.healthMax,0.0f,host.healthMax);++host.healthRevision;printf("APPLY healthfraction=%g hostHP=%g epoch=%u\n",e.a,host.healthCurrent,host.collisionEpoch);}else{++staleHealthEvents;printf("REJECT stale health response eventepoch=%u currentepoch=%u HPunchanged=%g\n",e.weapon,host.collisionEpoch,host.healthCurrent);}}
        }
        if(now-lastPrint>2000){printf("tick=%llums alive=%d MCflags=%u ack=%u xyz=%.3f,%.3f,%.3f atlas=%ux%u sections=%zu avatarVerts=%zu hud=%lluframes rejected=%llu\n",now-started,link.alive(),mc.flags,mc.teleportAck,mc.x,mc.y,mc.z,store.atlas.width,store.atlas.height,store.sections.size(),store.avatar.vertices.size(),frames,link.rejected);lastPrint=now;}
        Sleep(16);
    }
    link.input(proto::kInReleaseAll);host.flags|=proto::kSkyMenuOpen;link.publish_host(host);link.heartbeat();Sleep(250);
    const bool passed=worldAt&&atlas&&mesh&&avatar&&frames&&moved&&gui&&solidAdded&&solidRemoved&&healthEvents==2&&staleHealthEvents>=1&&damageFraction<0&&damageFraction>=-0.151f&&std::abs(healFraction-0.2f)<0.001f&&std::abs(hpAfterHurt-(75+100*damageFraction))<0.1f&&std::abs(hpAfterHeal-(hpAfterHurt+20))<0.1f&&std::abs(host.healthCurrent-hpAfterHeal)<0.1f;
    printf("RESULT pass=%d inworld=%d atlas=%d meshes=%d avatar=%d HUDframes=%llu movement=%d GUI=%d healthQuerySent=%d hits=%u healthEvents=%u staleRejected=%u HPafterHurt=%g HPafterHeal=%g HPfinal=%g solidAdded=%d solidRemoved=%d rejected=%llu\n",passed,worldAt!=0,atlas,mesh,avatar,frames,moved,gui,healthQuery,hits,healthEvents,staleHealthEvents,hpAfterHurt,hpAfterHeal,host.healthCurrent,solidAdded,solidRemoved,link.rejected);
    std::ofstream result(logs/L"runtime-smoke-result.json");result<<"{\"scope\":\"real Minecraft Fabric plus simulated native host; not Onimusha verification\",\"passed\":"<<(passed?"true":"false")<<",\"world\":"<<(worldAt?"true":"false")<<",\"atlas\":"<<(atlas?"true":"false")<<",\"meshes\":"<<(mesh?"true":"false")<<",\"avatar\":"<<(avatar?"true":"false")<<",\"overlayFrames\":"<<frames<<",\"movement\":"<<(moved?"true":"false")<<",\"gui\":"<<(gui?"true":"false")<<",\"expectedMinecraftHealth\":15,\"healthQuerySent\":"<<(healthQuery?"true":"false")<<",\"combatHits\":"<<hits<<",\"healthChangesApplied\":"<<healthEvents<<",\"staleHealthChangesRejected\":"<<staleHealthEvents<<",\"hpAfterHurt\":"<<hpAfterHurt<<",\"hpAfterHeal\":"<<hpAfterHeal<<",\"hpFinal\":"<<host.healthCurrent<<",\"solidAdded\":"<<(solidAdded?"true":"false")<<",\"solidRemoved\":"<<(solidRemoved?"true":"false")<<",\"rejectedPackets\":"<<link.rejected<<"}";
    // Keep dead host PID in the mapping for SkyClient's ProcessHandle watchdog. It saves/exits
    // after this process closes; setting hostPid=0 would intentionally skip that watchdog.
    auto* header=reinterpret_cast<proto::Header*>(link.testing_base());std::atomic_ref(header->skyrimHeartbeatMs).store(0,std::memory_order_release);
    result.flush();result.close();std::fflush(stdout);ExitProcess(passed?0:1);
}
