package dev.skycraft.link;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import org.junit.jupiter.api.Test;

class OnimushaProtocolTest {
	@Test void forkCannotAttachToUpstreamSkyrimMapping() {
		assertEquals(14, Proto.VERSION);
		assertEquals("Local\\OnimushaMC_v1", Proto.MAPPING_NAME);
		assertNotEquals("Local\\SkyCraft_v1", Proto.MAPPING_NAME);
	}
	@Test void healthLayoutFitsBeforeMinecraftState() {
		assertEquals(0x40, Proto.SS_HEALTH_CURRENT);
		assertEquals(0x44, Proto.SS_HEALTH_MAX);
		assertEquals(0x48, Proto.SS_HOST_UNITS_PER_BLOCK);
		assertEquals(0x50, Proto.SS_HEALTH_REVISION);
		assertTrue(Proto.OFF_SKY_STATE + Proto.SKY_STATE_BYTES <= Proto.OFF_MC_STATE);
		ByteBuffer bytes = ByteBuffer.allocate((int) Proto.SKY_STATE_BYTES).order(ByteOrder.LITTLE_ENDIAN);
		bytes.putFloat((int) Proto.SS_HEALTH_CURRENT, 1250);
		bytes.putFloat((int) Proto.SS_HEALTH_MAX, 2500);
		bytes.putDouble((int) Proto.SS_HOST_UNITS_PER_BLOCK, 1);
		bytes.putInt((int) Proto.SS_HEALTH_REVISION, 17);
		assertEquals(1250, bytes.getFloat(0x40));
		assertEquals(2500, bytes.getFloat(0x44));
		assertEquals(1, bytes.getDouble(0x48));
		assertEquals(17, bytes.getInt(0x50));
	}
	@Test void healthRequestHasItsOwnEventTypeAndEpochField() {
		assertEquals(6, Proto.EV_HEALTH_CHANGE);
		assertNotEquals(Proto.EV_PLAYER_DIED, Proto.EV_HEALTH_CHANGE);
		assertEquals(32, Proto.EVENT_BYTES);
		assertEquals(1, Proto.HEALTH_DAMAGE);
		assertEquals(2, Proto.HEALTH_HEAL);
	}
}
