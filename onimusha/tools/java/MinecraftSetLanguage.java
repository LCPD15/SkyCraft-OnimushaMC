import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.nio.file.*;
import java.util.concurrent.Executor;

/** Persist the next-launch language on MC's own thread without reloading resources mid-combat. */
public final class MinecraftSetLanguage {
    public static void main(String[] args) throws Exception {
        if(args.length!=4)throw new IllegalArgumentException("PID agent.jar game-directory receipt-path");
        var vm=VirtualMachine.attach(args[0]);
        try{vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(),args[2]+"|"+args[3]);}
        finally{vm.detach();}
    }
    public static void agentmain(String args, Instrumentation inst) throws Exception {
        var paths=args.split("\\|",2);
        Class<?> type=null;
        for(var t:inst.getAllLoadedClasses())if(t.getName().equals("net.minecraft.client.Minecraft")){type=t;break;}
        if(type==null)throw new IllegalStateException("Minecraft not loaded");
        var mcType=type;var mc=type.getMethod("getInstance").invoke(null);
        var directory=((java.io.File)type.getField("gameDirectory").get(mc)).toPath().toRealPath();
        if(!directory.equals(Path.of(paths[0]).toRealPath()))throw new IllegalStateException("Wrong Minecraft directory");
        ((Executor)mc).execute(()->{try{
            var options=mcType.getField("options").get(mc);
            var field=options.getClass().getField("languageCode");
            var before=field.get(options);
            field.set(options,"zh_cn");
            options.getClass().getMethod("save").invoke(options);
            if(!"zh_cn".equals(field.get(options)) || !Files.readAllLines(directory.resolve("options.txt")).contains("lang:zh_cn"))
                throw new IllegalStateException("Language readback failed");
            Files.writeString(Path.of(paths[1]),"before="+before+"\nafter=zh_cn\nsaved=true\nresource_reload=false\neffective=next_launch\n");
        }catch(Exception e){try{Files.writeString(Path.of(paths[1]),"ERROR "+e);}catch(Exception ignored){}}});
    }
}
