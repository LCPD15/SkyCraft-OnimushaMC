package dev.skycraft.link;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class HostRotationTest {
	@Test void initialTeleportReplacesTheSavedUpwardViewExactlyOnce() {
		var saved = new HostRotation.Angles(-89.55F, -57.75F);
		var arrived = HostRotation.resolve(saved, 25.0F, 0.0F, true, true);
		assertEquals(new HostRotation.Angles(25.0F, 0.0F), arrived);
		assertSame(arrived, HostRotation.resolve(arrived, 0.0F, 40.0F, false, true));
	}
	@Test void normalMinecraftLookIsNotResetEvenByMalformedHostAngles() {
		var playerLook = new HostRotation.Angles(721.25F, -32.0F);
		assertSame(playerLook, HostRotation.resolve(playerLook, Float.NaN, Float.POSITIVE_INFINITY, false, true));
	}
	@Test void sceneTeleportOverridesLookWhileHostControlledFramesStillFollowTheHost() {
		var old = new HostRotation.Angles(12.0F, 34.0F);
		assertEquals(new HostRotation.Angles(-45.0F, 10.0F), HostRotation.resolve(old, -45.0F, 10.0F, true, true));
		assertEquals(new HostRotation.Angles(-45.0F, 10.0F), HostRotation.resolve(old, -45.0F, 10.0F, false, false));
	}
	@Test void teleportClampsPitchAndWrapsYawAtTheVanillaViewBoundaries() {
		var old = new HostRotation.Angles(0, 0);
		assertEquals(new HostRotation.Angles(-180.0F, 90.0F), HostRotation.resolve(old, 540.0F, 100.0F, true, true));
		assertEquals(new HostRotation.Angles(179.0F, -90.0F), HostRotation.resolve(old, -541.0F, -100.0F, true, true));
		assertEquals(new HostRotation.Angles(-180.0F, 90.0F), HostRotation.resolve(old, -180.0F, 90.0F, true, true));
	}
	@Test void invalidHostAnglesCannotPropagateNanOrInfinityIntoTheClientCamera() {
		var old = new HostRotation.Angles(5.0F, 15.0F);
		assertEquals(new HostRotation.Angles(0, 0), HostRotation.resolve(old, Float.NaN, Float.POSITIVE_INFINITY, true, true));
		var large = HostRotation.resolve(old, Float.MAX_VALUE, Float.NEGATIVE_INFINITY, true, true);
		assertTrue(Float.isFinite(large.yaw()) && large.yaw() >= -180.0F && large.yaw() < 180.0F);
		assertEquals(0.0F, large.pitch());
	}
}
