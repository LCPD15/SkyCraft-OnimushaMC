#include "RenderStore.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <set>

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
    temp.revision=temp.nativeRevision=rev; out=std::move(temp); return true;
}
std::vector<AtlasRect> atlas_rects(const Mesh&m,const Texture&t) {
    if(!t.width||!t.height)return {};
    std::set<AtlasRect> unique;
    for(std::size_t i=0;i<m.vertices.size();i+=3){
        double u0=1,v0=1,u1=0,v1=0;
        for(std::size_t j=0;j<3;j++){const auto&v=m.vertices[i+j];u0=std::min(u0,double(v.u));v0=std::min(v0,double(v.v));u1=std::max(u1,double(v.u));v1=std::max(v1,double(v.v));}
        auto low=[](double a,std::uint32_t n){return std::uint32_t(std::clamp(std::floor(a*n)-2.,0.,double(n)));};
        auto high=[](double a,std::uint32_t n){return std::uint32_t(std::clamp(std::ceil(a*n)+2.,0.,double(n)));};
        const auto x=low(u0,t.width),y=low(v0,t.height),right=high(u1,t.width),bottom=high(v1,t.height);
        unique.insert({x,y,right-x,bottom-y});
        if(unique.size()>2048)return {{0,0,t.width,t.height}};
    }
    return {unique.begin(),unique.end()};
}
bool overlaps(AtlasRect a,AtlasRect b){return a.x<b.x+b.w&&b.x<a.x+a.w&&a.y<b.y+b.h&&b.y<a.y+a.h;}
NativeCube tagged_cube(const proto::RenVertex* v,SectionKey k){
    const auto kind=(v[0].flags>>8)&255,face=(v[0].flags>>4)&7;
    if(!kind||kind>16||!face||face>6)return {};
    constexpr int normals[6][3]={{0,-1,0},{0,1,0},{0,0,-1},{0,0,1},{-1,0,0},{1,0,0}};
    const auto*n=normals[face-1];double center[3]{};
    for(int j=0;j<3;j++){
        if(v[j].flags!=v[0].flags||(v[j].flags&2)||(v[j].color>>24)!=255)return {};
        center[0]+=v[j].x/3.;center[1]+=v[j].y/3.;center[2]+=v[j].z/3.;
    }
    int local[3];for(int a=0;a<3;a++){local[a]=int(std::floor(center[a]-n[a]*.002));if(local[a]<0||local[a]>15)return {};}
    for(int j=0;j<3;j++){const float pos[]={v[j].x,v[j].y,v[j].z};for(int a=0;a<3;a++){
        if(pos[a]<local[a]-.001||pos[a]>local[a]+1.001)return {};
        if(n[a]&&std::abs(pos[a]-(local[a]+(n[a]>0?1:0)))>.001)return {};
    }}
    return {k.x*16+local[0],k.y*16+local[1],k.z*16+local[2],kind};
}
}
void RenderStore::invalidate_native_views(){nativeViews.clear();instanceReceiptValid=false;instanceReceipts.clear();}
std::vector<NativeCube> RenderStore::nearby_instances(double x,double y,double z)const{
    std::set<NativeCube>unique;
    if(!cubeConnected||!cubeCleared)return {};
    for(const auto&[k,m]:sections){
        if(std::abs(k.x*16+8.-x)>24||std::abs(k.y*16+8.-y)>24||std::abs(k.z*16+8.-z)>24)continue;
        for(const auto&p:m.nativeTriangles)if(p.kind){const double dx=p.x+.5-x,dy=p.y+.5-y,dz=p.z+.5-z;if(dx*dx+dy*dy+dz*dz<=256)unique.insert(p);}
    }
    std::vector<NativeCube>rows(unique.begin(),unique.end());auto distance=[&](auto p){double dx=p.x+.5-x,dy=p.y+.5-y,dz=p.z+.5-z;return dx*dx+dy*dy+dz*dz;};
    std::sort(rows.begin(),rows.end(),[&](auto a,auto b){auto da=distance(a),db=distance(b);return da==db?a<b:da<db;});if(rows.size()>1280)rows.resize(1280);return rows;
}
bool RenderStore::accept_instances(const std::vector<NativeCube>&rows,std::uint64_t now){
    if(rows.size()>1280||!cubeConnected||!cubeCleared)return false;
    std::set<NativeCube>ready(rows.begin(),rows.end());if(ready.size()!=rows.size())return false;
    for(auto p:rows)if(!p.kind||p.kind>16)return false;
    const std::vector<NativeCube>sorted(ready.begin(),ready.end());
    if(instanceReceiptValid&&instanceReceiptRevision==instanceRevision&&instanceReceipts==sorted){for(auto&[k,v]:nativeViews)v.expires=now+500;return true;}
    for(const auto&[k,m]:sections){
        std::vector<std::uint8_t>mask((m.nativeTriangles.size()+7)/8);bool any=false;
        for(std::size_t i=0;i<m.nativeTriangles.size();i++)if(m.nativeTriangles[i].kind&&ready.contains(m.nativeTriangles[i])){mask[i/8]|=1u<<(i%8);any=true;}
        auto old=nativeViews.find(k);
        if(old!=nativeViews.end()&&(!any||old->second.mask!=mask))nativeViews.erase(old);
        if(any&&!accept_native_section(k,m.nativeRevision,mask,now))return false;
    }instanceReceipts=sorted;instanceReceiptRevision=instanceRevision;instanceReceiptValid=true;return true;
}
const Mesh& RenderStore::section_overlay(SectionKey key,const Mesh& original,std::uint64_t now) const {
    auto it=nativeViews.find(key);if(it==nativeViews.end()||it->second.sourceRevision!=original.nativeRevision||now>=it->second.expires)return original;
    return it->second.remainder;
}
bool RenderStore::accept_native_section(SectionKey key,std::uint64_t sourceRevision,std::span<const std::uint8_t> mask,std::uint64_t now){
    auto it=sections.find(key);if(it==sections.end()||it->second.nativeRevision!=sourceRevision)return false;
    const auto&source=it->second;const auto triangles=source.vertices.size()/3;
    if(mask.size()!=(triangles+7)/8||mask.empty()||(triangles%8&&(mask.back()>>(triangles%8))))return false;
    bool any=false;
    for(std::size_t i=0;i<triangles;i++)if(mask[i/8]&(1u<<(i%8))){any=true;for(int j=0;j<3;j++)if(source.vertices[i*3+j].flags&2)return false;}
    if(!any)return false;
    auto found=nativeViews.find(key);
    if(found!=nativeViews.end()&&found->second.sourceRevision==sourceRevision){if(!std::equal(mask.begin(),mask.end(),found->second.mask.begin(),found->second.mask.end()))return false;found->second.expires=now+500;return true;}
    NativeSectionView view;view.mask.assign(mask.begin(),mask.end());view.sourceRevision=sourceRevision;view.expires=now+500;
    std::copy(std::begin(source.origin),std::end(source.origin),std::begin(view.remainder.origin));view.remainder.revision=++revision;
    view.depth.origin[0]=source.origin[0];view.depth.origin[1]=source.origin[1];view.depth.origin[2]=source.origin[2];view.depth.revision=view.remainder.revision;
    for(std::size_t i=0;i<triangles;i++){auto&dest=(mask[i/8]&(1u<<(i%8)))?view.depth.vertices:view.remainder.vertices;dest.insert(dest.end(),source.vertices.begin()+i*3,source.vertices.begin()+i*3+3);}
    nativeViews[key]=std::move(view);return true;
}
void RenderStore::clear() {
    for(const auto& [k,bits]:solids) for(int i=0;i<4096;i++) if(bits[i>>3]&(1u<<(i&7)))
        solidChanges.push_back({k.x*16+(i&15),k.y*16+(i>>8),k.z*16+((i>>4)&15),false});
    sections.clear();sectionAtlasRects.clear();invalidate_native_views();++instanceRevision;solids.clear(); fullCubes.clear();++cubeRevision;
    avatar={}; scene={}; worldEntities={}; ++revision;
}
void RenderStore::set_cube_context(std::uint32_t world,std::uint32_t epoch,std::uint32_t pid,std::uint64_t generation,bool connected) {
    if(world!=cubeWorld||epoch!=cubeEpoch||pid!=cubePid||generation!=cubeGeneration||connected!=cubeConnected) {
        fullCubes.clear();invalidate_native_views();++cubeRevision;cubeCleared=false;
    }
    cubeWorld=world;cubeEpoch=epoch;cubePid=pid;cubeGeneration=generation;cubeConnected=connected;
}
CubeSnapshot RenderStore::nearby_cubes(double x,double y,double z,double radius,std::size_t limit) const {
    CubeSnapshot result;
    if(!cubeConnected||!cubeCleared||!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(z)
        ||std::abs(x)>30'000'000||std::abs(y)>30'000'000||std::abs(z)>30'000'000
        ||!std::isfinite(radius)||radius<=0||radius>16||limit==0||limit>1280)return result;
    struct Candidate {double distance;CubePosition p;};std::vector<Candidate> candidates;
    for(const auto& [k,bits]:fullCubes) {
        const double sx=double(k.x)*16,sy=double(k.y)*16,sz=double(k.z)*16;
        if(sx>x+radius||sx+16<x-radius||sy>y+radius||sy+16<y-radius||sz>z+radius||sz+16<z-radius)continue;
        for(int i=0;i<4096;i++)if(bits[i>>3]&(1u<<(i&7))) {
            CubePosition p{k.x*16+(i&15),k.y*16+(i>>8),k.z*16+((i>>4)&15)};
            const double dx=p.x+.5-x,dy=p.y+.5-y,dz=p.z+.5-z,d=dx*dx+dy*dy+dz*dz;
            if(d<=radius*radius)candidates.push_back({d,p});
        }
    }
    result.total=candidates.size();
    const auto count=std::min(limit,candidates.size());
    std::partial_sort(candidates.begin(),candidates.begin()+count,candidates.end(),[](const Candidate&a,const Candidate&b){
        return std::tie(a.distance,a.p.x,a.p.y,a.p.z)<std::tie(b.distance,b.p.x,b.p.y,b.p.z);
    });
    for(std::size_t i=0;i<count;i++)result.rows.push_back(candidates[i].p);
    return result;
}
bool RenderStore::consume(std::uint32_t type,std::span<const std::uint8_t> p) {
    const auto rev=++revision;
    bool ok=false;
    switch(type) {
    case proto::kRenClearAll: if(p.empty()){clear();cubeCleared=cubeConnected;ok=true;} break;
    case proto::kRenAtlas: {
        proto::RenAtlas h; ok=read(p,h)&&texture(atlas,p,sizeof(h),h.width,h.height,rev);
        if(ok){animatedAtlasRects.clear();invalidate_native_views();++instanceRevision;for(auto&[key,m]:sections){m.nativeRevision=rev;sectionAtlasRects[key]=atlas_rects(m,atlas);}}break;
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
        atlas.revision=rev;
        const AtlasRect changed{h.x,h.y,h.width,h.height};
        // First discovery invalidates captures that might include this sprite. Later animation
        // frames do not rebuild static geometry; the worker excludes every known animated rect.
        const bool discovered=std::find(animatedAtlasRects.begin(),animatedAtlasRects.end(),changed)==animatedAtlasRects.end();
        if(discovered){++instanceRevision;if(animatedAtlasRects.size()<512)animatedAtlasRects.push_back(changed);else animatedAtlasRects={{0,0,atlas.width,atlas.height}};
            for(auto&[key,m]:sections)for(const auto&r:sectionAtlasRects[key])if(overlaps(r,changed)){m.nativeRevision=rev;nativeViews.erase(key);break;}}
        ok=true; break;
    }
    case proto::kRenSection: {
        proto::RenSection h; if(!read(p,h)) break;
        SectionKey k{h.sx,h.sy,h.sz};
        ++instanceRevision;
        if(std::abs(std::int64_t(h.sx))>1'000'000||std::abs(std::int64_t(h.sy))>1'000'000||std::abs(std::int64_t(h.sz))>1'000'000) break;
        if(h.vertexCount==0&&p.size()==sizeof(h)){sections.erase(k);sectionAtlasRects.erase(k);nativeViews.erase(k);ok=true;break;}
        if(!sections.contains(k)&&sections.size()>=kMaxSections) break;
        Mesh m; ok=mesh(m,p,sizeof(h),0,h.vertexCount,rev); if(ok){m.origin[0]=double(h.sx)*16;m.origin[1]=double(h.sy)*16;m.origin[2]=double(h.sz)*16;
            m.nativeTriangles.reserve(m.vertices.size()/3);for(std::size_t i=0;i<m.vertices.size();i+=3)m.nativeTriangles.push_back(tagged_cube(m.vertices.data()+i,k));
            sectionAtlasRects[k]=atlas_rects(m,atlas);nativeViews.erase(k);sections[k]=std::move(m);} break;
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
    case proto::kRenFullCubes: {
        proto::RenFullCubes h;
        if(!read(p,h)||h.reserved||h.count>4096||p.size()!=sizeof(h)+(h.count?512:0)
            ||std::abs(std::int64_t(h.sx))>1'000'000||std::abs(std::int64_t(h.sy))>1'000'000||std::abs(std::int64_t(h.sz))>1'000'000)break;
        std::array<std::uint8_t,512> bits{};if(h.count)std::memcpy(bits.data(),p.data()+sizeof(h),512);
        std::uint32_t count=0;for(auto b:bits)for(int i=0;i<8;i++)count+=(b>>i)&1u;
        if(count!=h.count)break;
        if(!cubeConnected||!cubeCleared||h.worldId!=cubeWorld||h.epoch!=cubeEpoch||h.mcPid!=cubePid) {
            ++staleCubeMessages;ok=true;break;
        }
        const SectionKey key{h.sx,h.sy,h.sz};
        if(h.count&&!fullCubes.contains(key)&&fullCubes.size()>=kMaxSections)break;
        if(h.count)fullCubes[key]=bits;else fullCubes.erase(key);++cubeRevision;ok=true;break;
    }
    // Native terrain destruction intentionally unsupported: original terrain is protected.
    case proto::kRenDug: case proto::kRenRagdoll: case proto::kRenLights: ok=true;break;
    default: break;
    }
    if(!ok)++invalidMessages;
    return ok;
}
}
