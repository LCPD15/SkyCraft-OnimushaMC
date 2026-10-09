#pragma once
#include "RenderStore.hpp"
#include <cstring>
namespace omc::tests {
template<class Check>void pose_frame_tests(Check check){
 RenderStore s;s.set_cube_context(4,7,12,1,true);s.consume(proto::kRenClearAll,{});
 auto packet=[](unsigned frame,double x){
  proto::RenPoseFrame h{};h.version=1;h.worldId=4;h.epoch=7;h.mcPid=12;
  h.avatarBytes=8;h.sceneBytes=h.handsBytes=32;h.state.flags=proto::kMcInWorld;
  h.state.frameCounter=frame;h.state.x=x;h.state.eyeX=x;h.state.fovDeg=70;
  std::vector<std::uint8_t>p(sizeof(h)+72);std::memcpy(p.data(),&h,sizeof(h));
  proto::RenScene a{};a.originX=x+1;
  std::memcpy(p.data()+sizeof(h)+8,&a,sizeof(a));
  a.originX=x+2;std::memcpy(p.data()+sizeof(h)+40,&a,sizeof(a));return p;
 };
 auto a=packet(11,100);check(s.consume(proto::kRenPoseFrame,a),"atomic pose packet accepted");
 check(s.renderPose.frameCounter==0&&s.pendingPose.state.frameCounter==11,"incoming render frame cannot move game-thread presentation");
 check(s.latch_pose()&&s.renderPose.x==100&&s.scene.origin[0]==101&&s.hands.origin[0]==102,"camera and all dynamic origins latch together");
 for(unsigned i=12;i<19;i++)check(s.consume(proto::kRenPoseFrame,packet(i,100+i)),"faster MC sender stores latest complete frame");
 check(s.renderPose.frameCounter==11&&s.hands.origin[0]==102,"Present cannot advance hands while RE camera still uses previous frame");
 check(s.latch_pose()&&s.renderPose.frameCounter==18&&s.hands.origin[0]==120,"slow host drops intermediate complete frames atomically");
 check(!s.latch_pose()&&s.renderPose.frameCounter==18,"fast host repeats a whole frame instead of mixing poses");
 std::vector<std::uint8_t> legacy(32);proto::RenScene legacyHeader{};legacyHeader.originX=999;
 std::memcpy(legacy.data(),&legacyHeader,sizeof(legacyHeader));
 check(s.consume(proto::kRenHands,legacy)&&s.hands.origin[0]==120,"legacy hand packet cannot split an atomic presentation");
 check(s.consume(proto::kRenPoseFrame,a)&&!s.pendingPose.ready,"out-of-order pose never rewinds presentation");
 auto bad=packet(19,200);bad.pop_back();check(!s.consume(proto::kRenPoseFrame,bad)&&!s.pendingPose.ready,"truncated last stream cannot commit partial frame");
 auto wrong=packet(20,200);reinterpret_cast<proto::RenPoseFrame*>(wrong.data())->epoch=8;
 check(s.consume(proto::kRenPoseFrame,wrong)&&!s.pendingPose.ready,"wrong scene pose discarded");
 s.set_cube_context(4,8,12,2,true);check(!s.poseFrames&&!s.renderPose.frameCounter&&!s.pendingPose.ready,"session change clears latched and pending camera/geometry");
}
}
