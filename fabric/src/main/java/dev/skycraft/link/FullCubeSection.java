package dev.skycraft.link;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Conservative unit-box subset; never expands slabs, fences or stairs to solid cubes. */
public final class FullCubeSection {
	private final long[] words = new long[64];
	private int count;
	public void clear() { java.util.Arrays.fill(words, 0L); count = 0; }
	public int count() { return count; }
	public static boolean unitBox(int boxes, double x0, double y0, double z0, double x1, double y1, double z1) {
		return boxes == 1 && x0 == 0 && y0 == 0 && z0 == 0 && x1 == 1 && y1 == 1 && z1 == 1;
	}
	public void add(int x, int y, int z) {
		if (x < 0 || x > 15 || y < 0 || y > 15 || z < 0 || z > 15) throw new IllegalArgumentException("Section coordinate");
		int i = x + 16 * z + 256 * y;
		long mask = 1L << (i & 63);
		if ((words[i >> 6] & mask) == 0) { words[i >> 6] |= mask; count++; }
	}
	public ByteBuffer header(int sx, int sy, int sz, int world, int epoch, int pid) {
		return ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN)
			.putInt(sx).putInt(sy).putInt(sz).putInt(count).putInt(world).putInt(epoch).putInt(pid).putInt(0).flip();
	}
	public ByteBuffer bits() {
		ByteBuffer b = ByteBuffer.allocate(count == 0 ? 0 : 512).order(ByteOrder.LITTLE_ENDIAN);
		if (count != 0) for (long word : words) b.putLong(word);
		return b.flip();
	}
}
