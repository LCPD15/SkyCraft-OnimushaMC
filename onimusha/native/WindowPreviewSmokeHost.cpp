#include "Bridge.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <cstdio>
using namespace omc;
namespace {
void key(Bridge& b,unsigned short k){b.input(proto::kInKey,k,1);b.input(proto::kInKey,k,0);}
void command(Bridge&b,const char*s){key(b,56);Sleep(120);for(;*s;s++)b.input(proto::kInText,0,*s);key(b,40);}
}
int main(){
    const std::filesystem::path out=L"G:/Onimusha_MC_mod/logs/window-preview-20261010";
    std::filesystem::create_directories(out);
    Bridge b;if(!b.open(L"Local\\OnimushaMC_WindowSmoke"))return 2;
    proto::SkyState h{};h.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
    h.worldId=1;h.collisionEpoch=1;h.teleportSeq=1;h.posX=4;h.posY=65;h.posZ=4;h.pitch=45;h.viewportW=854;h.viewportH=480;h.healthCurrent=100;h.healthMax=100;h.healthRevision=1;h.hostUnitsPerBlock=1;h.gameHour=12;
    proto::ColRegion region{-8,48,-8,31,79,31,1,0};proto::ColTri tris[2]={{{-8,65,-8,-8,65,32,32,65,-8},proto::kTriTerrain},{{32,65,-8,-8,65,32,32,65,32},proto::kTriTerrain}};
    RenderStore store;proto::McState mc{};OverlayFrame hud;auto started=GetTickCount64();ULONGLONG ready{},lastCol{};int stage=0;bool placed=false,placedAfterGui=false;unsigned long long transparent=0,pixels=0;
    while(GetTickCount64()-started<120000){
        auto now=GetTickCount64();b.heartbeat();b.publish_host(h);auto c=b.collision_status();store.set_cube_context(h.worldId,h.collisionEpoch,c.mcPid,c.generation,c.connected);
        if(now-lastCol>2000){b.publish_collision(1,region,tris);lastCol=now;}
        b.drain_render(store,32ull<<20);
        if(b.overlay(hud)&&stage>=2){pixels=hud.rgba.size()/4;transparent=0;for(size_t i=3;i<hud.rgba.size();i+=4)if(hud.rgba[i]==0)transparent++;}
        if(b.read_mc(mc)){
            if(!ready&&(mc.flags&proto::kMcInWorld)&&mc.teleportAck==1)ready=now;
            if(ready){auto elapsed=now-ready;
                if(stage==0&&elapsed>2000){command(b,"item replace entity @s weapon.mainhand with minecraft:stone 32");stage++;}
                else if(stage==1&&elapsed>4000){b.input(proto::kInMouseButton,3,1);b.input(proto::kInMouseButton,3,0);stage++;}
                else if(stage==2&&elapsed>7000){placed=!store.nearby_cubes(4,65,6,16,128).rows.empty();command(b,"fill 2 65 10 6 68 10 minecraft:gold_block");stage++;}
                else if(stage==3&&elapsed>10000){key(b,8);stage++;}
                else if(stage==4&&elapsed>11500){key(b,41);stage++;}
                else if(stage==5&&elapsed>13000){h.posX=8;h.teleportSeq=2;stage++;}
                else if(stage==6&&elapsed>18000&&mc.teleportAck==2){b.input(proto::kInMouseButton,3,1);b.input(proto::kInMouseButton,3,0);stage++;}
                else if(stage==7&&elapsed>21000){placedAfterGui=!store.nearby_cubes(8,65,5,1,128).rows.empty();stage++;}
                // Leave the scene available for framebuffer inspection, then quit normally.
                else if(stage==8&&elapsed>45000)break;
            }
        }
        Sleep(16);
    }
    // The large first-person shield and held block occupy roughly a quarter of the frame.
    bool passed=placed&&placedAfterGui&&pixels&&transparent>pixels*0.6&&store.invalidMessages==0;
    std::ofstream j(out/"host.json");j<<"{\"stage\":"<<stage<<",\"passed\":"<<passed<<",\"placed_via_mouse\":"<<placed<<",\"placed_after_gui\":"<<placedAfterGui<<",\"pixels\":"<<pixels<<",\"transparent_overlay_pixels\":"<<transparent<<",\"invalid_packets\":"<<store.invalidMessages<<"}";
    return passed?0:1;
}
