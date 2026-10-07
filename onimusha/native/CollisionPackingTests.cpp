#include "CollisionPacking.hpp"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>

// Offline replay of a complete read-only RE area-query capture. Never maps the game.
int main(int argc,char** argv){
    if(argc!=2){std::fprintf(stderr,"Usage: omc_collision_replay <bounds-and-triangles.bin>\n");return 2;}
    std::ifstream input(argv[1],std::ios::binary);
    omc::proto::ColRegion bounds{};
    if(!input.read(reinterpret_cast<char*>(&bounds),sizeof(bounds))||bounds.count>100000)return 3;
    std::vector<omc::proto::ColTri> tris(bounds.count);
    if(!input.read(reinterpret_cast<char*>(tris.data()),tris.size()*sizeof(tris[0])))return 4;
    std::vector<omc::CollisionPacket> packets;std::string error;
    const auto start=std::chrono::steady_clock::now();
    const bool ok=omc::pack_collision(bounds,tris,packets,error);
    std::size_t bytes=0,blocks=0;
    for(const auto& p:packets){bytes+=p.payload.size();if(p.type==omc::proto::kColRegion){omc::proto::ColRegion h;std::memcpy(&h,p.payload.data(),sizeof(h));blocks+=h.count;}}
    const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    std::printf("ok=%d triangles=%zu packets=%zu bytes=%zu blocks=%zu elapsed_ms=%.3f error=%s\n",ok,tris.size(),packets.size(),bytes,blocks,ms,error.c_str());
    if(ok){std::ofstream output(std::string(argv[1])+".packed",std::ios::binary);for(const auto& p:packets){auto len=std::uint32_t(p.payload.size());output.write(reinterpret_cast<const char*>(&p.type),4);output.write(reinterpret_cast<const char*>(&len),4);output.write(reinterpret_cast<const char*>(p.payload.data()),p.payload.size());}}
    return ok?0:1;
}
