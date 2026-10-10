package dev.skycraft.combat;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Server-thread per-attack/per-victim accounting, including rejected MC invulnerability hits. */
public final class AttackLedger {
    private record AttackKey(int attacker,int attack,int hit) {}
    private static final class Window {long seen;final Map<UUID,Receipt> victims=new HashMap<>();}
    private record Receipt(long time,int count) {}
    private final Map<AttackKey,Window> windows=new HashMap<>();
    private int session;
    private long lastPrune;
    public void clear(){windows.clear();session=0;lastPrune=0;}
    public void observe(NativeAttack a,long now){
        if(session!=a.session()){clear();session=a.session();}
        if(now-lastPrune>=1000){windows.values().removeIf(w -> now-w.seen>10_000);lastPrune=now;}
        AttackKey k=new AttackKey(a.attacker(),a.attack(),a.hit());
        if(!windows.containsKey(k)&&windows.size()>=2048)return;
        windows.computeIfAbsent(k,ignored -> new Window()).seen=now;
    }
    public boolean admit(NativeAttack a,UUID victim){
        Window w=windows.get(new AttackKey(a.attacker(),a.attack(),a.hit()));if(w==null)return false;
        Receipt old=w.victims.get(victim);
        if(old!=null&&(!a.multi() || (a.maxHits()>0&&old.count>=a.maxHits())
            || a.timeMs()-old.time<Math.max(50,Math.round(a.repeatSeconds()*1000))))return false;
        if(old==null&&w.victims.size()>=512)return false;
        w.victims.put(victim,new Receipt(a.timeMs(),old==null?1:old.count+1));return true;
    }
}
