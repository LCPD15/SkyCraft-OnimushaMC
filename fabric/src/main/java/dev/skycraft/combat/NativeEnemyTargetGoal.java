package dev.skycraft.combat;

import dev.skycraft.link.SkyLink;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;

/** Allows a golem to select the invisible proxy of a visible native enemy. */
public final class NativeEnemyTargetGoal extends NearestAttackableTargetGoal<SkyrimActorEntity> {
	public NativeEnemyTargetGoal(Mob mob) {
		super(mob, SkyrimActorEntity.class, 10, true, false, (target, level) -> valid((SkyrimActorEntity)target));
		this.targetConditions.ignoreInvisibilityTesting();
	}

	private static boolean valid(SkyrimActorEntity proxy) {
		SkyLink.SkyState host = new SkyLink.SkyState();
		int generation = SkyLink.generation();
		return SkyLink.active() && SkyLink.readSkyState(host)
			&& HostHealth.currentSession(generation, host.collisionEpoch)
			&& proxy.belongsTo(new ActorProxyIdentity.Session(generation, host.collisionEpoch));
	}

	@Override public boolean canContinueToUse() {
		return this.mob.getTarget() instanceof SkyrimActorEntity proxy && valid(proxy) && super.canContinueToUse();
	}
}
