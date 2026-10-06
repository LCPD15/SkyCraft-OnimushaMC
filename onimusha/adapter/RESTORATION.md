# 接管停止与脚本重置 / Takeover release and script reset

停止接管会恢复本次接管记录的输入字段、角色绘制与原相机 FOV，并回读确认。
恢复失败时保留原 owner、原值及尚未完成的记录；脚本仍在运行时逐帧重试，完成前不再接管。
即使已经从阶段 C 降级到只读阶段 A，Script Reset 也会对这些已有待恢复记录再尝试一次。
冷启动阶段 A 没有接管记录，因此不会新增输入、绘制或 FOV 写入。

SDK setter 永久失败、原 owner 失效或 Lua 在重试完成前被销毁时，不能保证恢复成功。
Reset 的最后一次恢复失败仍显示为 pending；旧 Lua 状态销毁后无法继续这份记录的重试。
本补丁不在全局持久化 managed 指针，不能据此声称跨脚本重置可继续恢复。
看到恢复错误时应先在当前脚本中关闭接管并等待 pending 清零，再执行 Reset；无法清零时需正常退出游戏。

Release restores the captured input fields, draw states and original camera FOV with readback.
Failed records retain their original owners and values and are retried while the script lives;
takeover stays blocked until restoration finishes. Reset attempts owned pending restoration even
after a C-to-A downgrade. A cold stage-A run owns no changes and performs no such writes.

A permanently failing SDK setter, invalid owner or Lua teardown before successful recovery
prevents a restoration guarantee. The final failed reset attempt remains pending; its retry
ledger ends with that Lua state. No managed pointers are persisted globally by this patch.
Disable takeover and allow pending recovery to finish before Reset. If it cannot finish, close
the game normally rather than treating reset as proof that the original state was restored.

`tests/reset_restore_regression.py` executes the production callback and restore helpers in Lua
5.4, covering cold stage A, input-only/FOV-only/combined pending restoration and permanent failure.

活动相机同步只写六项：实际虚拟相机 Transform 的位置、旋转和 FOV，以及实际
controller CurrentParam 的 EyePos、LookAtPos、FOV。先确认实际 TARGET 枚举、主相机
component 身份、controller/virtual 身份与 operator/current param 身份；虚拟相机不能
与主相机共用 camera 或 Transform。原值以数字深拷贝保存在 exact-owner ledger，
每项写后回读，失败记录按上述恢复规则保留并重试。相机 owner 改变时先恢复旧 owner，
下一帧再捕获新 owner。主相机与活动相机矩阵的缓存差只记录诊断，不作为即时失败门槛。
不主动调用整段 camera update、reflect 或注册接口。真实 UI 转向时序仍需游戏实测。

Active-camera synchronization owns only six writes: the exact virtual Transform position,
rotation and virtual FOV, plus the exact controller CurrentParam EyePos, LookAtPos and FOV.
The actual TARGET literal, primary component, controller/virtual and operator/current-param
identities must agree before any write; virtual and primary cameras/transforms cannot alias.
Numeric deep copies and exact owners are retained, each write is read back, and failed restore
records stay pending. An owner change restores the previous owner before a later recapture.
View-matrix cache lag remains diagnostic rather than an immediate failure gate. No whole
camera update, reflection or registration method is called proactively. Visible
world-UI rotation timing still requires a physical game test. Release can briefly restore the
captured camera position before the engine computes its next normal camera update.

`tests/active_camera_sync_regression.py` exercises the production ownership/sync/release
helpers, actual fail-open and reset callbacks with only fixed-SDK-shaped interfaces exposed.

相机时序观察最多安装八个精确签名的被动钩子。安装尝试与真实调用计数分开；
实际函数地址必须非空、非零，并去重。钩子参数只作原始地址整数比对，未确认的
struct 返回参数布局不构造 managed 对象、不解引用。阶段 A 不安装；停止接管后
只累计 Lua 计数。接管期间每 30 帧、每钩子每相位最多采样一次，保留最近 64 条。
钩子只读既有主相机 Transform/FOV 和已捕获 param.FOV，不遍历 manager/operator，
不在可能持锁的反射回调内读取矩阵。矩阵仍在原 application phase 中采样。
pre 不跳过原方法，post 原样返回；该观察本身不增加相机写入或修复 UI 转向时序。

The passive camera-order observer installs at most eight exact-signature hooks. Attempted
installation is distinct from natural invocation counts; function pointers must be non-null,
nonzero and unique. Hook slots are compared as raw pointer numbers, without constructing or
dereferencing managed wrappers for an uncertified struct-return ABI. Cold stage A installs
nothing; inactive callbacks only increment Lua counters. Active sampling occurs at most once
per hook/phase every 30 frames and retains 64 records. Hook reads are limited to existing
primary Transform/FOV and captured param.FOV; manager/operator traversal and matrix getters
remain outside potentially locked reflection callbacks. Pre never skips the original method,
and post returns its original result. This observer adds no camera writes and does not itself
fix world-UI rotation timing. `tests/camera_hook_order_regression.py` covers the production
hooks, real-pointer-shaped userdata, nested pairing, bounded cadence and application markers.

