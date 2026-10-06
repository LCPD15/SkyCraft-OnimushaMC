package dev.skycraft.combat;

import static org.junit.jupiter.api.Assertions.*;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class ActorProxyIdentityTest {
	@Test
	void reusedActorIdRefreshesItsNameWithoutRepeatedUpdates() {
		Map<Integer, String> names = new HashMap<>();
		names.put(13, "Em101_00");
		AtomicInteger updates = new AtomicInteger();
		var assign = (java.util.function.Consumer<String>) name -> {
			names.put(13, name);
			updates.incrementAndGet();
		};
		assertTrue(ActorProxyIdentity.refreshName(names.get(13), "Em101_50", assign));
		assertEquals("Em101_50", names.get(13));
		assertFalse(ActorProxyIdentity.refreshName(names.get(13), "Em101_50", assign));
		assertEquals(1, updates.get());
		assertTrue(ActorProxyIdentity.refreshName(names.get(13), "", assign));
		assertEquals("", names.get(13));
		assertFalse(ActorProxyIdentity.refreshName(null, "", assign));
	}

	@Test
	void epochAndHostRestartInvalidateThePreviousProxyBoundary() {
		var boundary = new ActorProxyIdentity.Boundary();
		var first = new ActorProxyIdentity.Session(1, 2);
		assertTrue(boundary.observe(first));
		assertFalse(boundary.observe(new ActorProxyIdentity.Session(1, 2)));
		assertTrue(boundary.observe(new ActorProxyIdentity.Session(1, 3)));
		assertTrue(boundary.observe(new ActorProxyIdentity.Session(2, 3)));
		boundary.invalidate();
		assertTrue(boundary.observe(new ActorProxyIdentity.Session(2, 3)));
	}

	@Test
	void clientKeepsNewSessionTagsButRejectsOldSessionTagsWithTheSameActorId() {
		var current = new ActorProxyIdentity.Session(7, 0xFFFF_FFFF);
		assertTrue(current.matches(7, 0xFFFF_FFFF));
		assertFalse(current.matches(6, 0xFFFF_FFFF));
		assertFalse(current.matches(7, 0));
	}
}
