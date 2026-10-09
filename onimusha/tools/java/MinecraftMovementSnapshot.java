import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.concurrent.Executor;

/** Read-only, bounded reflection on the client/server's own threads. */
public final class MinecraftMovementSnapshot {
    public static void main(String[] args) throws Exception {
        VirtualMachine vm = VirtualMachine.attach(args[0]);
        try { vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(), args[2]+"|"+args[3]); }
        finally { vm.detach(); }
    }
    static Field field(Class<?> type, String name) throws Exception {
        for (Class<?> c=type;c!=null;c=c.getSuperclass()) {
            try { Field f=c.getDeclaredField(name);f.setAccessible(true);return f; }
            catch (NoSuchFieldException ignored) {}
        }
        throw new NoSuchFieldException(name);
    }
    static void fields(StringBuilder out,Object o,String... names) {
        for(String name:names) try { out.append(name).append('=').append(field(o.getClass(),name).get(o)).append('\n'); }
        catch(Exception e){out.append(name).append("=<unavailable>\n");}
    }
    static String player(Object p) {
        StringBuilder out=new StringBuilder("type="+p.getClass().getName()+"\n");
        for(String name:new String[]{"getHealth","isDeadOrDying","isAlive","getPose","position","getDeltaMovement","onGround","isSleeping","isPassenger","getUUID","getId"}) {
            try {out.append(name).append('=').append(p.getClass().getMethod(name).invoke(p)).append('\n');}
            catch(Exception e){out.append(name).append("=<unavailable>\n");}
        }
        fields(out,p,"dead","deathTime","damageCooldownTime","hurtTime","noPhysics","xxa","yya","zza","isChangingDimension","wonGame","clientLoaded");
        try {Object input=field(p.getClass(),"input").get(p);out.append("INPUT\n");fields(out,input,"keyPresses","moveVector","forwardImpulse","leftImpulse");}catch(Exception ignored){}
        return out.toString();
    }
    public static void agentmain(String options,Instrumentation instrumentation) throws Exception {
        String[] args=options.split("\\|",2);Class<?> type=null;
        for(Class<?> c:instrumentation.getAllLoadedClasses()) if(c.getName().equals("net.minecraft.client.Minecraft")){type=c;break;}
        if(type==null)throw new IllegalStateException("No Minecraft");
        Class<?> mcType=type;Object mc=type.getMethod("getInstance").invoke(null);
        if(!((java.io.File)type.getField("gameDirectory").get(mc)).toPath().toRealPath().equals(Path.of(args[0]).toRealPath()))throw new IllegalStateException("Wrong directory");
        ((Executor)mc).execute(()->{
            try {
                Object p=mcType.getField("player").get(mc);StringBuilder out=new StringBuilder(player(p));
                Class<?> sky=mcType.getClassLoader().loadClass("dev.skycraft.client.SkyClient");
                for(String name:new String[]{"linked","holdPos","holdSince","teleportPending","teleportAck","lastTeleportSeq","unlinkedHold"})out.append(name).append('=').append(field(sky,name).get(null)).append('\n');
                Object host=sky.getMethod("sky").invoke(null);out.append("HOST\n");fields(out,host,"flags","healthCurrent","healthMax","teleportSeq","collisionEpoch","x","y","z");
                Object gui=mcType.getField("gui").get(mc);out.append("screen=").append(gui.getClass().getMethod("screen").invoke(gui)).append('\n');
                Files.writeString(Path.of(args[1]+".client.txt"),out);
                Object server=mcType.getMethod("getSingleplayerServer").invoke(mc);
                Object uuid=p.getClass().getMethod("getUUID").invoke(p);
                ((Executor)server).execute(()->{try{
                    Object list=server.getClass().getMethod("getPlayerList").invoke(server);
                    Object sp=list.getClass().getMethod("getPlayer",java.util.UUID.class).invoke(list,uuid);
                    Files.writeString(Path.of(args[1]+".server.txt"),player(sp));
                }catch(Exception e){throw new RuntimeException(e);}});
            }catch(Exception e){throw new RuntimeException(e);}
        });
    }
}
