import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.nio.file.Path;
import java.util.concurrent.Executor;

/** Maintenance only: call Minecraft.stop on its own render thread; never terminate Java. */
public final class MinecraftSaveAndQuit {
    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("PID agent.jar expected-game-directory");
        VirtualMachine vm = VirtualMachine.attach(args[0]);
        try { vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(), args[2]); }
        finally { vm.detach(); }
    }
    public static void agentmain(String expectedDirectory, Instrumentation instrumentation) throws Exception {
        Class<?> minecraftClass = null;
        for (Class<?> type : instrumentation.getAllLoadedClasses()) {
            if (type.getName().equals("net.minecraft.client.Minecraft")) { minecraftClass = type; break; }
        }
        if (minecraftClass == null) throw new IllegalStateException("Minecraft is not loaded");
        Object minecraft = minecraftClass.getMethod("getInstance").invoke(null);
        Path actual = ((java.io.File) minecraftClass.getField("gameDirectory").get(minecraft)).toPath().toRealPath();
        if (!actual.equals(Path.of(expectedDirectory).toRealPath())) throw new IllegalStateException("Wrong Minecraft installation");
        var stop = minecraftClass.getMethod("stop");
        ((Executor) minecraft).execute(() -> {
            try {
                System.out.println("Onimusha maintenance: normal Minecraft save-and-quit requested");
                stop.invoke(minecraft);
            } catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
        });
    }
}
