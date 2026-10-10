#include "Bridge.hpp"
#include <cstdio>
int main(){
    using namespace omc;Bridge link;if(!link.open(L"Local\\OnimushaMC_NpcDamageSmoke"))return 2;
    proto::SkyState host{};host.flags=proto::kSkyInGame|proto::kSkyAuthoritativeHealth|proto::kSkyNativeTerrainProtected|proto::kSkyMcLook;
    host.worldId=1;host.collisionEpoch=1;host.teleportSeq=1;host.posX=0;host.posY=65.375;host.posZ=0;
    host.viewportW=854;host.viewportH=480;host.healthCurrent=100;host.healthMax=100;host.hostUnitsPerBlock=1;
    proto::ColRegion region{-16,48,-16,23,87,23,1,0};
    proto::ColTri tris[2]={{{-16,65.375f,-16,-16,65.375f,24,24,65.375f,-16},0},{{24,65.375f,-16,-16,65.375f,24,24,65.375f,24},0}};
    proto::ActorRecord enemy{};enemy.formId=1001;enemy.flags=proto::kActorHostile|proto::kActorInCombat;
    enemy.x=0;enemy.y=65.375f;enemy.z=-2;enemy.width=.8f;enemy.height=1.8f;enemy.healthFrac=1;strcpy_s(enemy.name,"Incoming attack source");
    proto::NativeAttack a{};a.attackerId=1001;a.attackId=77;a.hitId=1;a.shape=1;a.damage=4;a.maxHits=1;
    a.origin[1]=65.375f;a.origin[2]=-2;
    a.geometry[1]=65.875f;a.geometry[4]=67.375f;a.geometry[6]=.6f;std::copy_n(a.geometry,7,a.geometry+7);
    RenderStore store;OverlayFrame overlay;auto start=GetTickCount64();std::uint64_t terrain=0,last=0;int stage=0;
    while(GetTickCount64()-start<180000){
        link.heartbeat();link.publish_host(host);link.publish_actors(std::span(&enemy,1));
        if(GetTickCount64()-terrain>2000){link.publish_collision(1,region,tris);terrain=GetTickCount64();}
        link.drain_render(store,32ull<<20);link.overlay(overlay);
        for(auto e:link.events())if(e.type==proto::kEvSkillUse&&e.formId==0x4E5043){stage=int(e.a);printf("NPC_SMOKE_STAGE %d\n",stage);fflush(stdout);}
        if(stage==9){link.publish_attacks(false,1,1,{});puts("NPC_SMOKE_COMPLETED");return 0;}
        if(GetTickCount64()-last>=16){
            if(stage==1||stage==2||stage==4){a.hitId=stage;a.damage=stage==4?10000.f:4.f;link.publish_attacks(true,1,1,std::span(&a,1));}
            else link.publish_attacks(false,1,1,{});
            last=GetTickCount64();
        }
        Sleep(5);
    }
    puts("NPC_SMOKE_TIMEOUT");return 3;
}
