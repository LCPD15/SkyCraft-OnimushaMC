package dev.skycraft.combat;

import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/** Bounded horizontal escape when a host-controlled actor moves into the player. */
public final class ActorSeparation {
    private ActorSeparation() {}
    public static Vec3 displacement(AABB player, AABB actor) {
        if (!player.intersects(actor)) return Vec3.ZERO;
        double[] escape={actor.minX-player.maxX-.002,actor.maxX-player.minX+.002,
            actor.minZ-player.maxZ-.002,actor.maxZ-player.minZ+.002};
        int axis=0;
        for(int i=1;i<4;i++) if(Math.abs(escape[i])<Math.abs(escape[axis])) axis=i;
        double amount=Math.clamp(escape[axis],-.2,.2);
        return axis<2 ? new Vec3(amount,0,0) : new Vec3(0,0,amount);
    }
}
