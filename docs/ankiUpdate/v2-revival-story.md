# v2 复活记：幽灵闪退的根因、猎杀与复盘（2026-09-01 ～ 2026-09-02）

> 本文是 [ADR 0044](../decisions/0044-anki-v2-revival.md) 的叙事版：一次跨越两天的真机抓捕，如何证明「杀死 v2 的不是架构，而是一个 UI 层死循环 bug」。
> 证据与工具存于 `logs/crash-hunt/`；工程收据见 [test/BASELINE.md](../../test/BASELINE.md) 当日条目。

---

## 起因

**v2 的死刑判决书里，真正的行刑者是「跑不了真机验证」。**

2026-09-01，Anki 底座 v2（ADR 0043）被宣告整体失败。判决列了四条，但核心链条只有一条：Step 4 的 C3 真机强杀矩阵（K1–K14）永远跑不绿 → 发布门禁永远不满足 → 生产 flag 永远不敢翻 → 整条链「未交付」。

而矩阵跑不了的原因，当时被记作「真机不可达/未执行」。真相是：**每一轮真机导入测试，都会在完成页卡死、被系统 ANR 处决**。K13（大库期间 UI 可交互、无 ANR dump）这一行结构性不可能变绿——app 活不到验证那一刻。

这个幽灵从 Step 1 时代就在场（step1.md 真机新发现 #1「提交完成后 ANR」），此后一路被误判：
- 怀疑**字体**（系统字体切换工程做了，幽灵照旧）；
- 怀疑**导入文件与投影**（数据检查全部完好——这个观察是对的，它后来成为破案关键之一）；
- 怀疑**主线程同步 SQLite / 重计算**（2026-09-01 的 PR1 止血据此施工——诊断部分正确，但不是本案元凶）。

幽灵的特性完美：**只在真机出现（测试全绿）、只在导入完成态触发（平时无恙）、死法是系统处决（无 tombstone，像闪退）**。它陪葬了 v2。

## 经过

### 第一幕：定性（2026-09-01 深夜）

从设备拉回 6 份 ANR trace + bugreport，逐一核对：

- 6 次死亡**全部**是 `reason=ANR, Input dispatching timed out (5001ms)`，零 SIGSEGV/tombstone——「闪退」实为卡死 5 秒后被杀；
- 主线程 `state=R`、PC 落 `[anon:dart-code]`，累计 CPU 高达 125 秒/几分钟进程寿命——主线程在玩命跑 Dart；
- 触摸点坐标全部落在屏幕底部 20%——正是「开始学习」「导入确认」这些按钮。

### 第二幕：第一次围捕与 PR1 止血（错诊的一半）

顺「主线程忙」这条线，代码侧确认了三类真实存在的主线程重活（catalog 同步 sqlite3、投影/词表/回执的纯 Dart 重计算、build 内查库），全部下沉后台（PR1：`Isolate.run` + `commitReceipt` 下沉 worker + 四页面防抖；全量 1766 过/35 失败全为预存）。

**但真机复测：照卡。** 这一步的价值不是破案，而是排除了最大的一片嫌疑区。

### 第三幕：监控抓到「不可能的矛盾」（2026-09-02 夜）

带着监控脚本（VM 服务探针 + 堆曲线）上真机。冻结发生后拿到三组互相「矛盾」的读数：

1. `top -H`：主 PID 线程烧 93% CPU，**但** VM 服务毫秒级响应——烧 CPU 的若真是卡死的主 isolate，服务不可能这么快；
2. 冻结中拉取 VM 时间线：25 秒窗口内 root isolate 做了 **2475 次新生代 GC（≈100 次/秒）**——不是纯计算循环，是 **1.6GB/s 的短命对象分配风暴**（堆曲线「平稳」是被每秒百次 GC 造出的假象，此前误导了两轮诊断）；
3. 分配风暴 + 服务可响应 ⇒ 循环必然频繁经过安全点 ⇒ **debug 模式的 getStack 可以截到它**。

### 第四幕：当场抓获（带名字）

debug 构建 + 每秒一次符号化栈采样，用户复现、冻结后不碰屏幕。连续采样全部命中同一组帧：

