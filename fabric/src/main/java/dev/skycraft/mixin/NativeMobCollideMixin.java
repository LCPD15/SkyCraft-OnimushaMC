package dev.skycraft.mixin;

import dev.skycraft.world.NativeMobPhysics;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Entity.class)
public abstract class NativeMobCollideMixin {
	@Inject(method = "collide", at = @At("RETURN"), cancellable = true)
	private void skycraft$nativeMobCollision(Vec3 movement, CallbackInfoReturnable<Vec3> cir) {
		Entity entity = (Entity) (Object) this;
		if (!entity.level().isClientSide() && NativeMobPhysics.managed(entity)) {
			cir.setReturnValue(NativeMobPhysics.collide(entity, cir.getReturnValue()));
		}
	}
}
