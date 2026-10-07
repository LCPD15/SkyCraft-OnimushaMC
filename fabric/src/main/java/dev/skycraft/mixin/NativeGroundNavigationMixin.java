package dev.skycraft.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import dev.skycraft.world.NativePathing;
import dev.skycraft.world.SkyCollision;
import net.minecraft.core.BlockPos;
import net.minecraft.world.entity.ai.navigation.GroundPathNavigation;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.pathfinder.PathType;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(GroundPathNavigation.class)
public abstract class NativeGroundNavigationMixin {
	@Inject(method = "findSurfacePosition", at = @At("HEAD"), cancellable = true)
	private void skycraft$surfaceInFootCell(LevelChunk chunk, BlockPos pos, int accuracy, CallbackInfoReturnable<BlockPos> cir) {
		if (NativePathing.active() && chunk.getBlockState(pos).isAir()
			&& NativePathing.rawType(SkyCollision.shapeAt(pos)) == PathType.WALKABLE) cir.setReturnValue(pos);
	}

	@WrapOperation(method = "findSurfacePosition", at = @At(value = "INVOKE",
		target = "Lnet/minecraft/world/level/chunk/LevelChunk;getBlockState(Lnet/minecraft/core/BlockPos;)Lnet/minecraft/world/level/block/state/BlockState;"))
	private BlockState skycraft$surfaceScan(LevelChunk chunk, BlockPos pos, Operation<BlockState> original) {
		BlockState block = original.call(chunk, pos);
		return NativePathing.active() && block.isAir() && SkyCollision.hasGeometry(pos)
			? Blocks.STONE.defaultBlockState() : block;
	}
}
