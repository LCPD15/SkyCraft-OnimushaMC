#pragma once
#include "RenderStore.hpp"
#include <cmath>
namespace omc::tests {
template<class Check>void dynamic_models_tests(Check check){
 RenderStore s;s.atlas={8,8,std::vector<std::uint8_t>(256,255),1};s.atlasBaseRevision=1;
 const proto::RenVertex quad[]={{1,2,3,0,0,0xffffffff,0xF0F,0x79},{1,2,5,1,0,0xffffffff,0xF0F,0x79},{1,5,5,1,1,0xffffffff,0xF0F,0x79},{1,2,3,0,0,0xffffffff,0xF0F,0x79},{1,5,5,1,1,0xffffffff,0xF0F,0x79},{1,5,3,0,1,0xffffffff,0xF0F,0x79}};
 s.scene.vertices.assign(std::begin(quad),std::end(quad));s.scene.batches={{0,0,6,0}};s.scene.revision=10;s.prepare_dynamic();
 check(s.nativeScene.faces.size()==1,"animated rectangle becomes one reusable native resource");
 if(s.nativeScene.faces.empty())return;
 auto f=s.nativeScene.faces[0];const auto id=f.model;
 check(f.scale[0]==2&&f.scale[1]==3&&std::abs(f.rotation[0]-.70710678f)<1e-5&&std::abs(f.rotation[2]+.70710678f)<1e-5,"face transform keeps dimensions and uses right-handed quaternion wxyz");
 for(auto&v:s.scene.vertices){v.x+=3;v.z+=5;}++s.scene.revision;s.prepare_dynamic();
 check(s.nativeScene.faces[0].model==id&&s.blockModels.size()==1,"animated movement reuses resource without converting each frame");
 check(s.accept_dynamic(false,{{0,id}},100),"ready posed face receipt accepted");s.partition_dynamic(s.scene,s.nativeScene,101);
 check(s.nativeScene.remainder.vertices.empty()&&s.nativeScene.depth.vertices.size()==6,"only acknowledged current appearance suppressed, depth retained");
 for(auto&v:s.scene.vertices){v.x+=.01f;}++s.scene.revision;s.prepare_dynamic();s.partition_dynamic(s.scene,s.nativeScene,102);
 check(s.nativeScene.remainder.vertices.empty(),"pose advance preserves appearance lease across present/game thread timing");
 s.partition_dynamic(s.scene,s.nativeScene,251);check(s.nativeScene.remainder.vertices.size()==6,"stalled pose updater restores MC within 150ms");
 for(auto&v:s.scene.vertices)v.color=0xff8080ff;++s.scene.revision;s.prepare_dynamic();
 check(s.nativeScene.faces[0].model!=id,"hurt flash/tint change cannot reuse old-color resource receipt");s.partition_dynamic(s.scene,s.nativeScene,103);
 check(s.nativeScene.remainder.vertices.size()==6,"changed appearance immediately falls back until newly ready");
 s.scene.vertices[2].x+=.2f;s.scene.vertices[4].x+=.2f;++s.scene.revision;s.prepare_dynamic();
 check(s.nativeScene.faces.empty(),"non-rigid/non-rectangular geometry remains Minecraft rendered");
 s.scene.vertices.assign(std::begin(quad),std::end(quad));for(auto&v:s.scene.vertices)v.flags|=2;++s.scene.revision;s.prepare_dynamic();
 check(s.nativeScene.faces.empty(),"translucent particle/cloth layer is not silently made opaque");
 s.hands.vertices.assign(std::begin(quad),std::end(quad));s.hands.batches={{0,0,6,0}};s.hands.revision=90;s.prepare_dynamic();
 auto handId=s.nativeHands.faces[0].model;check(!s.hands_ready(100),"unloaded first person hands keep vanilla HUD rendering");
 s.accept_dynamic(2,{{0,handId}},100);check(s.hands_ready(101)&&!s.hands_ready(251),"complete hand receipt controls bounded HUD takeover");
 s.accept_dynamic(2,{},103);check(!s.hands_ready(104),"partial/failed hand loading cannot hide original HUD hands");
 s.release_dynamic();check(s.nativeScene.receipt.empty()&&s.nativeAvatar.faces.empty()&&s.nativeHands.faces.empty(),"takeover/scene exit releases animated draw ownership");
}
}
