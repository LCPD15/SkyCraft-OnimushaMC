package dev.skycraft.mixin;

import dev.skycraft.world.NativePathing;
import net.minecraft.core.BlockPos;
import net.minecraft.world.entity.ai.navigation.PathNavigation;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(PathNavigation.class)
public abstract class NativeStableDestinationMixin {
	@Inject(method = "isStableDestination", at = @At("RETURN"), cancellable = true)
	private void skycraft$nativeSupport(BlockPos pos, CallbackInfoReturnable<Boolean> cir) {
		if (!cir.getReturnValue() && NativePathing.active() && NativePathing.supported(pos)) cir.setReturnValue(true);
	}
}
