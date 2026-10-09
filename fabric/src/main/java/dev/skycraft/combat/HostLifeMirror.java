package dev.skycraft.combat;

/** Reset only transient death presentation after confirmed native revival; keep the player and inventory. */
public interface HostLifeMirror {
	boolean onimusha$clearDeathState();
}
