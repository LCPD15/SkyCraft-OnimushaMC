#include "CollisionPacking.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace omc {
namespace {
int region_of(int n){const auto wide=std::int64_t(n);return int(wide>=0?wide/8:-((-wide+7)/8));}
void sub(const float* a,const float* b,float* v){for(int i=0;i<3;i++)v[i]=a[i]-b[i];}
void cross(const float* a,const float* b,float* v){v[0]=a[1]*b[2]-a[2]*b[1];v[1]=a[2]*b[0]-a[0]*b[2];v[2]=a[0]*b[1]-a[1]*b[0];}
float dot(const float* a,const float* b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
bool axis(const float* a,const float* b,const float* c,const float* n,float h){const float x=dot(a,n),y=dot(b,n),z=dot(c,n),r=h*(std::abs(n[0])+std::abs(n[1])+std::abs(n[2]));return std::min({x,y,z})<=r&&std::max({x,y,z})>=-r;}
// Same triangle-box separating-axis test used by upstream SkyCraft collision packing.
bool overlaps(const proto::ColTri& t,const double* center,const float* normal){
    constexpr float h=0.06255f;float a[3],b[3],c[3];
    for(int i=0;i<3;i++){a[i]=float(double(t.v[i])-center[i]);b[i]=float(double(t.v[i+3])-center[i]);c[i]=float(double(t.v[i+6])-center[i]);}
    for(int i=0;i<3;i++)if(std::min({a[i],b[i],c[i]})>h||std::max({a[i],b[i],c[i]})<-h)return false;
    if(std::abs(dot(normal,a))>h*(std::abs(normal[0])+std::abs(normal[1])+std::abs(normal[2])))return false;
    float edges[3][3];sub(b,a,edges[0]);sub(c,b,edges[1]);sub(a,c,edges[2]);constexpr float units[3][3]={{1,0,0},{0,1,0},{0,0,1}};
    for(auto& e:edges)for(const auto& unit:units){float n[3];cross(e,unit,n);if(!axis(a,b,c,n,h))return false;}return true;
}
template<class T> CollisionPacket packet(std::uint32_t type,const proto::ColRegion& h,std::span<const T> rows){CollisionPacket p;p.type=type;p.payload.resize(sizeof(h)+rows.size_bytes());std::memcpy(p.payload.data(),&h,sizeof(h));if(!rows.empty())std::memcpy(p.payload.data()+sizeof(h),rows.data(),rows.size_bytes());return p;}
}
bool pack_collision(const proto::ColRegion& bounds,std::span<const proto::ColTri> triangles,std::vector<CollisionPacket>& out,std::string& error){
    out.clear();error.clear();const int minimum[3]={bounds.minX,bounds.minY,bounds.minZ},maximum[3]={bounds.maxX,bounds.maxY,bounds.maxZ};
    for(int k=0;k<3;k++)if(minimum[k]>maximum[k]||std::abs(std::int64_t(minimum[k]))>kMaxCollisionCoordinate||std::abs(std::int64_t(maximum[k]))>kMaxCollisionCoordinate){error="Collision bounds must be ordered and within 30 million blocks";return false;}
    const int lo[3]={region_of(bounds.minX),region_of(bounds.minY),region_of(bounds.minZ)},hi[3]={region_of(bounds.maxX),region_of(bounds.maxY),region_of(bounds.maxZ)};
    for(int k=0;k<3;k++)if(hi[k]<lo[k]||hi[k]-lo[k]>16){error="Collision region bounds exceed 136 blocks";return false;}
    const auto regionCount=std::uint64_t(hi[0]-lo[0]+1)*(hi[1]-lo[1]+1)*(hi[2]-lo[2]+1);if(regionCount>1024||triangles.size()>100000){error="Too many collision regions/triangles";return false;}
    std::map<SectionKey,std::vector<proto::ColTri>> groups;
    for(int x=lo[0];x<=hi[0];x++)for(int y=lo[1];y<=hi[1];y++)for(int z=lo[2];z<=hi[2];z++)groups[{x,y,z}];
    std::uint64_t refs=0,samples=0;
    for(const auto& t:triangles){int tlo[3],thi[3];bool valid=true;for(int k=0;k<9;k++)valid=valid&&std::isfinite(t.v[k])&&std::abs(t.v[k])<30'000'000;if(!valid){error="Invalid collision vertex";return false;}
        for(int k=0;k<3;k++){const double mn=std::min({t.v[k],t.v[k+3],t.v[k+6]}),mx=std::max({t.v[k],t.v[k+3],t.v[k+6]});tlo[k]=std::max(lo[k],int(std::floor((mn-0.001)/8)));thi[k]=std::min(hi[k],int(std::floor((mx+0.001)/8)));}
        for(int x=tlo[0];x<=thi[0];x++)for(int y=tlo[1];y<=thi[1];y++)for(int z=tlo[2];z<=thi[2];z++){if(++refs>500000){error="Collision triangle region fanout exceeds limit";return false;}groups[{x,y,z}].push_back(t);}
    }
    for(const auto& [key,tris]:groups){
        proto::ColRegion h{key.x*8,key.y*8,key.z*8,key.x*8+7,key.y*8+7,key.z*8+7,bounds.epoch,std::uint32_t(tris.size())};out.push_back(packet(proto::kColTris,h,std::span<const proto::ColTri>(tris)));
        std::array<proto::ColBlock,512> blocks{};const int base[3]={h.minX*8,h.minY*8,h.minZ*8};
        for(const auto& t:tris){if(t.flags&proto::kTriGhost)continue;int mn[3],mx[3];float e1[3],e2[3],n[3];sub(t.v+3,t.v,e1);sub(t.v+6,t.v,e2);cross(e1,e2,n);
            for(int k=0;k<3;k++){mn[k]=std::max(base[k],int(std::floor(double(std::min({t.v[k],t.v[k+3],t.v[k+6]}))*8-0.001)));mx[k]=std::min(base[k]+63,int(std::floor(double(std::max({t.v[k],t.v[k+3],t.v[k+6]}))*8+0.001)));}
            // A triangle is a surface, not its entire 3-D bounding volume. Rasterize
            // two axes and conservatively bound the third by its supporting plane.
            // Choosing the largest normal avoids division by a small component.
            // The original SAT still decides every bit; this only rejects empty work.
            int d=0;for(int k=1;k<3;k++)if(std::abs(n[k])>std::abs(n[d]))d=k;
            const int u=(d+1)%3,v=(d+2)%3;
            const bool planar=std::isfinite(n[d])&&std::abs(n[d])>1e-20f;
            const double reach=planar?0.06255*(std::abs(double(n[0]))+std::abs(double(n[1]))+std::abs(double(n[2])))/std::abs(double(n[d])):0;
            int cell[3];
            for(cell[u]=mn[u];cell[u]<=mx[u];cell[u]++)for(cell[v]=mn[v];cell[v]<=mx[v];cell[v]++){
                int first=mn[d],last=mx[d];
                if(planar){
                    const double cu=(double(cell[u])+0.5)/8,cv=(double(cell[v])+0.5)/8;
                    const double plane=double(t.v[d])-(double(n[u])*(cu-t.v[u])+double(n[v])*(cv-t.v[v]))/n[d];
                    // One extra subcell protects float SAT rounding, including far
                    // MC world tiles. Bounds are clamped before conversion to int.
                    const double low=std::max(double(first),std::floor((plane-reach)*8-0.5)-1);
                    const double high=std::min(double(last),std::ceil((plane+reach)*8-0.5)+1);
                    if(low>high)continue;first=int(low);last=int(high);
                }
                for(cell[d]=first;cell[d]<=last;cell[d]++){
                    if(++samples>12'000'000){error="Collision voxelization exceeds bounded work budget";return false;}
                    const double center[3]={(double(cell[0])+0.5)/8,(double(cell[1])+0.5)/8,(double(cell[2])+0.5)/8};if(!overlaps(t,center,n))continue;
                    const int vx=cell[0]-base[0],vy=cell[1]-base[1],vz=cell[2]-base[2];auto& b=blocks[(vx>>3)+8*((vz>>3)+8*(vy>>3))];b.x=h.minX+(vx>>3);b.y=h.minY+(vy>>3);b.z=h.minZ+(vz>>3);b.bits[vy&7]|=1ull<<((vz&7)*8+(vx&7));
                }
            }
        }
        std::vector<proto::ColBlock> packed;for(const auto& b:blocks)if(std::any_of(std::begin(b.bits),std::end(b.bits),[](auto v){return v!=0;}))packed.push_back(b);
        h.count=std::uint32_t(packed.size());out.push_back(packet(proto::kColRegion,h,std::span<const proto::ColBlock>(packed)));
    }return true;
}
}
