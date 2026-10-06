package dev.skycraft.mixin;

import dev.skycraft.combat.GuardObservation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(LivingEntity.class)
public abstract class GuardObservationMixin {
	@Inject(method = "applyItemBlocking", at = @At("RETURN"))
	private void onimusha$observeReduction(ServerLevel level, DamageSource source, float incoming,
		CallbackInfoReturnable<Float> cir) {
		GuardObservation.blockingApplied(this, incoming, cir.getReturnValue());
	}
}
