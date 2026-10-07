package dev.skycraft.world;

import static org.junit.jupiter.api.Assertions.*;
import net.minecraft.world.level.pathfinder.PathType;
import net.minecraft.world.phys.shapes.Shapes;
import org.junit.jupiter.api.Test;

class NativePathingTest {
	@Test void thinNativeGroundSharesTheFootCellRatherThanBlockingIt() {
		var floor = Shapes.box(0, 0, 0, 1, 0.125, 1);
		assertEquals(PathType.WALKABLE, NativePathing.rawType(floor));
		assertEquals(12.125, NativePathing.floor(11, 12, floor, null));
	}
	@Test void wallIsBlockedAndUnknownSpaceCannotInventGround() {
		assertEquals(PathType.BLOCKED, NativePathing.rawType(Shapes.block()));
		assertNull(NativePathing.rawType(null));
		assertNull(NativePathing.rawType(Shapes.empty()));
		assertEquals(-1, NativePathing.floor(-1, 0, null, null));
	}
	@Test void realBlockFloorAndNativeStairFloorUseTheHigherSupport() {
		var stair = Shapes.box(0, 0, 0, 1, 0.75, 1);
		assertEquals(4.75, NativePathing.floor(4, 5, null, stair));
		assertEquals(5, NativePathing.floor(5, 5, null, stair));
		assertEquals(5, NativePathing.floor(4, 5, null, Shapes.block()));
	}
}
