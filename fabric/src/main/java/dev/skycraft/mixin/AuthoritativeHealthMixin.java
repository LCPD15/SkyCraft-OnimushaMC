package dev.skycraft.mixin;

import dev.skycraft.combat.HostHealth;
import dev.skycraft.combat.HostHealthMath;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Intercept the common final mutation, covering fall, drowning, fire, poison and item healing. */
@Mixin(LivingEntity.class)
public abstract class AuthoritativeHealthMixin implements dev.skycraft.combat.HostLifeMirror {
	@Shadow protected boolean dead;
	@Shadow public int deathTime;

	@Override
	public boolean onimusha$clearDeathState() {
		boolean changed = dead || deathTime != 0;
		dead = false;
		deathTime = 0;
		return changed;
	}

	@Inject(method = "tickDeath", at = @At("HEAD"), cancellable = true)
	private void onimusha$nativeOwnsRespawn(CallbackInfo ci) {
		if (HostHealth.ownsLife((LivingEntity) (Object) this)) {
			((LivingEntity) (Object) this).deathTime = 0;
			ci.cancel();
		}
	}

	@Inject(method = "setHealth", at = @At("HEAD"), cancellable = true)
	private void onimusha$nativeOwnsHealth(float value, CallbackInfo ci) {
		if ((Object) this instanceof ServerPlayer player && HostHealth.intercepts(player)) {
			HostHealth.request(player, value);
			ci.cancel();
		}
	}

	@Inject(method = "getMaxHealth", at = @At("HEAD"), cancellable = true)
	private void onimusha$tenHearts(CallbackInfoReturnable<Float> cir) {
		if (HostHealth.mirrored((LivingEntity) (Object) this)) {
			cir.setReturnValue(HostHealthMath.MC_MAX_HEALTH);
		}
	}

	@Inject(method = "heal", at = @At("HEAD"))
	private void onimusha$explicitHealing(float amount, CallbackInfo ci) {
		if ((Object) this instanceof ServerPlayer player && HostHealth.intercepts(player)) {
			HostHealth.beginHealing();
		}
	}

	@Inject(method = "heal", at = @At("RETURN"))
	private void onimusha$finishedHealing(float amount, CallbackInfo ci) {
		HostHealth.endHealing();
	}
}