实际 B274 顺序记录证明 app.CameraManager.lateUpdate 内会把 MC 的相机朝向/FOV
覆盖为原生值。因此该唯一、实际调用过的 outer post 现在可重放上一成功 tick 缓存的
MC 相机姿态。缓存仅在主相机三项与已有虚拟相机六项写入和回读全部成功后提交，
保存数字深拷贝、确切 owner、frame、epoch 和传送序号；首次接管无缓存时不重放。
post 必须重新通过最新 bridge readiness/watchdog、连接、renderer、MC alive/ack
和既有完整相机身份链；不允许在 post 捕获新 owner。不重复 tick、输入、移动、血量
或地形处理，也不调用原游戏整段相机更新。fail_open 先清缓存，再按原 ledger 恢复。
正常停止接管时主相机原有恢复语义仍仅恢复 FOV，其位置/旋转由恢复后的原生更新继续计算；虚拟
六项保持精确原值恢复。真实世界空间 UI 是否在该 post 之后更新，仍待实测确认。

Observed B274 order proves that app.CameraManager.lateUpdate overwrites MC camera direction
and FOV. Its naturally observed outer post may now replay the last successfully certified MC
camera pose. The cache is committed only after primary three-field and existing owned six-field
writes/readbacks all succeed. Numeric deep copies retain exact owners, frame, epoch and teleport
sequence. No first-activation cache means no replay. Fresh bridge readiness/watchdog, connection,
renderer, MC alive/ack and the complete existing owner chain must agree; post cannot capture a
new owner. Replay does not repeat tick, input, movement, health or terrain processing, or call a
whole engine camera update. Fail-open clears the cache before existing ledger restoration.
Normal release retains the primary's existing FOV-only semantics; native updates recompute its
position/rotation after release. The virtual six fields retain exact-value restoration. Whether
world-space UI actually calculates after this post remains a physical acceptance test.
`tests/camera_post_replay_regression.py` executes the production post, gate, nine-write helper
and recovery paths; it does not implement a duplicate replay algorithm.

outer post 每次实际写入前还必须完整捕获该帧原生更新后的 primary position、quaternion
和 FOV 数字快照，并核对原 component、GameObject 有效性及确切 Transform 身份。
每项写前记录 attempted；九项写入／回读成功后立即丢弃这个单次事务，不长期保存成功帧姿态。
若任一 primary 或虚拟六项写入／回读失败，fail_open 恢复该次 primary 三项原值。
恢复失败的记录保留待以后 fail_open／reset 重试，阻止新的接管与快照，不写替换 owner。
事务恢复期间，仅同一 primary 的旧 visual FOV ledger 被跳过；整个事务确认恢复后才释放它，
避免初始 FOV41 在重试时覆盖本帧原生 FOV43。无事务的正常 F10 恢复语义不变。
无效／已替换的旧 GameObject/Transform 只能保留 pending，无法安全恢复时需要干净重启。

Before an outer-post write, capture numeric deep copies of that frame's post-native primary
position, quaternion and FOV, verifying the exact component, valid GameObject and Transform.
Mark each attempted write before calling it. All nine writes/readbacks succeeding discards this
per-attempt transaction immediately; successful frame poses are not a permanent release ledger.
A primary or owned-six failure rolls back all attempted primary fields. Failed rollback records
remain pending for fail-open/reset retry and block new capture/takeover without writing a
replacement owner. Only the same primary's older visual-FOV ledger is deferred, and it is cleared
only when the entire transaction restores successfully. This prevents initial FOV41 from
overwriting post-native FOV43 during a partial retry. Normal F10 release remains unchanged.
Invalid/replaced old GameObjects or Transforms remain pending; unrecoverable owners require a
clean restart. The production regression covers silent and throwing setters, failure after a
partial write, both primary and owned-six failures, exact-owner replacement, disabled-stage retry,
and native FOV43 differing from initial FOV41.

引用保留按固定版本Lua绑定处理。该版本 `add_ref(force=true)` 对已经由Lua跟踪的对象不会继续累加引用；普通userdata的GC负责归还。这里不使用 `add_ref_permanent`，也不在丢弃单次快照时手动 `release` 仍由其他ledger引用的对象。升级SDK需重查这一行为。证据：[固定版本Sdk.cpp](https://github.com/praydog/REFramework/blob/b6baf6b406efc65e077b99cb4d9ad25b0a0a9095/src/mods/bindings/Sdk.cpp#L47)。
