package dev.skycraft.world;

import dev.skycraft.link.SkyLink;
import java.util.ArrayList;
import java.util.List;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/** Server-authoritative MC mobs use the same native triangles as the local player. */
public final class NativeMobPhysics {
	private NativeMobPhysics() {}

	public static boolean managed(Entity entity) {
		return entity instanceof Mob && !entity.noPhysics && SkyLink.segment() != null;
	}

	/** Unknown streamed ground is not empty space. Hold simulation until the whole body is covered. */
	public static boolean ready(Mob mob) {
		var host = new SkyLink.SkyState();
		if (!SkyLink.active() || !SkyLink.readSkyState(host) || host.loading()
			|| !SkyCollision.currentSession(host.collisionEpoch)) return false;
		AABB b = mob.getBoundingBox().expandTowards(mob.getDeltaMovement()).inflate(1, 2, 1);
		return SkyCollision.knownBox(b);
	}

	public static Vec3 collide(Entity mob, Vec3 move) {
		AABB box = mob.getBoundingBox();
		double step = mob.maxUpStep();
		List<SkyTri> tris = new ArrayList<>();
		SkyCollision.trianglesNear(box.expandTowards(move).inflate(1, 1 + step, 1), tris);
		if (tris.isEmpty()) return move;
		double[] r = TriCollider.resolve(tris, mob.getX(), box.minY, mob.getZ(),
			box.getXsize() * 0.5, box.getYsize(), step, mob.onGround(), move.x, move.y, move.z);
		if (r[0] == move.x && r[1] == move.y && r[2] == move.z) return move;
		// Keep real MC blocks authoritative after native slope/step corrections.
		return Entity.collideBoundingBox(mob, new Vec3(r[0], r[1], r[2]), box, mob.level(), List.of());
	}

	/** Golem construction uses an integer Y which can begin inside native ground. Once only. */
	public static void liftSpawn(Mob mob) {
		var tris = new ArrayList<SkyTri>();
		SkyCollision.trianglesNear(mob.getBoundingBox().inflate(1, 1.25, 1), tris);
		double ground = TriCollider.walkableGroundAt(tris, mob.getX(), mob.getY(), mob.getZ(), 1.0);
		if (!Double.isFinite(ground) || ground <= mob.getY() + 1e-6) return;
		Vec3 lift = new Vec3(0, ground - mob.getY(), 0);
		Vec3 allowed = Entity.collideBoundingBox(mob, lift, mob.getBoundingBox(), mob.level(), List.of());
		if (Math.abs(allowed.y - lift.y) > 1e-6) return;
		mob.setPos(mob.getX(), ground, mob.getZ());
		mob.setDeltaMovement(Vec3.ZERO);
		mob.resetFallDistance();
	}
}
