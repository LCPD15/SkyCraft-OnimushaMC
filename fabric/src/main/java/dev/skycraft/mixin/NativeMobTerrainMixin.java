package dev.skycraft.mixin;

import dev.skycraft.world.NativeMobPhysics;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Mob.class)
public abstract class NativeMobTerrainMixin {
	@Unique private boolean skycraft$groundInitialized;

	@Inject(method = "tick", at = @At("HEAD"), cancellable = true)
	private void skycraft$waitForGround(CallbackInfo ci) {
		Mob mob = (Mob) (Object) this;
		if (mob.level().isClientSide() || !NativeMobPhysics.managed(mob)) return;
		if (!NativeMobPhysics.ready(mob)) {
			mob.setDeltaMovement(Vec3.ZERO);
			skycraft$groundInitialized = false;
			ci.cancel();
			return;
		}
		if (!skycraft$groundInitialized) {
			NativeMobPhysics.liftSpawn(mob);
			skycraft$groundInitialized = true;
		}
	}
}
