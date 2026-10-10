package dev.skycraft.link;

import dev.skycraft.combat.NativeAttack;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.VarHandle;
import java.util.ArrayList;
import java.util.List;
import static java.lang.foreign.ValueLayout.*;

/** Only the integrated-server thread consumes this ring. Input/render threads never touch its tail. */
public final class NativeAttackReader {
    private static final VarHandle INT=JAVA_INT.varHandle(),LONG=JAVA_LONG.varHandle();
    private NativeAttackReader(){}
    public static boolean liveSession(int session,int epoch,int world){
        MemorySegment s=SkyLink.segment();long b=Proto.OFF_ATTACK_RING;
        if(s==null||!SkyLink.active()||(int)INT.getAcquire(s,b+8)!=1)return false;
        int current=(int)INT.getAcquire(s,b+12);
        boolean same=current==session&&s.get(JAVA_INT,b+16)==epoch&&s.get(JAVA_INT,b+20)==world;
        VarHandle.loadLoadFence();return same&&(int)INT.getAcquire(s,b+8)==1&&(int)INT.getAcquire(s,b+12)==session;
    }
    public static List<NativeAttack> drain(){
        MemorySegment s=SkyLink.segment();if(s==null)return List.of();long b=Proto.OFF_ATTACK_RING;
        long head=(long)LONG.getAcquire(s,b),tail=(long)LONG.getAcquire(s,b+0x40);
        if(tail<0||head<tail||head-tail>Proto.ATTACK_RING_ENTRIES)return List.of();
        List<NativeAttack> out=new ArrayList<>();long now=SkyLink.tickCount();
        for(;tail<head;tail++){
            long p=b+0x80+(tail&(Proto.ATTACK_RING_ENTRIES-1))*Proto.ATTACK_RECORD_BYTES;
            int session=s.get(JAVA_INT,p+8),epoch=s.get(JAVA_INT,p+12),world=s.get(JAVA_INT,p+16);
            if(!liveSession(session,epoch,world))continue;
            double[] geometry=new double[24];for(int i=0;i<24;i++)geometry[i]=s.get(JAVA_FLOAT,p+68+i*4L);
            NativeAttack a=new NativeAttack(s.get(JAVA_LONG,p),session,epoch,world,s.get(JAVA_INT,p+20),
                s.get(JAVA_INT,p+24),s.get(JAVA_INT,p+28),s.get(JAVA_INT,p+32),s.get(JAVA_INT,p+36),
                s.get(JAVA_FLOAT,p+40),s.get(JAVA_FLOAT,p+44),s.get(JAVA_INT,p+48),
                s.get(JAVA_FLOAT,p+56),s.get(JAVA_FLOAT,p+60),s.get(JAVA_FLOAT,p+64),geometry);
            if(a.valid(now))out.add(a);
        }
        LONG.setRelease(s,b+0x40,tail);return out;
    }
}
