package dev.skycraft.combat;

import org.junit.jupiter.api.Test;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

class NativeMobDamageTest {
    static NativeAttack capsule(double ax,double ay,double az,double bx,double by,double bz,double r){
        double[] g=new double[24];g[0]=ax;g[1]=ay;g[2]=az;g[3]=bx;g[4]=by;g[5]=bz;g[6]=r;
        System.arraycopy(g,0,g,7,7);return attack(1000,1,7,0,0,1,g);
    }
    static NativeAttack attack(long time,int session,int hit,int flags,float repeat,int limit,double[] g){
        return new NativeAttack(time,session,3,4,5,6,hit,1,flags,4,repeat,limit,0,0,0,g);
    }
    @Test void actualCapsuleRejectsBroadBoxCorner(){
        var a=capsule(0,0,0,4,0,4,.1);
        assertTrue(AttackGeometry.intersects(a,new AttackGeometry.Box(1.9,-.05,1.9,2.1,.05,2.1)));
        assertFalse(AttackGeometry.intersects(a,new AttackGeometry.Box(0,-.05,3.8,.1,.05,4)));
        assertFalse(AttackGeometry.intersects(a,new AttackGeometry.Box(2,1,2,3,2,3)));
    }
    @Test void continuousMotionHitsBetweenBothFrames(){
        var a=capsule(4,0,0,4,1,0,.1);double[] g=a.geometry().clone();g[7]=-4;g[10]=-4;
        var moving=attack(1000,1,7,0,0,1,g);
        assertTrue(AttackGeometry.intersects(moving,new AttackGeometry.Box(-.1,.4,-.1,.1,.6,.1)));
        assertFalse(AttackGeometry.intersects(moving,new AttackGeometry.Box(-.1,.4,1,.1,.6,2)));
    }
    @Test void sphereGrazingAndEmbeddedSegment(){
        var a=capsule(0,0,0,0,0,0,1);
        assertTrue(AttackGeometry.intersects(a,new AttackGeometry.Box(.99,-.1,-.1,1.1,.1,.1)));
        assertFalse(AttackGeometry.intersects(a,new AttackGeometry.Box(.8,.8,.8,1,1,1)));
        assertEquals(0,AttackGeometry.segmentDistanceSquared(new double[]{0,0,0},new double[]{0,0,0},new AttackGeometry.Box(-1,-1,-1,1,1,1)));
    }
    @Test void obbUsesAllSeparatingAxes(){
        double v=Math.sqrt(.5);double[] g={0,0,0,v,0,v,0,1,0,-v,0,v,3,.2,.1,0,0,0,0,0,0,0,0,0};
        var a=new NativeAttack(1000,1,2,3,4,5,6,2,0,4,0,1,0,0,0,g);
        assertTrue(a.valid(1050));
        assertTrue(AttackGeometry.intersects(a,new AttackGeometry.Box(1,-.1,1,1.2,.1,1.2)));
        assertFalse(AttackGeometry.intersects(a,new AttackGeometry.Box(-2,-.1,2,-1.8,.1,2.2)));
    }
    @Test void perVictimDedupAndDifferentSwing(){
        var l=new AttackLedger();var a=capsule(0,0,0,0,1,0,1);var one=UUID.randomUUID();var two=UUID.randomUUID();
        l.observe(a,1000);assertTrue(l.admit(a,one));assertFalse(l.admit(a,one));assertTrue(l.admit(a,two));
        var next=attack(1100,1,8,0,0,1,a.geometry());l.observe(next,1100);assertTrue(l.admit(next,one));
        var session=attack(1100,2,7,0,0,1,a.geometry());l.observe(session,1100);assertTrue(l.admit(session,one));
    }
    @Test void nativeMultiHitIntervalAndLimit(){
        var l=new AttackLedger();var who=UUID.randomUUID();var g=capsule(0,0,0,0,1,0,1).geometry();
        for(long t:new long[]{1000,1100,1200,1500,2000}){
            var a=attack(t,1,7,1,.5f,2,g);l.observe(a,t);assertEquals(t==1000||t==1500,l.admit(a,who));
        }
    }
    @Test void staleFutureMalformedAndHugeSweepsRejected(){
        var a=capsule(0,0,0,0,1,0,1);assertTrue(a.valid(1100));assertFalse(a.valid(1251));assertFalse(a.valid(999));
        var g=a.geometry().clone();g[0]=Double.NaN;assertFalse(attack(1000,1,7,0,0,1,g).valid(1000));
        g=a.geometry().clone();g[0]=10000;assertFalse(attack(1000,1,7,0,0,1,g).valid(1000));
        assertFalse(attack(1000,0,7,0,0,1,a.geometry()).valid(1000));
    }
}
