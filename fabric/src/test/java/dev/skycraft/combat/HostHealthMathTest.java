package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class HostHealthMathTest {
	@Test void restartingHostCannotReuseAnOldHealthRequestWithTheSameEpoch() {
		assertTrue(HostHealthMath.sameSession(7, 1, 7, 1));
		assertFalse(HostHealthMath.sameSession(7, 1, 8, 1));
		assertFalse(HostHealthMath.sameSession(7, 1, 7, 2));
	}
	@Test void fiftyPercentAlwaysMeansFiveHearts() {
		assertEquals(10.0F, HostHealthMath.minecraftHealth(50, 100));
		assertEquals(10.0F, HostHealthMath.minecraftHealth(1250, 2500));
	}
	@Test void changingNativeMaxDoesNotAssumeFullHealth() {
		assertEquals(5.0F, HostHealthMath.minecraftHealth(50, 200));
		assertEquals(20.0F, HostHealthMath.minecraftHealth(100, 100));
	}
	@Test void nativeDeathAndOverhealAreClamped() {
		assertEquals(0, HostHealthMath.minecraftHealth(-5, 100));
		assertEquals(20, HostHealthMath.minecraftHealth(150, 100));
	}
	@Test void invalidHostStateIsRejectedInsteadOfReviving() {
		assertFalse(HostHealthMath.valid(10, 0));
		assertFalse(HostHealthMath.valid(Float.NaN, 100));
		assertFalse(HostHealthMath.valid(10, Float.POSITIVE_INFINITY));
		assertThrows(IllegalArgumentException.class, () -> HostHealthMath.minecraftHealth(10, 0));
	}
	@Test void damageIsAHostPercentageNotAnAbsoluteHpWrite() {
		assertEquals(-0.15F, HostHealthMath.requestedFraction(12, 9, false), 1e-6);
		assertEquals(-0.6F, HostHealthMath.requestedFraction(12, -100, false), 1e-6);
	}
	@Test void respawnAndAutomaticResetsCannotHealNativeGame() {
		assertEquals(0, HostHealthMath.requestedFraction(3, 20, false));
		assertEquals(0, HostHealthMath.requestedFraction(0, 20, false));
	}
	@Test void explicitItemHealingRequestsOnlyActualMissingHealth() {
		assertEquals(0.2F, HostHealthMath.requestedFraction(12, 16, true), 1e-6);
		assertEquals(0.1F, HostHealthMath.requestedFraction(18, 100, true), 1e-6);
		assertEquals(0, HostHealthMath.requestedFraction(20, 30, true));
	}
	@Test void nonFiniteRequestsCannotCrossProcessBoundary() {
		assertEquals(0, HostHealthMath.requestedFraction(Float.NaN, 10, true));
		assertEquals(0, HostHealthMath.requestedFraction(10, Float.POSITIVE_INFINITY, true));
	}
}
