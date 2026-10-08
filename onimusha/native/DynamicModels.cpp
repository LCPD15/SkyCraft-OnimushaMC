#include "RenderStore.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
namespace omc {
namespace {
struct V {float x,y,z;V operator-(V b)const{return{x-b.x,y-b.y,z-b.z};}V operator+(V b)const{return{x+b.x,y+b.y,z+b.z};}V operator*(float b)const{return{x*b,y*b,z*b};}};
V point(const proto::RenVertex&p){return{p.x,p.y,p.z};}
float dot(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
V cross(V a,V b){return{a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
float length(V a){return std::sqrt(dot(a,a));}
bool same(const proto::RenVertex&a,const proto::RenVertex&b){return std::memcmp(&a,&b,sizeof(a))==0;}
void quaternion(V x,V y,V z,float*q){
 const float trace=x.x+y.y+z.z;
 if(trace>0){const float s=std::sqrt(trace+1)*2;q[0]=s/4;q[1]=(y.z-z.y)/s;q[2]=(z.x-x.z)/s;q[3]=(x.y-y.x)/s;}
 else if(x.x>y.y&&x.x>z.z){const float s=std::sqrt(1+x.x-y.y-z.z)*2;q[0]=(y.z-z.y)/s;q[1]=s/4;q[2]=(y.x+x.y)/s;q[3]=(z.x+x.z)/s;}
 else if(y.y>z.z){const float s=std::sqrt(1+y.y-x.x-z.z)*2;q[0]=(z.x-x.z)/s;q[1]=(y.x+x.y)/s;q[2]=s/4;q[3]=(z.y+y.z)/s;}
 else{const float s=std::sqrt(1+z.z-x.x-y.y)*2;q[0]=(x.y-y.x)/s;q[1]=(z.x+x.z)/s;q[2]=(z.y+y.z)/s;q[3]=s/4;}
}
void prepare(RenderStore&s,const Mesh&m,DynamicNativeView&v){
 if(v.sourceRevision==m.revision)return;
 auto previous=std::move(v.faces);v.faces.clear();v.sourceRevision=m.revision;
 // Entity exporter emits quads as 0,1,2,0,2,3. Capture each rectangle once,
 // then update only its position/rotation/scale as Minecraft animates it.
 for(const auto&b:m.batches){
  if(b.flags&1)continue;
  for(unsigned first=b.first;first+6<=b.first+b.count;first+=6){
   if(v.faces.size()>=512)break;
   const auto*p=m.vertices.data()+first;
   if(!same(p[0],p[3])||!same(p[2],p[4]))continue;
   bool eligible=true;for(int i=0;i<6;i++)if((p[i].flags&0x72)!=0x70||(p[i].color>>24)!=255)eligible=false;
   if(!eligible)continue; // no particles, translucent layers or unlabelled triangles
   const V a=point(p[0]),ab=point(p[1])-a,ad=point(p[5])-a;
   float w=length(ab),h=length(ad);if(w<1e-5f||h<1e-5f||w>32||h>32)continue;
   V x=ab*(1/w),y=ad*(1/h);
   if(std::abs(dot(x,y))>1e-4f||length(point(p[2])-(a+ab+ad))>1e-4f*std::max(w,h))continue;
   V z=cross(x,y);Mesh model;
   const bool uniform=std::all_of(p,p+6,[&](const auto&vertex){return vertex.color==p[0].color;});
   const float uvxy[6][2]={{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}};
   for(int i=0;i<6;i++){auto vertex=p[i];vertex.x=uvxy[i][0];vertex.y=uvxy[i][1];vertex.z=0;vertex.light=0;vertex.flags=1;if(uniform)vertex.color=0xffffffff;model.vertices.push_back(vertex);}
   const auto id=s.register_model(std::move(model),b.texture);if(!id)continue;
   NativeFace face;face.first=first;face.model=id;face.whiteFlash=(p[0].flags&(1u<<21))!=0;face.tint=uniform?p[0].color:0xffffffff;face.position[0]=a.x;face.position[1]=a.y;face.position[2]=a.z;face.scale[0]=w;face.scale[1]=h;quaternion(x,y,z,face.rotation);v.faces.push_back(face);
  }
 }
 // A vertex offset is not an instance identity. Item changes can move every
 // body face in the flat list between the Lua tick and the render thread.
 // Reserve exact matches, then reuse remaining appearances one-to-one, just
 // as the Lua instance owner does. New geometry never inherits a receipt;
 // uniform hurt tint is an instance parameter and retains the same identity.
 std::map<std::pair<unsigned,unsigned>,std::size_t> exact;
 for(std::size_t i=0;i<previous.size();++i)exact[{previous[i].first,previous[i].model}]=i;
 std::vector<bool> used(previous.size());
 for(auto&f:v.faces){auto i=exact.find({f.first,f.model});if(i!=exact.end()){f.id=previous[i->second].id;used[i->second]=true;}}
 std::map<unsigned,std::vector<unsigned>> spare;
 for(std::size_t i=0;i<previous.size();++i)if(!used[i])spare[previous[i].model].push_back(previous[i].id);
 for(auto&f:v.faces)if(!f.id){auto&pool=spare[f.model];if(!pool.empty()){f.id=pool.back();pool.pop_back();}
  else if(s.nextDynamicFaceId<UINT32_MAX)f.id=++s.nextDynamicFaceId;}
 std::erase_if(v.faces,[](const auto&f){return !f.id;});
}
}
const Texture*RenderStore::model_texture(std::uint32_t model)const{
 auto it=modelTextures.find(model);if(it==modelTextures.end())return nullptr;
 if(!it->second)return &atlas;auto t=textures.find(it->second);return t==textures.end()?nullptr:&t->second;
}
void RenderStore::prepare_dynamic(){prepare(*this,avatar,nativeAvatar);prepare(*this,scene,nativeScene);prepare(*this,hands,nativeHands);}
bool RenderStore::accept_dynamic(unsigned stream,const std::map<std::uint32_t,std::uint32_t>&rows,std::uint64_t now,bool stableIds){
 if(rows.size()>512)return false;
 prepare_dynamic();auto&v=stream==2?nativeHands:stream==1?nativeAvatar:nativeScene;
 std::map<std::uint32_t,std::uint32_t> accepted;
 for(auto[key,model]:rows){
  auto it=std::find_if(v.faces.begin(),v.faces.end(),[&](auto f){return (stableIds?f.id:f.first)==key;});
  // A face may have disappeared since snapshot_native_dynamic. Omit only
  // that face; do not turn off all unchanged body parts for one render frame.
  if(it==v.faces.end()){if(stableIds&&key&&key<=nextDynamicFaceId)continue;return false;}
  if(it->model!=model)return false;accepted[it->id]=model;
 }
 if(v.receipt!=accepted){v.receipt=std::move(accepted);++v.receiptRevision;v.remainder.revision=0;}
 v.expires=now+150;return true;
}
void RenderStore::partition_dynamic(const Mesh&m,DynamicNativeView&v,std::uint64_t now){
 if(v.remainder.revision&&v.remainder.nativeRevision==m.revision&&now<v.expires)return;
 v.remainder={};v.depth={};v.remainder.nativeRevision=m.revision;
 v.remainder.revision=v.depth.revision=++revision;
 std::copy(std::begin(m.origin),std::end(m.origin),std::begin(v.remainder.origin));std::copy(std::begin(m.origin),std::end(m.origin),std::begin(v.depth.origin));
 std::map<unsigned,unsigned>matched;
 if(now<v.expires)for(auto f:v.faces){auto found=v.receipt.find(f.id);if(found!=v.receipt.end()&&found->second==f.model){matched[f.first]=f.model;matched[f.first+3]=f.model;}}
 for(auto b:m.batches){
  const auto rstart=unsigned(v.remainder.vertices.size()),dstart=unsigned(v.depth.vertices.size());
  for(unsigned i=b.first;i+3<=b.first+b.count;i+=3){auto&dest=matched.contains(i)?v.depth:v.remainder;dest.vertices.insert(dest.vertices.end(),m.vertices.begin()+i,m.vertices.begin()+i+3);}
  if(v.remainder.vertices.size()>rstart)v.remainder.batches.push_back({b.texture,rstart,unsigned(v.remainder.vertices.size()-rstart),b.flags});
  if(v.depth.vertices.size()>dstart)v.depth.batches.push_back({b.texture,dstart,unsigned(v.depth.vertices.size()-dstart),b.flags});
 }
}
bool RenderStore::hands_ready(std::uint64_t now)const{
 if(nativeHands.expires<=now||hands.vertices.empty()||hands.vertices.size()%6||nativeHands.faces.size()!=hands.vertices.size()/6)return false;
 for(auto f:nativeHands.faces){auto r=nativeHands.receipt.find(f.id);if(r==nativeHands.receipt.end()||r->second!=f.model)return false;}return true;
}
void RenderStore::release_dynamic(){nativeAvatar={};nativeScene={};nativeHands={};}
}
