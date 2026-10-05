#include "RenderStore.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace omc {
namespace {
constexpr std::size_t kMaxVertices=2'000'000, kMaxTextures=512, kMaxSections=8192;
template<class T> bool read(std::span<const std::uint8_t> p,T& out,std::size_t off=0) {
    if(off>p.size() || sizeof(T)>p.size()-off) return false;
    std::memcpy(&out,p.data()+off,sizeof(T)); return true;
}
bool texture(Texture& out,std::span<const std::uint8_t> p,std::size_t off,std::uint32_t w,std::uint32_t h,std::uint64_t rev) {
    if(!w||!h||w>8192||h>8192) return false;
    const std::uint64_t size=std::uint64_t(w)*h*4;
    if(size>32ull*1024*1024||off>p.size()||size!=p.size()-off) return false;
    out.width=w; out.height=h; out.rgba.assign(p.begin()+off,p.end()); out.revision=rev; return true;
}
bool mesh(Mesh& out,std::span<const std::uint8_t> p,std::size_t off,std::uint32_t bc,std::uint32_t vc,std::uint64_t rev) {
    if(vc>kMaxVertices||vc%3||bc>65536) return false;
    const auto bytes=std::uint64_t(bc)*sizeof(proto::RenBatch)+std::uint64_t(vc)*sizeof(proto::RenVertex);
    if(off>p.size()||bytes!=p.size()-off) return false;
    Mesh temp; temp.batches.resize(bc); temp.vertices.resize(vc);
    if(bc) std::memcpy(temp.batches.data(),p.data()+off,bc*sizeof(proto::RenBatch));
    if(vc) std::memcpy(temp.vertices.data(),p.data()+off+bc*sizeof(proto::RenBatch),vc*sizeof(proto::RenVertex));
    for(const auto& b:temp.batches) if(b.first>vc||b.count>vc-b.first||b.count%3) return false;
    for(const auto& v:temp.vertices) if(!std::isfinite(v.x)||!std::isfinite(v.y)||!std::isfinite(v.z)||!std::isfinite(v.u)||!std::isfinite(v.v)) return false;
    temp.revision=rev; out=std::move(temp); return true;
}
}
void RenderStore::clear() {
    for(const auto& [k,bits]:solids) for(int i=0;i<4096;i++) if(bits[i>>3]&(1u<<(i&7)))
        solidChanges.push_back({k.x*16+(i&15),k.y*16+(i>>8),k.z*16+((i>>4)&15),false});
    sections.clear(); solids.clear(); avatar={}; scene={}; worldEntities={}; ++revision;
}
bool RenderStore::consume(std::uint32_t type,std::span<const std::uint8_t> p) {
    const auto rev=++revision;
    bool ok=false;
    switch(type) {
    case proto::kRenClearAll: if(p.empty()){clear();ok=true;} break;
    case proto::kRenAtlas: {
        proto::RenAtlas h; ok=read(p,h)&&texture(atlas,p,sizeof(h),h.width,h.height,rev); break;
    }
    case proto::kRenTexture: {
        proto::RenTexture h;
        if(read(p,h)&&h.id>0&&(textures.contains(h.id)||textures.size()<kMaxTextures)) {
            Texture t; ok=texture(t,p,sizeof(h),h.width,h.height,rev); if(ok) textures[h.id]=std::move(t);
        } break;
    }
    case proto::kRenAtlasRegion: {
        proto::RenAtlasRegion h;
        if(!read(p,h)||!h.width||!h.height||h.x>atlas.width||h.y>atlas.height||h.width>atlas.width-h.x||h.height>atlas.height-h.y||p.size()!=sizeof(h)+std::uint64_t(h.width)*h.height*4) break;
        for(std::uint32_t y=0;y<h.height;y++) std::memcpy(atlas.rgba.data()+((std::size_t(h.y+y)*atlas.width+h.x)*4),p.data()+sizeof(h)+std::size_t(y)*h.width*4,std::size_t(h.width)*4);
        atlas.revision=rev; ok=true; break;
    }
    case proto::kRenSection: {
        proto::RenSection h; if(!read(p,h)) break;
        SectionKey k{h.sx,h.sy,h.sz};
        if(std::abs(std::int64_t(h.sx))>1'000'000||std::abs(std::int64_t(h.sy))>1'000'000||std::abs(std::int64_t(h.sz))>1'000'000) break;
        if(h.vertexCount==0&&p.size()==sizeof(h)){sections.erase(k);ok=true;break;}
        if(!sections.contains(k)&&sections.size()>=kMaxSections) break;
        Mesh m; ok=mesh(m,p,sizeof(h),0,h.vertexCount,rev); if(ok){m.origin[0]=double(h.sx)*16;m.origin[1]=double(h.sy)*16;m.origin[2]=double(h.sz)*16;sections[k]=std::move(m);} break;
    }
    case proto::kRenAvatar: {
        proto::RenAvatar h; ok=read(p,h)&&mesh(avatar,p,sizeof(h),h.batchCount,h.vertexCount,rev); break;
    }
    case proto::kRenScene: {
        proto::RenScene h; if(!read(p,h)||!std::isfinite(h.originX)||!std::isfinite(h.originY)||!std::isfinite(h.originZ))break;
        ok=mesh(scene,p,sizeof(h),h.batchCount,h.vertexCount,rev);if(ok){scene.origin[0]=h.originX;scene.origin[1]=h.originY;scene.origin[2]=h.originZ;} break;
    }
    case proto::kRenSolids: {
        proto::RenSolids h; if(!read(p,h)||h.count>4096||p.size()!=sizeof(h)+(h.count?512:0))break;
        SectionKey k{h.sx,h.sy,h.sz};
        if(std::abs(std::int64_t(h.sx))>1'000'000||std::abs(std::int64_t(h.sy))>1'000'000||std::abs(std::int64_t(h.sz))>1'000'000)break;
        if(!solids.contains(k)&&solids.size()>=kMaxSections) break;
        std::array<std::uint8_t,512> next{},old{};
        if(h.count)std::memcpy(next.data(),p.data()+sizeof(h),512);
        const auto found=solids.find(k);if(found!=solids.end())old=found->second;
        std::uint32_t count=0;for(int i=0;i<4096;i++)count+=(next[i>>3]>>(i&7))&1u;
        if(count!=h.count)break;
        for(int i=0;i<4096;i++){const bool a=(old[i>>3]&(1u<<(i&7)))!=0,b=(next[i>>3]&(1u<<(i&7)))!=0;if(a!=b)solidChanges.push_back({k.x*16+(i&15),k.y*16+(i>>8),k.z*16+((i>>4)&15),b});}
        if(h.count)solids[k]=next;else solids.erase(k);ok=true;break;
    }
    // Native terrain destruction intentionally unsupported: original terrain is protected.
    case proto::kRenDug: case proto::kRenRagdoll: case proto::kRenLights: ok=true;break;
    default: break;
    }
    if(!ok)++invalidMessages;
    return ok;
}
}
