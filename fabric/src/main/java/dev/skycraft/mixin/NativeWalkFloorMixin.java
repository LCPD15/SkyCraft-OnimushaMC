package dev.skycraft.mixin;

import dev.skycraft.world.NativePathing;
import dev.skycraft.world.SkyCollision;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.pathfinder.WalkNodeEvaluator;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(WalkNodeEvaluator.class)
public abstract class NativeWalkFloorMixin {
	@Inject(method = "getFloorLevel(Lnet/minecraft/world/level/BlockGetter;Lnet/minecraft/core/BlockPos;)D",
		at = @At("RETURN"), cancellable = true)
	private static void skycraft$nativeFloor(BlockGetter level, BlockPos pos, CallbackInfoReturnable<Double> cir) {
		if (NativePathing.active()) cir.setReturnValue(NativePathing.floor(cir.getReturnValue(), pos.getY(),
			SkyCollision.shapeAt(pos), SkyCollision.shapeAt(pos.below())));
	}
}
