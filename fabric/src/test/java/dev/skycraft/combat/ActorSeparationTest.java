package dev.skycraft.combat;
import static org.junit.jupiter.api.Assertions.*;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import org.junit.jupiter.api.Test;
class ActorSeparationTest {
    @Test void hostWalkingIntoPlayerSeparatesHorizontallyAndIsBounded(){
        var player=new AABB(-.3,0,-.3,.3,1.8,.3);
        var approaching=new AABB(.2,0,-.5,1,2,.5);
        var d=ActorSeparation.displacement(player,approaching);
        assertTrue(d.x<-.1&&d.x>-.103);assertEquals(0,d.y);assertEquals(0,d.z);
        assertFalse(player.move(d).intersects(approaching));
        assertEquals(.2,ActorSeparation.displacement(player,new AABB(-5,-1,-5,5,4,5)).length(),1e-8);
    }
    @Test void differentHeightAndNonOverlappingActorsDoNotPush(){
        var p=new AABB(-.3,0,-.3,.3,1.8,.3);
        assertEquals(Vec3.ZERO,ActorSeparation.displacement(p,new AABB(-1,2,-1,1,3,1)));
        assertEquals(Vec3.ZERO,ActorSeparation.displacement(p,new AABB(2,0,2,3,2,3)));
    }
}
