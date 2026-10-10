package dev.skycraft.combat;

import java.util.Arrays;

/** Capsule/AABB distance and OBB/AABB SAT. Broad bounds alone NEVER constitute a hit. */
public final class AttackGeometry {
    private AttackGeometry() {}
    public record Box(double minX,double minY,double minZ,double maxX,double maxY,double maxZ) {
        double min(int i){return i==0?minX:i==1?minY:minZ;}
        double max(int i){return i==0?maxX:i==1?maxY:maxZ;}
    }
    public static Box bounds(NativeAttack a){
        double[] g=a.geometry();double[] lo={Double.POSITIVE_INFINITY,Double.POSITIVE_INFINITY,Double.POSITIVE_INFINITY},hi={-lo[0],-lo[1],-lo[2]};
        if(a.shape()==1){for(int offset:new int[]{0,7})for(int endpoint:new int[]{0,3})for(int i=0;i<3;i++){
            lo[i]=Math.min(lo[i],g[offset+endpoint+i]-g[offset+6]);hi[i]=Math.max(hi[i],g[offset+endpoint+i]+g[offset+6]);
        }}else for(int i=0;i<3;i++){double r=0;for(int j=0;j<3;j++)r+=Math.abs(g[3+j*3+i])*g[12+j];lo[i]=g[i]-r;hi[i]=g[i]+r;}
        return new Box(lo[0],lo[1],lo[2],hi[0],hi[1],hi[2]);
    }
    public static boolean intersects(NativeAttack a,Box b){
        if(a.shape()==2)return obb(a.geometry(),b);
        double[] g=a.geometry();
        if(distanceAt(g,b,0)<=g[13] || distanceAt(g,b,1)<=g[6])return true;
        double speed=0;
        for(int endpoint:new int[]{0,3}){double d=0;for(int i=0;i<3;i++)d+=sq(g[endpoint+i]-g[7+endpoint+i]);speed=Math.max(speed,Math.sqrt(d));}
        // Lipschitz distance bound prunes continuous motion without inflating the hurtbox.
        // At the subdivision limit reject uncertain tangencies, never invent a hit in the broad AABB.
        return swept(g,b,0,1,speed+Math.abs(g[6]-g[13]),0);
    }
    private static boolean swept(double[] g,Box b,double start,double end,double speed,int depth){
        double t=(start+end)*.5,r=g[13]+(g[6]-g[13])*t,d=distanceAt(g,b,t);
        if(d<=r)return true;
        if(d-r>speed*(end-start)*.5 || depth>=12)return false;
        return swept(g,b,start,t,speed,depth+1)||swept(g,b,t,end,speed,depth+1);
    }
    private static double distanceAt(double[] g,Box b,double t){
        double[] a=new double[3],c=new double[3];
        for(int i=0;i<3;i++){a[i]=g[7+i]+(g[i]-g[7+i])*t;c[i]=g[10+i]+(g[3+i]-g[10+i])*t;}
        return Math.sqrt(segmentDistanceSquared(a,c,b));
    }
    static double segmentDistanceSquared(double[] a,double[] c,Box b){
        double[] points=new double[8];int count=2;points[1]=1;
        for(int i=0;i<3;i++){double d=c[i]-a[i];if(d==0)continue;for(double plane:new double[]{b.min(i),b.max(i)}){
            double t=(plane-a[i])/d;if(t>0&&t<1)points[count++]=t;
        }}
        Arrays.sort(points,0,count);double result=Double.POSITIVE_INFINITY;
        for(int j=1;j<count;j++){
            double l=points[j-1],h=points[j],m=(l+h)*.5,A=0,B=0;
            for(int i=0;i<3;i++){
                double d=c[i]-a[i],x=a[i]+d*m;double edge=x<b.min(i)?b.min(i):x>b.max(i)?b.max(i):Double.NaN;
                if(!Double.isNaN(edge)){A+=d*d;B+=d*(a[i]-edge);}
            }
            double t=A>0?Math.max(l,Math.min(h,-B/A)):m,sum=0;
            for(int i=0;i<3;i++){double x=a[i]+(c[i]-a[i])*t;sum+=sq(Math.max(b.min(i)-x,Math.max(0,x-b.max(i))));}
            result=Math.min(result,sum);
        }
        return result;
    }
    private static boolean obb(double[] g,Box b){
        double[] d={g[0]-(b.minX+b.maxX)*.5,g[1]-(b.minY+b.maxY)*.5,g[2]-(b.minZ+b.maxZ)*.5};
        double[] e={(b.maxX-b.minX)*.5,(b.maxY-b.minY)*.5,(b.maxZ-b.minZ)*.5};
        for(int i=0;i<3;i++){
            double[] world=new double[3];world[i]=1;if(separated(world,g,d,e))return false;
            double[] axis={g[3+3*i],g[4+3*i],g[5+3*i]};if(separated(axis,g,d,e))return false;
            for(int j=0;j<3;j++){
                double[] v=new double[3];v[(j+1)%3]=-axis[(j+2)%3];v[(j+2)%3]=axis[(j+1)%3];
                if(separated(v,g,d,e))return false;
            }
        }
        return true;
    }
    private static boolean separated(double[] axis,double[] g,double[] d,double[] e){
        double distance=0,r=0;for(int i=0;i<3;i++){distance+=axis[i]*d[i];r+=Math.abs(axis[i])*e[i];}
        for(int j=0;j<3;j++){double dot=0;for(int i=0;i<3;i++)dot+=axis[i]*g[3+3*j+i];r+=Math.abs(dot)*g[12+j];}
        return Math.abs(distance)>r+1e-8;
    }
    private static double sq(double v){return v*v;}
}
