package dev.skycraft.link;

/** Host viewport pixels -> the hidden MC window's logical mouse-coordinate space. */
public final class GuiCursor {
	public record Point(double x, double y) {}
	private double u, v;
	private boolean known;

	public boolean remember(double x, double y, int viewportWidth, int viewportHeight) {
		if (!Double.isFinite(x) || !Double.isFinite(y) || viewportWidth <= 0 || viewportHeight <= 0) {
			return false;
		}
		u = x / viewportWidth;
		v = y / viewportHeight;
		known = true;
		return true;
	}

	/** Recompute on every replay: a resize or DPI change must not move the normalized cursor. */
	public Point logical(int windowWidth, int windowHeight) {
		if (!known || windowWidth <= 0 || windowHeight <= 0) {
			return null;
		}
		// Keep positions outside the viewport: vanilla inventory outside-click/drop rules need them.
		return new Point(u * windowWidth, v * windowHeight);
	}
}
