// Real Fabric export + isolated IPC host. Never attaches to the live game's mapping.
#include "Bridge.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <set>
#include <cmath>
using namespace omc;
namespace {
void command(Bridge&b,const char*s){b.input(proto::kInKey,56,1);b.input(proto::kInKey,56,0);Sleep(180);for(;*s;s++)b.input(proto::kInText,0,*s);b.input(proto::kInKey,40,1);b.input(proto::kInKey,40,0);}
void write(const std::filesystem::path&p,const void*h,size_t hs,const void*d,size_t n){std::ofstream f(p,std::ios::binary);f.write(static_cast<const char*>(h),hs);f.write(static_cast<const char*>(d),n);}
}
int main(){
    const std::filesystem::path out=L"G:/Onimusha_MC_mod/logs/automatic-models-20261008/real-mc";std::filesystem::create_directories(out);
    Bridge b;if(!b.open(L"Local\\OnimushaMC_ModelSmoke"))return 2;
    proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
    h.worldId=1;h.collisionEpoch=1;h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=3;h.viewportW=854;h.viewportH=480;h.healthCurrent=100;h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
    proto::ColRegion region{-8,48,-8,31,79,31,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
    RenderStore store;proto::McState mc{};auto start=GetTickCount64();ULONGLONG ready{},lastCol{};int stage=0;std::uint32_t firstId{};bool chat=false,stable=false,same=false,turned=false;
    const char*commands[]={"gamemode creative","fill 4 64 6 10 64 7 minecraft:stone","setblock 4 65 7 minecraft:stone","setblock 4 65 6 minecraft:ladder[facing=north]","setblock 5 65 6 minecraft:carved_pumpkin[facing=north]","setblock 6 65 6 minecraft:carved_pumpkin[facing=north]","setblock 7 65 6 minecraft:oak_stairs[facing=east]","setblock 8 65 6 minecraft:red_wool","setblock 9 65 6 minecraft:oak_leaves[persistent=true]","setblock 10 65 6 minecraft:torch"};
    while(GetTickCount64()-start<120000){
        auto now=GetTickCount64();b.heartbeat();b.publish_host(h);auto c=b.collision_status();store.set_cube_context(h.worldId,h.collisionEpoch,c.mcPid,c.generation,c.connected);
        if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
        b.drain_render(store,32ull<<20);
        if(b.read_mc(mc)){
            chat=chat||bool(mc.flags&proto::kMcScreenOpen);
            if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1)ready=now;
            if(ready){
                auto elapsed=now-ready;
                if(stage<int(std::size(commands))&&elapsed>2000+stage*1300){command(b,commands[stage++]);}
                else if(stage==10&&elapsed>18000){
                    auto rows=store.nearby_instances(6,65,6);for(auto r:rows)if(r.x==5&&r.y==65&&r.z==6)firstId=r.kind;
                    for(auto r:rows)if(r.x==6&&r.y==65&&r.z==6)same=firstId&&r.kind==firstId;
                    command(b,"setblock 6 65 6 minecraft:carved_pumpkin[facing=south]");stage++;
                }else if(stage==11&&elapsed>22000){
                    for(auto r:store.nearby_instances(6,65,6)){if(r.x==5&&r.y==65&&r.z==6)stable=r.kind==firstId;if(r.x==6&&r.y==65&&r.z==6)turned=r.kind!=firstId;}
                    stage++;
                }else if(stage==12&&elapsed>25000)break;
            }
        }
        Sleep(16);
    }
    auto rows=store.nearby_instances(6,65,6);std::set<unsigned>ids;
    std::ofstream j(out/"models.json");j<<"{\"chat\":"<<chat<<",\"same_model_shared\":"<<same<<",\"neighbor_edit_stable\":"<<stable<<",\"rotation_distinct\":"<<turned<<",\"invalid_packets\":"<<store.invalidMessages<<",\"rows\":[";bool first=true;
    for(auto r:rows){if(!first)j<<',';first=false;j<<"{\"x\":"<<r.x<<",\"y\":"<<r.y<<",\"z\":"<<r.z<<",\"model\":"<<r.kind<<"}";ids.insert(r.kind);}j<<"]}";j.close();
    for(auto id:ids){auto&m=store.blockModels.at(id);proto::RenSection header{0,0,0,std::uint32_t(m.vertices.size())};write(out/("model_"+std::to_string(id)+".bin"),&header,sizeof(header),m.vertices.data(),m.vertices.size()*sizeof(proto::RenVertex));}
    proto::RenAtlas ah{store.atlas.width,store.atlas.height};write(out/"atlas.bin",&ah,sizeof(ah),store.atlas.rgba.data(),store.atlas.rgba.size());
    std::ofstream anim(out/"animated.json");anim<<'[';first=true;for(auto r:store.animatedAtlasRects){if(!first)anim<<',';first=false;anim<<'['<<r.x<<','<<r.y<<','<<r.w<<','<<r.h<<']';}anim<<']';anim.close();
    const bool passed=stage==12&&same&&stable&&turned&&chat&&ids.size()>=7&&!store.invalidMessages;
    // Process lifetime watchdog saves/quits the isolated world. No real-game input.
    printf("Automatic-model Fabric capture passed=%d rows=%zu models=%zu\n",passed,rows.size(),ids.size());
    std::fflush(stdout);ExitProcess(passed?0:1);
}
