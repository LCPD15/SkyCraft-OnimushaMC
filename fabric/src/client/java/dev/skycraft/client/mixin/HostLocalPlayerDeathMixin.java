package dev.skycraft.client.mixin;

import dev.skycraft.client.SkyClient;
import net.minecraft.client.player.LocalPlayer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(LocalPlayer.class)
public abstract class HostLocalPlayerDeathMixin {
	/** LocalPlayer overrides LivingEntity.tickDeath without calling super (removes itself at tick 20). */
	@Inject(method = "tickDeath", at = @At("HEAD"), cancellable = true)
	private void onimusha$keepMirroredLocalPlayer(CallbackInfo ci) {
		if (SkyClient.nativeOwnsDeath()) {
			((LocalPlayer) (Object) this).deathTime = 0;
			ci.cancel();
		}
	}

	/** A stale Respawn button must not recreate the MC player or discard their inventory. */
	@Inject(method = "respawn", at = @At("HEAD"), cancellable = true)
	private void onimusha$nativeOwnsRetry(CallbackInfo ci) {
		if (SkyClient.nativeOwnsDeath()) ci.cancel();
	}
}
