package dev.skycraft.combat;
import java.util.ArrayList;
import java.util.List;
public final class SoulRewardMath {
    public enum Kind { HEAL, REPAIR, STACK, EXPERIENCE }
    private SoulRewardMath() {}
    public static List<Kind> eligible(boolean heal,boolean repair,boolean stack) {
        var result=new ArrayList<Kind>(4);
        if(heal)result.add(Kind.HEAL);if(repair)result.add(Kind.REPAIR);if(stack)result.add(Kind.STACK);
        result.add(Kind.EXPERIENCE);return result;
    }
    public record Progress(int levels,float fraction) {}
    public static Progress addExperienceProgress(float old) {
        double value=Math.max(0,Math.min(.99999999,old))+.23;
        return new Progress((int)value,(float)(value-(int)value));
    }
}
