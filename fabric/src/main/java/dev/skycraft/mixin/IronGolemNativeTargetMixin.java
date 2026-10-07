package dev.skycraft.mixin;

import dev.skycraft.combat.NativeEnemyTargetGoal;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.animal.golem.AbstractGolem;
import net.minecraft.world.entity.animal.golem.IronGolem;
import net.minecraft.world.level.Level;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(IronGolem.class)
public abstract class IronGolemNativeTargetMixin extends AbstractGolem {
	@Unique private int skycraft$pathSamples;
	protected IronGolemNativeTargetMixin(EntityType<? extends AbstractGolem> type, Level level) { super(type, level); }

	@Inject(method = "registerGoals", at = @At("TAIL"))
	private void skycraft$nativeTargets(CallbackInfo ci) {
		this.targetSelector.addGoal(3, new NativeEnemyTargetGoal(this));
	}

	@Inject(method = "aiStep", at = @At("TAIL"))
	private void skycraft$observePath(CallbackInfo ci) {
		if (level().isClientSide() || !dev.skycraft.link.SkyLink.active()
			|| tickCount % 100 != 0 || skycraft$pathSamples >= 96) return;
		skycraft$pathSamples++;
		var path = getNavigation().getPath();
		dev.skycraft.SkyCraft.LOG.info("Onimusha golem {} pos={} ground={} target={} path={} next={} done={}",
			getId(), position(), onGround(), getTarget() == null ? null : getTarget().getId(),
			path == null ? 0 : path.getNodeCount(), path == null ? -1 : path.getNextNodeIndex(), getNavigation().isDone());
	}
}
