import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.Executor;

/** Development check with takeover OFF. Client-thread-only changes are restored before a frame can publish. */
public final class MinecraftDeathSyncCheck {
    public static void main(String[] args) throws Exception {
        if (args.length != 4) throw new IllegalArgumentException("PID agent.jar expected-game-directory result-file");
        VirtualMachine vm = VirtualMachine.attach(args[0]);
        try { vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(), args[2] + "|" + args[3]); }
        finally { vm.detach(); }
    }
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
    public static void agentmain(String options, Instrumentation instrumentation) throws Exception {
        String[] args = options.split("\\|", 2);
        Class<?> mcType = null;
        for (Class<?> type : instrumentation.getAllLoadedClasses())
            if (type.getName().equals("net.minecraft.client.Minecraft")) { mcType = type; break; }
        if (mcType == null) throw new IllegalStateException("Minecraft not loaded");
        Object mc = mcType.getMethod("getInstance").invoke(null);
        Path actual = ((java.io.File) mcType.getField("gameDirectory").get(mc)).toPath().toRealPath();
        require(actual.equals(Path.of(args[0]).toRealPath()), "Wrong Minecraft instance");
        Class<?> minecraft = mcType;
        ((Executor) mc).execute(() -> {
            String result;
            try {
                ClassLoader loader = minecraft.getClassLoader();
                Class<?> sky = loader.loadClass("dev.skycraft.client.SkyClient");
                require((boolean) sky.getMethod("nativeOwnsDeath").invoke(null), "Native authority unavailable");
                Object hostState = sky.getMethod("sky").invoke(null);
                require(!(boolean) hostState.getClass().getMethod("mcLook").invoke(hostState), "Turn takeover OFF before maintenance");
                Object player = minecraft.getField("player").get(mc);
                Object gui = minecraft.getField("gui").get(mc);
                Class<?> living = loader.loadClass("net.minecraft.world.entity.LivingEntity");
                Class<?> local = loader.loadClass("net.minecraft.client.player.LocalPlayer");
                Class<?> screen = loader.loadClass("net.minecraft.client.gui.screens.Screen");
                Class<?> deathScreen = loader.loadClass("net.minecraft.client.gui.screens.DeathScreen");
                Class<?> component = loader.loadClass("net.minecraft.network.chat.Component");
                var getHealth = living.getMethod("getHealth");
                var setHealth = living.getMethod("setHealth", float.class);
                Field dead = living.getDeclaredField("dead"); dead.setAccessible(true);
                Field deathTime = living.getField("deathTime");
                Field currentScreen = gui.getClass().getDeclaredField("screen"); currentScreen.setAccessible(true);
                Field linked = sky.getDeclaredField("linked"); linked.setAccessible(true);
                var setScreen = gui.getClass().getMethod("setScreen", screen);
                float hp = (float) getHealth.invoke(player);
                boolean wasDead = dead.getBoolean(player); int time = deathTime.getInt(player);
                Object oldScreen = currentScreen.get(gui);
                require(hp > 0 && !wasDead, "Wait for healthy native HP mirror before check");
                try {
                    setHealth.invoke(player, 0f); dead.setBoolean(player, true); deathTime.setInt(player, 17);
                    setScreen.invoke(gui, new Object[]{null});
                    require(!deathScreen.isInstance(currentScreen.get(gui)), "Implicit DeathScreen escaped redirect");
                    Object stale = deathScreen.getConstructor(component, boolean.class, local).newInstance(null, false, player);
                    setScreen.invoke(gui, stale);
                    require(!deathScreen.isInstance(currentScreen.get(gui)), "Explicit DeathScreen escaped guard");
                    // Open through the real GUI lifecycle (Fabric initializes its per-screen events there).
                    // A constructor plus direct screen assignment is not a valid initialized Screen.
                    linked.setBoolean(null, false);
                    try { setScreen.invoke(gui, stale); }
                    finally { linked.setBoolean(null, true); }
                    require(deathScreen.isInstance(currentScreen.get(gui)), "Legacy-screen fixture did not open");
                    setHealth.invoke(player, hp);
                    var sync = sky.getDeclaredMethod("synchronizeNativeLife", minecraft); sync.setAccessible(true);
                    sync.invoke(null, mc);
                    require(!(boolean) living.getMethod("isDeadOrDying").invoke(player), "Native revival did not clear dead flag");
                    require(deathTime.getInt(player) == 0, "Death animation timer survived retry");
                    require(!deathScreen.isInstance(currentScreen.get(gui)), "Stale DeathScreen survived retry");
                    require((float) getHealth.invoke(player) == hp, "Recovery changed HP");
                    require(minecraft.getField("player").get(mc) == player, "Recovery replaced player/inventory owner");
                    result = "PASS implicit screen; explicit screen; old screen cleanup; dead flag and timer reset; HP and player identity unchanged";
                } finally {
                    setHealth.invoke(player, hp); dead.setBoolean(player, wasDead); deathTime.setInt(player, time);
                    setScreen.invoke(gui, oldScreen);
                }
            } catch (Throwable e) {
                java.io.StringWriter writer = new java.io.StringWriter();
                e.printStackTrace(new java.io.PrintWriter(writer)); result = "FAIL " + writer;
            }
            try { Files.writeString(Path.of(args[1]), result); }
            catch (Exception e) { throw new RuntimeException(e); }
        });
    }
}
