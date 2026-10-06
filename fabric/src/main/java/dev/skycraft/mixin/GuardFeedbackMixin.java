package dev.skycraft.mixin;

import dev.skycraft.combat.GuardObservation;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.component.BlocksAttacks;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Vanilla plays the block sound; this only adds one small particle burst to its real callback. */
@Mixin(BlocksAttacks.class)
public abstract class GuardFeedbackMixin {
	@Inject(method = "onBlocked", at = @At("RETURN"))
	private void onimusha$blockParticles(ServerLevel level, LivingEntity defender, CallbackInfo ci) {
		if (!GuardObservation.vanillaFeedback(defender)) return;
		var forward = LivingEntity.calculateViewVector(0, defender.getYHeadRot());
		level.sendParticles(ParticleTypes.ELECTRIC_SPARK, defender.getX() + forward.x * 0.65,
			defender.getY(0.65), defender.getZ() + forward.z * 0.65, 5, 0.12, 0.12, 0.12, 0.02);
	}
}
