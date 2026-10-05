package dev.skycraft.link;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class GuiCursorTest {
	@Test void dpiScaledWindowKeepsTheSameRenderedPoint() {
		GuiCursor cursor = new GuiCursor();
		assertTrue(cursor.remember(960, 540, 1920, 1080));
		assertEquals(new GuiCursor.Point(640, 360), cursor.logical(1280, 720));
		assertEquals(new GuiCursor.Point(960, 540), cursor.logical(1920, 1080));
	}
	@Test void resizingBetweenMoveAndClickReplaysTheNormalizedPosition() {
		GuiCursor cursor = new GuiCursor();
		cursor.remember(480, 270, 1920, 1080);
		assertEquals(new GuiCursor.Point(320, 180), cursor.logical(1280, 720));
		assertEquals(new GuiCursor.Point(640, 360), cursor.logical(2560, 1440));
	}
	@Test void repeatedClicksWithoutAnotherMoveCannotRevertToWindowCentre() {
		GuiCursor cursor = new GuiCursor();
		cursor.remember(448, 510, 1920, 1080);
		var firstClick = cursor.logical(1280, 720);
		assertEquals(firstClick, cursor.logical(1280, 720));
		assertNotEquals(new GuiCursor.Point(640, 360), firstClick);
	}
	@Test void invalidSizeDoesNotOverwriteTheLatestKnownPosition() {
		GuiCursor cursor = new GuiCursor();
		assertNull(cursor.logical(1280, 720));
		cursor.remember(960, 540, 1920, 1080);
		assertFalse(cursor.remember(0, 0, 0, 1080));
		assertFalse(cursor.remember(Double.NaN, 0, 1920, 1080));
		assertEquals(new GuiCursor.Point(640, 360), cursor.logical(1280, 720));
		assertNull(cursor.logical(0, 720));
	}
	@Test void outsideInventoryClicksRetainVanillaDropCoordinates() {
		GuiCursor cursor = new GuiCursor();
		cursor.remember(-192, 1188, 1920, 1080);
		var point = cursor.logical(1280, 720);
		assertEquals(-128, point.x(), 1e-8);
		assertEquals(792, point.y(), 1e-8);
	}
}
