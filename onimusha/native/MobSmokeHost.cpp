#include "Bridge.hpp"
#include <Windows.h>
#include <cstdio>
#include <cstring>
// No keyboard, mouse or game control. Separate IPC host for the isolated MC regression world.
int main(){
    using namespace omc;Bridge link;if(!link.open(L"Local\\OnimushaMC_MobSmoke"))return 2;
    proto::SkyState host{};host.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
    host.worldId=1;host.collisionEpoch=1;host.teleportSeq=1;host.posX=-4;host.posY=65.375;host.posZ=-4;
    host.viewportW=854;host.viewportH=480;host.healthCurrent=100;host.healthMax=100;host.healthRevision=1;host.hostUnitsPerBlock=1;
    proto::ColRegion region{-16,48,-16,23,87,23,1,0};
    proto::ColTri tris[2]={{{-16,65.375f,-16,-16,65.375f,24,24,65.375f,-16},0},{{24,65.375f,-16,-16,65.375f,24,24,65.375f,24},0}};
    proto::ActorRecord enemy{};enemy.formId=1001;enemy.flags=proto::kActorHostile|proto::kActorInCombat;
    enemy.x=8;enemy.y=65.375f;enemy.z=5;enemy.width=.8f;enemy.height=1.8f;enemy.healthFrac=1;strcpy_s(enemy.name,"Mob smoke enemy");
    RenderStore store;OverlayFrame overlay;auto start=GetTickCount64();std::uint64_t last=0;
    while(GetTickCount64()-start<100000){
        link.heartbeat();link.publish_host(host);link.publish_actors(std::span(&enemy,1));
        if(GetTickCount64()-last>2000){link.publish_collision(1,region,tris);last=GetTickCount64();}
        link.drain_render(store,32ull<<20);link.overlay(overlay);
        for(const auto& e:link.events())if(e.type==proto::kEvHitActor)printf("MOB_SMOKE_NATIVE_HIT %u %.2f\n",e.formId,e.a);
        Sleep(10);
    }
}
