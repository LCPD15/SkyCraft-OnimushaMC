import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.concurrent.Executor;
import java.util.function.Consumer;

/** Capture framebuffer/input diagnostics; optional focus simulation is restricted to smoke worlds. */
public final class MinecraftWindowPreviewSnapshot {
    public static void main(String[] args) throws Exception {
        var vm=VirtualMachine.attach(args[0]);
        try {vm.loadAgent(Path.of(args[1]).toAbsolutePath().toString(),args[2]+"|"+args[3]+"|"+(args.length>4?args[4]:""));}finally{vm.detach();}
    }
    static Field field(Class<?> c,String n)throws Exception {for(;c!=null;c=c.getSuperclass())try{var f=c.getDeclaredField(n);f.setAccessible(true);return f;}catch(NoSuchFieldException e){}throw new NoSuchFieldException(n);}
    static Object call(Object o,String n)throws Exception{return o.getClass().getMethod(n).invoke(o);}
    public static void agentmain(String options,Instrumentation inst)throws Exception {
        String[] args=options.split("\\|",3);Class<?> mcType=null;
        for(var c:inst.getAllLoadedClasses())if(c.getName().equals("net.minecraft.client.Minecraft")){mcType=c;break;}
        Object mc=mcType.getMethod("getInstance").invoke(null);Class<?> type=mcType;
        if(!((java.io.File)type.getField("gameDirectory").get(mc)).toPath().toRealPath().equals(Path.of(args[0]).toRealPath()))throw new IllegalStateException("Wrong directory");
        ((Executor)mc).execute(()->{try{
            ClassLoader loader=type.getClassLoader();Object renderer=type.getField("gameRenderer").get(mc);
            var preview=loader.loadClass("dev.skycraft.client.LocalWindowPreview");
            StringBuilder out=new StringBuilder("previewFrames="+preview.getField("frames").get(null)+"\n");
            var inputs=loader.loadClass("dev.skycraft.client.InputBridge");out.append("ignoredLocalCallbacks=").append(inputs.getField("ignoredLocalCallbacks").get(null)).append('\n');
            Object mouse=type.getField("mouseHandler").get(mc);
            if(args.length>2&&args[2].equals("focus-smoke")) {
                // This mutating diagnostic is restricted to the disposable smoke world.
                Object server=call(mc,"getSingleplayerServer");
                Object data=call(server,"getWorldData");
                if(!call(data,"getLevelName").toString().startsWith("OnimushaMC-WindowSmoke-"))throw new IllegalStateException("Not a smoke world");
                call(mouse,"releaseMouse");
                Object window=call(mc,"getWindow");
                Class<?> button=loader.loadClass("net.minecraft.client.input.MouseButtonInfo");
                mouse.getClass().getMethod("onButton",long.class,button,int.class).invoke(mouse,
                    call(window,"handle"),button.getConstructor(int.class,int.class).newInstance(3,0),1);
                out.append("afterLocalCallback=").append(inputs.getField("ignoredLocalCallbacks").get(null)).append('\n');
            }
            out.append("mouseGrabbed=").append(call(mouse,"isMouseGrabbed")).append('\n');
            Object player=type.getField("player").get(mc);out.append("hp=").append(call(player,"getHealth")).append("\nitem=").append(call(player,"getMainHandItem")).append("\nusing=").append(call(player,"isUsingItem")).append('\n');
            out.append("gameMode=").append(call(type.getField("gameMode").get(mc),"getPlayerMode")).append('\n');
            Object abilities=call(player,"getAbilities");
            for(String name:new String[]{"mayBuild","instabuild","mayfly","invulnerable"})
                out.append(name).append('=').append(field(abilities.getClass(),name).get(abilities)).append('\n');
            Object level=type.getField("level").get(mc);for(String n:new String[]{"getMinY","getMaxY"})try{out.append(n).append('=').append(call(level,n)).append('\n');}catch(Exception ignored){}
            Object hit=type.getField("hitResult").get(mc);out.append("hit=").append(hit).append('\n');
            Files.writeString(Path.of(args[1]+".txt"),out);
            var screenshot=loader.loadClass("net.minecraft.client.Screenshot");
            Method take=screenshot.getMethod("takeScreenshot",loader.loadClass("com.mojang.blaze3d.pipeline.RenderTarget"),Consumer.class);
            for(String kind:new String[]{"local","overlay","world"}){
                Object target=kind.equals("local")?call(renderer,"mainRenderTarget"):field(preview,kind).get(null);
                if(target==null)continue;
                take.invoke(null,target,(Consumer<Object>)image->{try{
                    image.getClass().getMethod("writeToFile",Path.class).invoke(image,Path.of(args[1]+"-"+kind+".png"));
                    call(image,"close");
                }catch(Exception e){throw new RuntimeException(e);}});
            }
        }catch(Exception e){try{Files.writeString(Path.of(args[1]+".error.txt"),e.toString());}catch(Exception ignored){}throw new RuntimeException(e);}});
    }
}
