package dev.skycraft.world;

import dev.skycraft.link.SkyLink;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.pathfinder.PathType;
import net.minecraft.world.phys.shapes.VoxelShape;
import org.jspecify.annotations.Nullable;

/** Pathfinding sees the same streamed collision surfaces as MC mob movement. Never places blocks. */
public final class NativePathing {
	private NativePathing() {}
	public static boolean active() { return SkyLink.active() && SkyCollision.active(); }

	public static @Nullable PathType rawType(@Nullable VoxelShape shape) {
		if (shape == null || shape.isEmpty()) return null;
		// A low surface shares a voxel cell with the standing mob's feet. Marking
		// every nonempty cell BLOCKED strands mobs on thin native ground surfaces.
		return shape.max(Direction.Axis.Y) <= 0.5 ? PathType.WALKABLE : PathType.BLOCKED;
	}

	public static double floor(double vanilla, int y, @Nullable VoxelShape here, @Nullable VoxelShape below) {
		double result = vanilla;
		if (below != null && !below.isEmpty()) result = Math.max(result, y - 1 + below.max(Direction.Axis.Y));
		if (rawType(here) == PathType.WALKABLE) result = Math.max(result, y + here.max(Direction.Axis.Y));
		return result;
	}

	public static boolean supported(BlockPos pos) {
		if (rawType(SkyCollision.shapeAt(pos)) == PathType.WALKABLE) return true;
		var below = SkyCollision.shapeAt(pos.below());
		return below != null && !below.isEmpty() && below.max(Direction.Axis.Y) > 0.5;
	}
}
