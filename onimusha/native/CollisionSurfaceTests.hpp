#pragma once
#include "CollisionPacking.hpp"
#include <cmath>
#include <cstring>
#include <random>

namespace omc::tests {
// Brute-force SAT oracle: visit every subvoxel of a whole cell, without any
// dominant-axis/plane range pruning. Dyadic vertices keep boundary cases exact.
struct V {double x,y,z;V operator-(V b)const{return {x-b.x,y-b.y,z-b.z};}};
inline V cross_ref(V a,V b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double dot_ref(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline bool box_triangle_ref(const proto::ColTri& t,V p){
    V a{t.v[0]-p.x,t.v[1]-p.y,t.v[2]-p.z},b{t.v[3]-p.x,t.v[4]-p.y,t.v[5]-p.z},c{t.v[6]-p.x,t.v[7]-p.y,t.v[8]-p.z};
    V axes[13]={{1,0,0},{0,1,0},{0,0,1},cross_ref(b-a,c-a)};
    V edges[3]={b-a,c-b,a-c};int at=4;
    for(auto e:edges)for(int k=0;k<3;k++)axes[at++]=cross_ref(e,axes[k]);
    for(auto n:axes){const double r=double(0.06255f)*(std::abs(n.x)+std::abs(n.y)+std::abs(n.z));
        const double x=dot_ref(a,n),y=dot_ref(b,n),z=dot_ref(c,n);
        if(std::min({x,y,z})>r||std::max({x,y,z})<-r)return false;}
    return true;
}
template<class Check> void collision_surface_tests(Check check){
    std::mt19937 rng(20261007);bool equal=true;
    for(int test=0;test<20;test++){
        const int ox=test%3==0?-8:test%3==1?57344:8388608,oy=-8,oz=192;
        proto::ColTri t{};
        for(int j=0;j<9;j++)t.v[j]=float((j%3==0?ox:j%3==1?oy:oz)+double(rng()%65)/8);
        if(test<3){ // Exact grid planes, including a floor on a region boundary.
            const int d=test;t.v[d]=t.v[d+3]=t.v[d+6]=float((d==0?ox:d==1?oy:oz)+(test?4:0));
        }
        if(test==3)for(int j=0;j<3;j++){t.v[j+3]=t.v[j];t.v[j+6]=t.v[j];}
        proto::ColRegion b{ox,oy,oz,ox+7,oy+7,oz+7,1,1};
        std::vector<CollisionPacket> packed;std::string error;
        if(!pack_collision(b,std::span(&t,1),packed,error)){equal=false;break;}
        std::vector<bool> actual(64*64*64);
        for(const auto& p:packed)if(p.type==proto::kColRegion){
            proto::ColRegion h;std::memcpy(&h,p.payload.data(),sizeof(h));
            for(std::size_t i=0;i<h.count;i++){
                proto::ColBlock block;std::memcpy(&block,p.payload.data()+sizeof(h)+i*sizeof(block),sizeof(block));
                for(int y=0;y<8;y++)for(int z=0;z<8;z++)for(int x=0;x<8;x++)if((block.bits[y]>> (z*8+x))&1)
                    actual[(block.x-ox)*8+x+64*((block.z-oz)*8+z+64*((block.y-oy)*8+y))]=true;
            }
        }
        for(int y=0;y<64;y++)for(int z=0;z<64;z++)for(int x=0;x<64;x++){
            const bool expected=box_triangle_ref(t,{ox+(x+.5)/8,oy+(y+.5)/8,oz+(z+.5)/8});
            if(actual[x+64*(z+64*y)]!=expected)equal=false;
        }
    }
    check(equal,"surface pruning matches brute-force SAT for every voxel: slopes, all axes, negative/far coordinates and degeneracy");
    proto::ColRegion b{57344,-16,184,57375,15,215,1,0};
    std::vector<proto::ColTri> slopes(20,{{57344,-16,184,57376,16,184,57344,16,216},0});
    std::vector<CollisionPacket> packed;std::string error;
    check(pack_collision(b,slopes,packed,error),"broad diagonal surfaces complete within the unchanged 12-million-work safety limit");
}
}
