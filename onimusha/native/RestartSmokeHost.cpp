#include "Bridge.hpp"
#include <Windows.h>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <io.h>
#include <share.h>

namespace {
using namespace omc;
const std::filesystem::path logs=L"G:\\Onimusha_MC_mod\\logs";
void command(Bridge& link,const char* s){link.input(proto::kInKey,56,1);link.input(proto::kInKey,56,0);Sleep(200);for(;*s;s++)link.input(proto::kInText,0,*s);link.input(proto::kInKey,40,1);link.input(proto::kInKey,40,0);}
bool block(const RenderStore& store){const auto it=store.solids.find({0,4,0});constexpr int index=4+(10<<4)+(1<<8);return it!=store.solids.end()&&(it->second[index>>3]&(1u<<(index&7)));}
[[noreturn]] void finish(Bridge& link,bool pass){link.input(proto::kInReleaseAll);auto* h=reinterpret_cast<proto::Header*>(link.testing_base());std::atomic_ref(h->skyrimHeartbeatMs).store(0,std::memory_order_release);std::fflush(stdout);ExitProcess(pass?0:1);}
}
int wmain(int argc,wchar_t** argv){
    const bool second=argc==5&&std::wstring(argv[1])==L"--second";const DWORD oldPid=second?DWORD(std::wcstoul(argv[2],nullptr,10)):0;const auto deadline=second?std::wcstoull(argv[3],nullptr,10):GetTickCount64()+120000;const DWORD expectedPeer=second?DWORD(std::wcstoul(argv[4],nullptr,10)):0;
    std::filesystem::create_directories(logs);FILE* f=_wfsopen((logs/(second?L"restart-smoke-second.log":L"restart-smoke-first.log")).c_str(),L"w",_SH_DENYNO);if(!f)return 2;_dup2(_fileno(f),_fileno(stdout));fclose(f);setvbuf(stdout,nullptr,_IONBF,0);
    if(second){HANDLE old=OpenProcess(SYNCHRONIZE,FALSE,oldPid);if(old){const auto wait=WaitForSingleObject(old,3000);CloseHandle(old);if(wait!=WAIT_OBJECT_0){printf("FAIL old host did not exit within3s\n");return 3;}}}
    Bridge link;if(!link.open(L"Local\\OnimushaMC_Smoke")){printf("FAIL %s\n",link.error.c_str());return 4;}
    const auto started=GetTickCount64();printf("READY phase=%d PID=%lu oldPID=%lu expectedMCPID=%lu deadline=%llu mapping=Local\\OnimushaMC_Smoke\n",second?2:1,GetCurrentProcessId(),oldPid,expectedPeer,deadline);
    proto::SkyState host{};host.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;host.worldId=1;host.collisionEpoch=1;host.teleportSeq=1;host.posX=second?12:4;host.posY=65;host.posZ=4;host.healthCurrent=75;host.healthMax=100;host.healthRevision=1;host.hostUnitsPerBlock=1;host.viewportW=854;host.viewportH=480;
    proto::ColRegion region{-8,48,-8,15,79,15,1,0};proto::ColTri floor[2]={{{-8,65,-8,-8,65,16,16,65,-8},proto::kTriTerrain},{{16,65,-8,-8,65,16,16,65,16},proto::kTriTerrain}};
    RenderStore store;OverlayFrame hud;proto::McState mc{};std::uint64_t worldAt{},lastCollision{},lastPrint{},frames{},holdObservations{};unsigned stage=0;bool atlas=false,mesh=false,solid=false,moved=false,earlyAck=false,collisionSent=false;DWORD peer{};
    while(GetTickCount64()<deadline){
        const auto now=GetTickCount64();link.heartbeat();link.publish_host(host);
        if((!second||now-started>=1500)&&(!collisionSent||now-lastCollision>2000)){collisionSent=link.publish_collision(1,region,floor);lastCollision=now;if(collisionSent&&second&&now-started<2000)printf("FRESH COLLISION sent at%llums\n",now-started);}
        link.drain_render(store,32ull<<20);if(link.overlay(hud))++frames;atlas=atlas||!store.atlas.rgba.empty();mesh=mesh||store.sections.contains({0,4,0});solid=solid||block(store);store.solidChanges.clear();
        if(link.read_mc(mc)){
            peer=reinterpret_cast<proto::Header*>(link.testing_base())->mcPid;
            if(second&&!collisionSent){++holdObservations;if(mc.teleportAck!=0)earlyAck=true;}
            if(!worldAt&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1&&collisionSent){worldAt=now;printf("WORLD phase=%d MCpid=%lu ack=%u pos=%.3f %.3f %.3f holdObservations=%llu earlyAck=%d\n",second?2:1,peer,mc.teleportAck,mc.x,mc.y,mc.z,holdObservations,earlyAck);}
            if(worldAt){const auto elapsed=now-worldAt;
                if(!second){
                    if(stage==0&&elapsed>1500){command(link,"setblock 4 65 10 minecraft:stone");stage++;printf("ACTION place persistent test stone\n");}
                    else if(stage==1&&elapsed>3000){link.input(proto::kInKey,26,1);stage++;}
                    else if(stage==2&&elapsed>4000){link.input(proto::kInKey,26,0);stage++;}
                    moved=moved||std::hypot(mc.x-4,mc.z-4)>0.2;
                    if(elapsed>7000&&atlas&&mesh&&solid&&moved&&frames){
                        wchar_t exe[MAX_PATH]{};GetModuleFileNameW(nullptr,exe,MAX_PATH);std::wstring args=L"\""+std::wstring(exe)+L"\" --second "+std::to_wstring(GetCurrentProcessId())+L" "+std::to_wstring(deadline)+L" "+std::to_wstring(peer);STARTUPINFOW si{sizeof(si)};PROCESS_INFORMATION pi{};const bool launched=CreateProcessW(nullptr,args.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&si,&pi);
                        if(launched){printf("HANDOFF secondPID=%lu; firstPASS atlas=%d mesh=%d block=%d movement=%d HUD=%llu\n",pi.dwProcessId,atlas,mesh,solid,moved,frames);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);finish(link,true);}printf("FAIL child launch=%lu\n",GetLastError());break;
                    }
                }else if(elapsed>7000&&atlas&&mesh&&solid&&frames){
                    const bool pass=peer==expectedPeer&&peer!=0&&std::abs(mc.x-12)<0.2&&std::abs(mc.z-4)<0.2&&holdObservations>=5&&!earlyAck&&GetCurrentProcessId()!=oldPid;
                    printf("RESULT pass=%d sameMCpid=%d reusedEpochSeq=1 delayedAck=%d observations=%llu newSpawn=%.3f %.3f %.3f atlas=%d existingMesh=%d existingSolid=%d HUD=%llu rejected=%llu\n",pass,peer==expectedPeer,!earlyAck,holdObservations,mc.x,mc.y,mc.z,atlas,mesh,solid,frames,link.rejected);
                    std::ofstream result(logs/L"restart-smoke-result.json");result<<"{\"scope\":\"real Fabric client, two simulated native PIDs; not Onimusha\",\"passed\":"<<(pass?"true":"false")<<",\"oldHostPid\":"<<oldPid<<",\"newHostPid\":"<<GetCurrentProcessId()<<",\"clientPid\":"<<peer<<",\"sameClient\":"<<(peer==expectedPeer?"true":"false")<<",\"collisionDelayMs\":1500,\"heldAckObservations\":"<<holdObservations<<",\"earlyAck\":"<<(earlyAck?"true":"false")<<",\"x\":"<<mc.x<<",\"y\":"<<mc.y<<",\"z\":"<<mc.z<<",\"atlasReexported\":"<<(atlas?"true":"false")<<",\"blockMeshReexported\":"<<(mesh?"true":"false")<<",\"blockSolidReexported\":"<<(solid?"true":"false")<<"}";result.close();finish(link,pass);
                }
            }
        }
        if(now-lastPrint>2000){printf("tick=%llums MC=%d pid=%lu flags=%u ack=%u pos=%.3f %.3f %.3f collision=%d atlas=%d mesh=%d block=%d HUD=%llu\n",now-started,link.alive(),peer,mc.flags,mc.teleportAck,mc.x,mc.y,mc.z,collisionSent,atlas,mesh,solid,frames);lastPrint=now;}Sleep(16);
    }
    printf("RESULT pass=0 timeout phase=%d atlas=%d mesh=%d solid=%d frames=%llu earlyAck=%d\n",second?2:1,atlas,mesh,solid,frames,earlyAck);finish(link,false);
}
