package dev.skycraft.combat;

/** Owned, immutable numeric copy of a protocol-16 attack; never an engine pointer. */
public record NativeAttack(long timeMs, int session, int epoch, int world, int attacker,
    int attack, int hit, int shape, int flags, float damage, float repeatSeconds, int maxHits,
    double x, double y, double z, double[] geometry) {
    public NativeAttack { geometry=geometry.clone(); }
    public boolean valid(long now) {
        if(timeMs<=0 || now<timeMs || now-timeMs>250 || session==0 || attacker==0 || attack<0 || hit<0
            || (shape!=1 && shape!=2) || (flags&~1)!=0 || !Float.isFinite(damage) || damage<=0 || damage>10000
            || !Float.isFinite(repeatSeconds) || repeatSeconds<0 || repeatSeconds>3600 || maxHits<0 || maxHits>100000
            || !coordinate(x)||!coordinate(y)||!coordinate(z)||geometry.length!=24)return false;
        for(double v:geometry)if(!coordinate(v))return false;
        var bounds=AttackGeometry.bounds(this);
        for(int i=0;i<3;i++)if(bounds.max(i)-bounds.min(i)>256)return false;
        if(shape==1)return geometry[6]>0&&geometry[6]<=64&&geometry[13]>0&&geometry[13]<=64;
        for(int i=0;i<3;i++) {
            if(geometry[12+i]<=0||geometry[12+i]>64)return false;
            double norm=0;for(int j=0;j<3;j++)norm+=geometry[3+3*i+j]*geometry[3+3*i+j];
            if(Math.abs(norm-1)>0.002)return false;
            for(int k=0;k<i;k++){double dot=0;for(int j=0;j<3;j++)dot+=geometry[3+3*i+j]*geometry[3+3*k+j];if(Math.abs(dot)>0.002)return false;}
        }
        return true;
    }
    private static boolean coordinate(double v){return Double.isFinite(v)&&Math.abs(v)<=30_000_000;}
    public boolean multi(){return (flags&1)!=0;}
}
