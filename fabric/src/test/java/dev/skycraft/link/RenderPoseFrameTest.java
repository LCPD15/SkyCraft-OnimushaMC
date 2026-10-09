package dev.skycraft.link;
import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
class RenderPoseFrameTest {
 @Test void wireStateIsOneRenderSnapshot(){
  var s=new SkyLink.McState();s.frameCounter=91;s.x=12345.625;s.eyeZ=-20.25;s.cameraMode=2;s.cameraDistance=3.7f;s.fov=74;
  var p=RenderPoseFrame.header(s,4,7,12,8,32,32);
  assertEquals(232,p.remaining());assertEquals(1,p.getInt(0));assertEquals(7,p.getInt(8));
  assertEquals(91,p.getLong(32+56));assertEquals(12345.625,p.getDouble(32+8));
  assertEquals(-20.25,p.getDouble(32+96));assertEquals(2,p.getInt(32+192));assertEquals(3.7f,p.getFloat(32+196));
  s.x=999;assertEquals(12345.625,p.getDouble(40));
 }
 @Test void cannotEmitIncompleteGeometry(){
  assertThrows(IllegalArgumentException.class,()->RenderPoseFrame.header(new SkyLink.McState(),1,2,3,8,0,32));
 }
 @Test void startupCameraMustBeInitialized(){
  var s=new SkyLink.McState();s.flags=Proto.MC_IN_WORLD;s.frameCounter=1;
  assertFalse(RenderPoseFrame.ready(s));s.fov=70;assertTrue(RenderPoseFrame.ready(s));
  s.eyeX=Double.NaN;assertFalse(RenderPoseFrame.ready(s));
 }
}
