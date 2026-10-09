package dev.skycraft.combat;
import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
class SoulRewardMathTest {
 @Test void ineligibleCategoriesNeverEnterDraw(){
  assertEquals(java.util.List.of(SoulRewardMath.Kind.EXPERIENCE),SoulRewardMath.eligible(false,false,false));
  assertEquals(4,SoulRewardMath.eligible(true,true,true).size());
  assertFalse(SoulRewardMath.eligible(false,true,true).contains(SoulRewardMath.Kind.HEAL));
 }
 @Test void progressRemainsFractionalAndCrossesLevel(){
  var a=SoulRewardMath.addExperienceProgress(.1f);assertEquals(0,a.levels());assertEquals(.33,a.fraction(),1e-6);
  var b=SoulRewardMath.addExperienceProgress(.9f);assertEquals(1,b.levels());assertEquals(.13,b.fraction(),1e-6);
 }
}
