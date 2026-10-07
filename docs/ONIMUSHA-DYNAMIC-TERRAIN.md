# 动态地形流送修复 / Dynamic terrain streaming

2026-10-07，仅适用于已验证的 OnimushaWotS 01.000.001 / TDB82。
MOD制作：LCPD15/LCPD拉灯。

用户已确认铁傀儡能正常站立和寻路，原先13/14边界不再闪断。
随后报告另一处走远后接管中断、返回原位置恢复。此次日志中 world/observed_area
始终为 stage:0:area:13，epoch 为1791226399，没有 Stage transition。
14次地形转换超过 `Collision voxelization exceeds bounded work budget`，留下旧覆盖，
之后4次 `Minecraft foot/body/support outside verified query` 归还原游戏控制。
另有2次 Waiting for Minecraft world 短暂状态，本次不把这些独立原因宣布解决。

在接管关闭、用户位于安全处时，用只读原生区域查询重新捕获故障位置：3494个三角面，
没有 box/sphere/capsule；完整格边界查询得到5107个三角面。没有移动角色或模拟输入。
旧算法离线重放两份真实数据均在约240ms时触及1200万次工作上限，转换失败。

## 修改

- 把三角面的三维包围盒遍历改成沿主法线方向的表面遍历，保留最终SAT碰撞检测。
  保留1200万次工作上限、数量上限和完整批次规则，不截断地形来换取成功。
- 用双精度计算区域/体素边界和中心，避免远处MC坐标使边界epsilon消失。
- Lua查询与8×8×8地形格对齐，并向外多查0.002格。格边缘不再用未查询区域覆盖旧地面。
- 单一后台工作线程只持有数值副本，完成CPU转换；游戏线程检查会话再一次性提交整批。
  工作票据、发布序号、MC整批接收确认分开处理。等待时继续使用旧的完整碰撞范围。
- 角色移动8格或垂直2格便预取新范围；范围自动随当前位置移动，不需要为这次路径增加AreaID别名。
  真正换地图仍按原有隔离规则处理，不能把不同地图或尚未迁移的存档区块无条件拼在一起。

## 验证和交接

3组原生CTest通过：IPC/完整批次、真实DLL Lua接口和渲染回归。
体素逐格与不裁剪的暴力SAT参考实现比较通过，覆盖斜面、三个主轴、负坐标、远坐标及退化面。
真实DLL测试验证异步发布一次、失败保留旧批次、epoch变化丢弃后台旧结果。
23个Lua回归脚本通过（两个边界断言随完整格查询更新后分别复测通过）。
真实3494/5107面离线重放均完整成功，最终一轮耗时约174/233ms，转换已移到后台。
该耗时是CPU任务总耗时，不是游戏主线程耗时，也不代表已在游戏内通过跨区域复测。
Fabric JAR没有改动；铁傀儡前一轮用户通过结果保留。

证据：`logs/dynamic-area-20261007-194446/`，包含原始状态、只读捕获、旧版失败重放、
CTest/Lua结果。原生几何捕获仅保存在本机日志，不包含在分发包。
世界完整备份：`runtime/test-backups/before-dynamic-terrain-20261007-200301`，64文件哈希验证。
未改动MC存档、背包、区域映射和既有方块。临时只读捕获脚本随正式Lua安装被移除。

待测：开启接管后沿之前断联路线往返，并继续走过更远位置；检查控制连续、碰撞、
方块保留和铁傀儡站立。若失败，先保存状态中的具体原因，不能一律当成AreaID切换。

English: The reported loss was reproduced as terrain packing exhaustion within the same
area and epoch. Full-cell native queries, conservative surface rasterization and a bounded
background numeric worker now refresh terrain as the player travels. Publication and
consumer acknowledgement remain distinct. Offline native/Lua regressions passed; the
affected in-game route still needs user acceptance. Other maps keep their isolation.
