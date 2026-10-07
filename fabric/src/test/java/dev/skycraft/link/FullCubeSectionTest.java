package dev.skycraft.link;
import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class FullCubeSectionTest {
	@Test void partialAndDisconnectedShapesNeverBecomeUnitCubes() {
		assertTrue(FullCubeSection.unitBox(1,0,0,0,1,1,1));
		assertFalse(FullCubeSection.unitBox(1,0,0,0,1,.5,1)); // lower slab
		assertFalse(FullCubeSection.unitBox(1,0,.5,0,1,1,1)); // upper slab
		assertFalse(FullCubeSection.unitBox(2,0,0,0,1,1,1)); // stairs/union bounding box
		assertFalse(FullCubeSection.unitBox(1,.375,0,.375,.625,1.5,.625)); // fence
		assertFalse(FullCubeSection.unitBox(0,0,0,0,1,1,1));
		assertFalse(FullCubeSection.unitBox(1,Double.NaN,0,0,1,1,1));
	}
	@Test void bitOrderCountsAndEmptyRemovalMatchNativeWireFormat() {
		var s = new FullCubeSection(); s.add(1,2,3); s.add(1,2,3); s.add(15,15,15);
		assertEquals(2,s.count());
		var h = s.header(-2,4,6,9,81,1234);
		assertEquals(32,h.remaining()); assertEquals(-2,h.getInt(0)); assertEquals(2,h.getInt(12));
		assertEquals(9,h.getInt(16)); assertEquals(81,h.getInt(20)); assertEquals(1234,h.getInt(24)); assertEquals(0,h.getInt(28));
		var b = s.bits(); assertEquals(512,b.remaining());
		int i=1+16*3+256*2; assertEquals(1,(b.get(i>>3)>>(i&7))&1);
		assertEquals(1,(b.get(511)>>7)&1);
		s.clear(); assertEquals(0,s.count()); assertEquals(0,s.bits().remaining()); assertEquals(0,s.header(0,0,0,9,81,1234).getInt(12));
		assertThrows(IllegalArgumentException.class,()->s.add(16,0,0));
	}
}