```
findAncestorWidgetOfExactType ← AutoRouter.of ← context.router ← <匿名闭包> ← _microtaskLoop
maybePop ← _callPopInvoked ← onPopInvokedWithResult ← maybePop ← …
```

对回源码（`anki_import_screen.dart`），死循环闭环：

```dart
PopScope(
  canPop: false,                          // ① 写死，永不放行
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    final leave = await _confirmLeave(...); // ② Completed 态秒回 true，无弹窗
    if (leave ...) context.router.maybePop(); // ③ 再 pop → 被①挡回 → 回调再触发 → ∞
  },
)
```

每一轮乒乓 = 一次微任务 + `context.router` 全树祖先查找 + 路由机器——就是分配风暴的源头。日志永远停在 `body received` 的原因也水落石出：那是 `setCourseScope` 的最后一条日志，之后 `maybePop` 进风暴，再无任何输出。

用户实测的三条规律逐一对上：**开始学习/完成**（要 pop 向导）→ 死；**查看牌组**（push 不 pop）→ 活；**取消并清理**（最终也 pop）→ 死。

讽刺的注脚：`ai_api_config_page.dart` 里早就躺着同一颗雷的修复与注释（"Unconditional pop bypasses canPop so this callback doesn't re-enter"）——向导页漏拆了。

## 结果

**修复**（2026-09-02，真机实测通过）：

- `anki_import_screen.dart` 四处离开路径（PopScope 回调 / 返回箭头 / 完成按钮 / 开始学习）`maybePop` → `context.router.pop()`（直接 Navigator.pop，绕过 canPop 闸门）；
- 守卫测试 `anki_import_pop_loop_guard_test.dart`：锁死该文件内不得出现 `.maybePop(` 调用；
- `flutter analyze` 零问题；失败仅剩两项已定性的预存（staging schema 断言过时、controller 引用已删调用链）。

**决策**（ADR 0044）：v2 复活。依据即本文：C3 不可执行的元凶已消灭，v2 架构从未在真机上被证伪；host 落码与 31 个用例完好。剩余执行线：

- R1 重建 arm64 `libturna_anki.so`（现网 .so 旧于 op 41/42——日志里 `[OfficialAnkiV2] unimplemented` 为证，C3 硬前置）；
- R1.5 v2 链自身 `upsertCardBatch` 每卡同步主 isolate 写须下沉（本轮抓捕带出的新隐患，K13 前置）；
- R2 C3 矩阵 → R3 C4 定标 → R4 观察期 + 翻 `v2ImportChain` → Step 4 关闭；
- 原「PR2 catalog 迁 drift」作废，由 v2 D4 删表终局吸收。

**留给下次的两条教训**：

1. 「堆曲线平稳」不等于没有分配风暴——每秒百次 Scavenge 会把曲线熨平。定性循环先看 GC 频率（VM 时间线的 `CollectNewGeneration` 计数），再看堆。
2. 「服务响应快 + CPU 满」的组合不是矛盾，是礼物：它说明循环让出了安全点，getStack/debug 工具必然能截到名字。别急着换 profile/符号化硬啃。

## 附：证据与工具索引（`logs/crash-hunt/`）

| 文件 | 内容 |
|---|---|
| `br/FS/data/anr/anr_*` | 2026-09-01 六份 ANR trace（定性：全部 reason=ANR） |
| `transparency-26949.jsonl` | 4.3 小时会话应用日志（46 次 reload、5+ 来源、最后一次冻结） |
| `monitor-run*.log` | VM 服务探针曲线（rpc 延迟劣化点 = 冻结起点） |
| `timeline-frozen.json` | 冻结中拉取的 VM 时间线（2475 次 Scavenge/25s 的实锤） |
| `stackloop.log` / `stackloop-console.log` | 每秒符号化栈采样（元凶帧的当场抓获） |
| `db-*` / `libapp-profile.so` | 冻结进程的库快照与 AOT 载荷（佐证：冻结期间零 DB 写入） |
| `monitor.js` / `monitor-auto.js` / `stackloop.js` / `prepare-timeline.js` / `dump-now.js` | 可复用取证工具（已纳入 C3/C4 常设设施，见 ADR 0044） |
