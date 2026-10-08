package dev.skycraft.client;

import dev.skycraft.SkyCraft;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.item.PrimedTnt;

/** The vanilla priming sample ends before the fuse. Keep positional audio alive
 * for the linked TNT's lifetime, independently of native rendering receipts. */
public final class TntFuseAudio {
    private static final Map<Integer, FuseSound> sounds = new HashMap<>();
    private static Object level;
    private TntFuseAudio() {}

    public static boolean replaces(SoundInstance sound) {
        var mc = Minecraft.getInstance();
        if (!SkyClient.linked() || mc.level == null || mc.player == null || sound instanceof FuseSound
            || !sound.getIdentifier().equals(SoundEvents.TNT_PRIMED.location())) return false;
        // Do not mute a TNT minecart or a mod's unrelated use of this sound.
        for (Entity entity : mc.level.entitiesForRendering()) {
            if (entity instanceof PrimedTnt tnt && tnt.isAlive() && tnt.getFuse() > 0
                && mc.player.distanceToSqr(tnt) <= 64 * 64
                && tnt.distanceToSqr(sound.getX(), sound.getY(), sound.getZ()) < 1
                && (sounds.containsKey(tnt.getId()) || sounds.size() < 32)) return true;
        }
        return false;
    }

    public static void tick(Minecraft mc) {
        if (!SkyClient.linked() || mc.level == null || mc.player == null || level != mc.level) {
            for (FuseSound sound : sounds.values()) { sound.finish(); mc.getSoundManager().stop(sound); }
            sounds.clear(); level = mc.level;
            if (!SkyClient.linked() || mc.level == null || mc.player == null) return;
        }
        Set<Integer> wanted = new HashSet<>();
        for (Entity entity : mc.level.entitiesForRendering()) {
            if (!(entity instanceof PrimedTnt tnt) || !tnt.isAlive() || tnt.getFuse() <= 0
                || mc.player.distanceToSqr(tnt) > 64 * 64 || wanted.size() >= 32) continue;
            wanted.add(tnt.getId());
            FuseSound sound = sounds.get(tnt.getId());
            if (sound == null || sound.tnt != tnt) {
                if (sound != null) { sound.finish(); mc.getSoundManager().stop(sound); }
                sound = new FuseSound(tnt); sounds.put(tnt.getId(), sound);
                var result = mc.getSoundManager().play(sound);
                SkyCraft.LOG.info("OnimushaMC: TNT fuse audio start entity={} fuse={} result={}", tnt.getId(), tnt.getFuse(), result);
            }
            // Bounded late-fuse evidence, without a log entry on every tick.
            if (!sound.lateLogged && tnt.getFuse() <= 10) {
                sound.lateLogged = true;
                SkyCraft.LOG.info("OnimushaMC: TNT fuse audio late entity={} fuse={} active={}",
                    tnt.getId(), tnt.getFuse(), mc.getSoundManager().isActive(sound));
            }
        }
        var iterator = sounds.entrySet().iterator();
        while (iterator.hasNext()) {
            var entry = iterator.next();
            if (!wanted.contains(entry.getKey())) {
                entry.getValue().finish(); mc.getSoundManager().stop(entry.getValue()); iterator.remove();
                SkyCraft.LOG.info("OnimushaMC: TNT fuse audio stop entity={}", entry.getKey());
            }
        }
    }

    private static final class FuseSound extends AbstractTickableSoundInstance {
        final PrimedTnt tnt;
        boolean lateLogged;
        FuseSound(PrimedTnt tnt) {
            super(SoundEvents.TNT_PRIMED, SoundSource.BLOCKS, SoundInstance.createUnseededRandom());
            this.tnt = tnt; looping = true; delay = 0; volume = 1; pitch = 1;
            updatePosition();
        }
        private void updatePosition() { x = tnt.getX(); y = tnt.getY(); z = tnt.getZ(); }
        void finish() { stop(); }
        @Override public void tick() {
            if (!SkyClient.linked() || !tnt.isAlive() || tnt.getFuse() <= 0) { stop(); return; }
            updatePosition();
        }
    }
}
