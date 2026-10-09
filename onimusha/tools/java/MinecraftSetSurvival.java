import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.nio.file.*;
import java.util.concurrent.Executor;

/** Restore vanilla Survival through the integrated server; never edit a running save on disk. */
public final class MinecraftSetSurvival {
    static Object call(Object object,String name)throws Exception{return object.getClass().getMethod(name).invoke(object);}
    public static void main(String[] args)throws Exception {
        var vm=VirtualMachine.attach(args[0]);
        try{vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(),args[2]+"|"+args[3]);}finally{vm.detach();}
    }
    public static void agentmain(String options,Instrumentation inst)throws Exception {
        var args=options.split("\\|",2);
        Class<?> type=null;
        for(var candidate:inst.getAllLoadedClasses())if(candidate.getName().equals("net.minecraft.client.Minecraft")){type=candidate;break;}
        if(type==null)throw new IllegalStateException("Minecraft not loaded");
        var mcType=type;Object mc=type.getMethod("getInstance").invoke(null);
        if(!((java.io.File)type.getField("gameDirectory").get(mc)).toPath().toRealPath().equals(Path.of(args[0]).toRealPath()))throw new IllegalStateException("Wrong game directory");
        ((Executor)mc).execute(()->{try{
            Object server=call(mc,"getSingleplayerServer");
            if(server==null)throw new IllegalStateException("An integrated server is required");
            Object uuid=call(mcType.getField("player").get(mc),"getUUID");
            ((Executor)server).execute(()->{try{
                Object data=call(server,"getWorldData");
                if(!call(data,"getLevelName").equals("OnimushaMC-XYZ-v2"))throw new IllegalStateException("Wrong world");
                Object list=call(server,"getPlayerList");
                Object player=list.getClass().getMethod("getPlayer",java.util.UUID.class).invoke(list,uuid);
                Class<?> mode=mcType.getClassLoader().loadClass("net.minecraft.world.level.GameType");
                Object before=call(player,"gameMode");
                Object changed=player.getClass().getMethod("setGameMode",mode).invoke(player,mode.getField("SURVIVAL").get(null));
                Object abilities=call(player,"getAbilities");
                Files.writeString(Path.of(args[1]),"before="+before+"\nafter="+call(player,"gameMode")+"\nchanged="+changed+"\nmayBuild="+abilities.getClass().getField("mayBuild").get(abilities)+"\n");
            }catch(Exception e){try{Files.writeString(Path.of(args[1]),"ERROR "+e);}catch(Exception ignored){}}});
        }catch(Exception e){try{Files.writeString(Path.of(args[1]),"ERROR "+e);}catch(Exception ignored){}}});
    }
}
