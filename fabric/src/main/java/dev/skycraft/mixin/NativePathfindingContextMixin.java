package dev.skycraft.mixin;

import dev.skycraft.world.NativePathing;
import dev.skycraft.world.SkyCollision;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.pathfinder.PathfindingContext;
import net.minecraft.world.level.pathfinder.PathType;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(PathfindingContext.class)
public abstract class NativePathfindingContextMixin {
	@Shadow public abstract BlockState getBlockState(BlockPos pos);

	@Inject(method = "getPathTypeFromState", at = @At("HEAD"), cancellable = true)
	private void skycraft$nativeGeometry(int x, int y, int z, CallbackInfoReturnable<PathType> cir) {
		if (!NativePathing.active()) return;
		BlockPos pos = new BlockPos(x, y, z);
		// Keep MC blocks, doors, water and hazards under vanilla's own rules.
		if (!getBlockState(pos).isAir()) return;
		PathType type = NativePathing.rawType(SkyCollision.shapeAt(pos));
		// Apply before the vanilla cache: native geometry updates don't send MC block updates.
		if (type != null) cir.setReturnValue(type);
	}
}
