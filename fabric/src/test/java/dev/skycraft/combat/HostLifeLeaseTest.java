package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class HostLifeLeaseTest {
	@Test void deathLoadAndHeartbeatLossDoNotReleaseTheSameLife() {
		var lease = new HostLifeLease();
		Object player = new Object(), level = new Object(), server = new Object();
		assertFalse(lease.update(player, level, server, false));
		assertTrue(lease.update(player, level, server, true));
		for (int tick = 0; tick < 600; tick++) assertTrue(lease.update(player, level, server, false));
		assertTrue(lease.update(player, level, server, true));
	}
	@Test void replacementPlayerOrWorldRequiresNewAuthority() {
		var lease = new HostLifeLease();
		Object p = new Object(), l = new Object(), s = new Object();
		assertTrue(lease.update(p, l, s, true));
		assertFalse(lease.update(new Object(), l, s, false));
		assertTrue(lease.update(p, l, s, true));
		assertFalse(lease.update(p, new Object(), s, false));
		assertTrue(lease.update(p, l, s, true));
		assertFalse(lease.update(p, l, new Object(), false));
	}
	@Test void disconnectClearsOwnershipEvenIfTheSameObjectsAreLaterOffered() {
		var lease = new HostLifeLease();
		Object p = new Object(), l = new Object(), s = new Object();
		assertTrue(lease.update(p, l, s, true));
		assertFalse(lease.update(null, null, null, true));
		assertFalse(lease.update(p, l, s, false));
	}
}
