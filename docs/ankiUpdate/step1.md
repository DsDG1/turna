# Step 1 详细说明：先让现有链在真机上活下来

> > 上游文档：[README.md](./README.md)。
> Step 1 只做三件事：**真机实测 → 修 staging 引擎不打开 → 修启动维护被跳过**。
> 原则：改动最小、不加新接口、不做数据迁移。修接线的活，不是重构的活。

---

## 0. 范围围栏（先说清楚不修什么）

Step 1 **不碰**这些问题（它们属于 Step 2 以后的 v2 重构，别顺手修）：

| 已知问题 | 归属 |
|---|---|
| 存储页「删除残留文件」点了没真删（幽灵删除） | Step 4 |
| 优化/删除在界面线程同步执行会冻屏 | Step 4 |
| 媒体 GC / VACUUM 不能取消、120 秒超时后反复重试 | Step 4 |
| 崩溃后 previewReady 阶段的 staging 目录不回收 | Step 4 |
| p5c 迁移备份、backups 永不清理 | Step 4/6 |

Step 1 的产出是：**真机实测记录 + 两个小修复 + 回归测试**。不新增引擎操作（用的都是已有的 OPEN_COLLECTION，契约编号不变，不用 bump contract）。

---

## 任务 A：真机全链路实测

### 目的

回答一个致命问题：**现在的导入链在真机上到底能不能跑通。** 代码层核查强烈怀疑不能（见任务 B 的根因链），但所有测试用的都是假引擎，说明不了真机行为。这个问题不回答，后面所有步骤都建立在流沙上。

### 准备

1. **构建**：按现有流水线出 arm64 release 包（`python tool/build_release.py --version 0.4.0-step1`），确认 APK 里带了 anki 动态库（contract 1.11，流水线已做）。
2. **测试包**：一个小的 .apkg（建议 <10MB、带媒体）。可用 `tool/official_anki_spike/generate_fixtures.sh` 生成，产物在 `test/fixtures/anki_official/`。
3. **观察手段**：`adb logcat -s flutter`，盯这些前缀：
   - `[OfficialAnki]`（启动恢复、pending 清理）
   - `[OfficialAnkiStagingManager]`（staging 会话与目录删除）
   - `[OfficialAnkiMaintenance]`（维护任务执行/失败）
   - `[AnkiMedia]`（遗留媒体清扫）
   - 界面上的错误提示文案对应关系在 `lib/application/anki_import/official_import_error_messages.dart`。

### 步骤清单（跑两遍：修复前的基线一遍，修复后的验证一遍）

| # | 操作 | 预期 | 最可能的挂点 | 实际结果（填写） |
|---|---|---|---|---|
| 1 | 冷启动 → 首页 | 正常进入；logcat 出现 due 同步相关日志 | — | 两遍均过。注：due sync 只挂在复习页/练习中心/资料页，首页冷启动本就没有 due 同步日志（收据见「新发现」） |
| 2 | 导入向导选 .apkg → 解析 | 出现预览/映射页 | **本步最可能挂**：报 invalid_state 类错误（根因见任务 B） | **基线：挂**，UI 报 `导入失败，请重试 (invalidState)`，如根因链预测。**修复后：过**，预览页正常出现（牌组已读入、识别练习方式） |
| 3 | 预览、确认字段映射 | 映射页可操作、可保存 | doc 42 已修的 S-c/S-d 若复发需记录 | 修复后：过。映射页可操作（识别 3 类 + 4 类建议确认，正反翻面提示正常）；基线被步骤 2 阻断 |
| 4 | 确认提交 | 提交完成，无 quarantine | live 引擎若也未打开会在此挂（任务 B 顺带修） | 第一版修复包在此挂 `capabilityMissing`（live 会话不存在，见任务 B「真机跟进」），补 requireImporter 引导后**提交完成、课程发布**（CourseProvider 重载×2）。**但提交后主线程卡 ≥5s → ANR 被系统杀**（新发现 #1，Step 4 范围）；重启后数据完好 |
| 5 | 返回课程树 | 官方 anki 章节出现 | | 牌组条目出现在课程管理页（含卡片数与移除入口）。**但点击切换课程后首页仍显示 Turkish**（新发现 #2，未归因） |
| 6 | 进入课时、完成练习 | 正常 | | 被步骤 5 的切换异常阻断，未执行 |
| 7 | 复习一张卡（答案提交） | 队列刷新、计数变化 | | 同上，未执行 |
| 8 | 删除该牌组 | 删除完成 | | 过：移除对话框确认后条目消失。但 source 残留 `pending_cleanup`（新发现 #3，即围栏里 Step 4 的幽灵删除，手动重试同样失败） |
| 9 | 杀进程重启 | logcat 能看到启动恢复逻辑执行 | **本步是任务 C 的观测点**：修复前维护任务不会有任何执行日志 | 基线：重启无任何 `[OfficialAnki*]` 日志（问题证实）。修复后：**本机（vivo V2502A）在应用发生一次 ANR 后系统不再输出该应用任何 flutter 日志**（新发现 #4），`[OfficialAnkiMaintenance]` 行无法采集；改用修复中心 UI 观测——`pending_cleanup` 两次冷启动后仍在，与手动重试失败一致，归因到 Step 4 的 cleanup saga 缺陷而非启动接线（接线正确性由三种情形的单元测试覆盖） |

### 记录与判定规则

- 每步过/不过都写进本文件末尾的「收据」小节，附 logcat 关键行。这是项目惯例（doc 41/42 的收据制），**没跑真机不许填「通过」**。
- 基线跑完的判定：
  - **步骤 2 就挂** → 证实「生产链路跑不通」，任务 B 升级为救命修复，最高优先；「为什么测试全绿没拦住」写进 Step 2 设计文档的教训清单。
  - **步骤 2 过了** → 「跑不通」假设降级为「潜在隐患」，任务 B 变成防御性加固（照做），并在收据里如实记录假设被推翻。
  - 不管哪种，步骤 9 修复前看不到维护日志 → 证实任务 C 的问题存在。

---

## 任务 B：修「staging 引擎没打开就导入」

### 根因链（每一环都已对照源码核实）

1. 导入 saga 在 acquire 之后**立刻**调导入：`official_anki_import_saga.dart` 的 `startStaging` 里，`manager.acquire(stagingPaths)` 拿到引擎后马上 `engine.importPackage(...)`。
2. `acquire()` 的生产分支只做了 spawn：`official_anki_staging_manager.dart:41-49` —— spawn 出的 worker 在 init 里只调了 `engineNew()`（`official_anki_session.dart:707-741`），引擎处于 **Created** 状态（`bridge/src/engine.rs:169`）。
3. 没有任何代码对 staging 会话调过「打开」。全库 `ensureCollectionOpen` 的调用者只有 home due sync（`official_anki_home_due_sync.dart:125`）和复习 gate（`anki_official_review_gate.dart:182`）——都是 live 会话。
4. Rust 侧 `import_package` 要求引擎必须是 Open 状态：`bridge/src/ops.rs`（`require_open`，`engine.rs:392` 对 Created 直接返回 `STATUS_INVALID_STATE`）。
5. **测试为什么全绿**：`acquire()` 的测试注入分支（`staging_manager.dart:36-40`）恰好调了 `openProfile`——生产分支漏掉的正是这一句。假引擎也不模拟状态机，所以「没打开就导入」在测试里不可能失败。

### 改法

把 `openProfile` 从测试分支里搬出来，**两个分支共用**（这样测试走的和生产线走的是同一行代码，同类遗漏不再可能）：

```dart
Future<OfficialAnkiEngine> acquire(OfficialAnkiPaths stagingPaths) async {
  await stagingPaths.ensureLayout();
  final override = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
  final OfficialAnkiEngine engine;
  if (override != null) {
    engine = override;
    OfficialAnkiCompositionRoot.stagingEngine = override;
  } else {
    final session = await OfficialAnkiSession.spawn(
      paths: stagingPaths,
      libraryPath: resolveOfficialAnkiLibraryPath(),
    );
    OfficialAnkiCompositionRoot.stagingSession = session;
    engine = OfficialAnkiSessionEngine(session);
    OfficialAnkiCompositionRoot.stagingEngine = engine;
  }
  await engine.openProfile(stagingPaths); // ← 补的就是这一句，两个分支都过
  return engine;
}
```

两个实现细节：

- `OfficialAnkiSessionEngine.openProfile` 会转发到会话的 `ensureOpen` RPC（`official_anki_session.dart:683-692`），它**已经打开时会吞掉 already-open 错误**、打开后还会跑一次完整性检查（小 staging 库上开销可忽略）——所以这句是幂等的，重复调无害。
- **顺带加固 commitLive**：live 引擎依赖「首页 due 同步或复习 gate 先打开过」。如果用户启动后直奔导入向导，live 引擎可能同样是 Created。在 `commitLive` 发起 `importPackage` 之前同样补一句 `await engine.openProfile(paths)`（幂等，已打开时无副作用）。staging 修了、live 漏了，等于只修一半。

### 真机跟进（施工中发现，已修）

真机第二遍实测在步骤 4 暴露了任务 B 预判的另一半：**live 会话不是 Created 态，而是根本不存在**。due sync 实际挂在复习页 / 练习中心 / 资料页（`anki_review_screen.dart:76`、`play_hub_screen.dart:71`、`profile_quick_actions.dart:41`），首页并不触发——新装应用直奔向导时 `OfficialAnkiCompositionRoot.engine` 为 null，commitLive 报 `capabilityMissing`（importer_not_ready）。修法与文档同一精神（不新增接口）：commitLive 解析不到 engine 时先 `await OfficialAnkiCompositionRoot.requireImporter()`（与 due sync 同路，自带单飞），再重取 engine；已有 `openProfile` 行随后正常打开。

### 测试方案

1. **顺序断言测试**（核心）：做一个「严格假引擎」——记录调用顺序，`importPackage` 若发生在 `openProfile` 之前就抛 invalidState。通过 `debugStagingEngineOverride` 注入，跑完整 startStaging → commitLive 流程。这个测试如果在修复前跑，会直接红。
2. **结构保障**：修复后 open 调用在 if/else 之外，现有 override 分支的测试自然覆盖到生产用的同一行。加一个断言「acquire 返回前必调 openProfile」。
3. **Rust 侧钉契约**：bridge 的 cargo 测试里如果没有「Created 状态调 import_package 必须返回 INVALID_STATE」的用例，补一个——把引擎状态机的约定钉死在两边。
4. **诚实说明**：生产分支的完整覆盖只有真机能给（spawn 真隔离线程 + 真动态库），这正是任务 A 第二遍跑的意义。

---

## 任务 C：修「启动时维护任务被跳过」

### 根因链

1. 冷启动只初始化了只读目录库，**没有创建引擎会话**：`main.dart` 里 `await OfficialAnkiCompositionRoot.initializeReadOnlyLocator()`（`official_anki_composition.dart:232-244`，只开 catalog），随后 `main.dart:131` 起 `OfficialAnkiStartupRecovery().run()`。
2. `run()` 里的判断 `if (engine != null && paths != null)`（`startup_recovery.dart:38-39`）——`engine` 取自会话（`official_anki_composition.dart:49,287-296`），此刻会话还不存在 → **null → 整个修复执行器被跳过**（census、未完成导入恢复、pending 清理、维护任务 `runPending`，全在 `official_anki_repair_executor.dart:29-79` 里）。
3. 会话真正被创建要等到首页 due 同步（`official_anki_home_due_sync.dart:115` 的 `requireImporter`）——那时启动恢复早就返回了。
4. 细节：`run()` 里 reanchor 和 `retryPendingOfficialCleanups` 仍然无条件执行（`startup_recovery.dart:58-71`），后者在有 pending_cleanup 时会懒建引擎（`uninstallOfficialSource` → `_resolveOfficialEngine`，`anki_deck_manager.dart:255,498-503`）——但那已经发生在维护任务被跳过**之后**，救不回来。

**用户可见后果**：删除牌组时入队的媒体 GC / VACUUM 永远不会自动执行，只有手动点「优化数据库」才跑（`official_storage_optimize_service.dart:63-69`）。这就是「删除后空间不回来」的直接原因。

### 改法：「有活才开引擎」

不是无条件在启动时创建引擎（那会拖慢所有用户的冷启动，包括从没用过 anki 的用户），而是先查账、有活再开：

```dart
// OfficialAnkiStartupRecovery.run() 里，替换原来的 engine-null 判断
final hasMaintenanceWork =
    _hasPendingMaintenanceJobs(catalog) ||   // anki_maintenance_jobs 有 pending/retry_wait
    _hasPendingCleanupSources(catalog) ||    // anki_sources 有 pending_cleanup
    _hasUnfinishedAttempts(catalog);         // anki_import_attempts 有未完成
if (hasMaintenanceWork) {
  await OfficialAnkiCompositionRoot.requireImporter(); // 和首页同步同一条路
}
final engine = OfficialAnkiCompositionRoot.engine;
if (engine != null && paths != null) {
  // ……原有修复执行器逻辑不动
}
```

三个查账都只读已打开的 catalog，代价是三条轻查询。没有活的用户走原路（不建引擎、不拖慢启动）；有活的用户引擎建好后维护任务真正跑起来。已有的 maintenance lease（`tryAcquire`）会防止和手动优化并发，保持不动。

### 施工中修掉的两个连锁接线缺陷（实现任务 C 时暴露）

原 `engine != null` 分支在生产从未可达，所以它内部还埋着两个只有接通后才会发作的缺陷，本次一并修掉（仍是接线级改动，无新接口）：

1. **lease 自锁**：`startup_recovery` 持有 `startup-recovery` lease 时，repair executor 内部的 `runPending` 用随机新 token 再 `tryAcquire` 会被自己人的未过期 lease 拒绝（返回 0、任务全部跳过）。修法：`OfficialAnkiMaintenanceRunner.runPending` 增加可选 `leaseOwnerToken`，嵌套调用方复用外层 lease；独立调用方（手动优化）默认随机 token，互斥语义不变。
2. **profileId 没传**：`startup_recovery` 调 `OfficialAnkiRepairExecutor.run` 时不传 `profileId`，executor 用默认 `'profile-default-01'` 查任务表；生产里恰好同值所以从未暴露，换 profile 即静默查不到活。修法：显式传 `profileId: profileId`。

**否决掉的备选**（记录下来防止反复）：
- 挂到 home_due_sync 打开引擎之后回调——维护任务被绑死在 due 同步的成败上，而且开引擎的入口不止一个（复习 gate 也会开），挂一处漏一处。
- 无条件启动即开引擎——为少数有活的用户给所有人加冷启动成本。

### 测试方案

1. 现状（已核实）：`OfficialAnkiStartupRecovery` **零测试覆盖**——全库引用只有 `main.dart` 和它自己的定义；唯一相关的 `official_anki_census_repair_test.dart` 只断言白名单常量，不跑 `run()` 流程。引擎为 null 的路径从未被任何测试执行过，**这正是它漏网的原因**。本次新写的测试就是这类级的第一个覆盖。
2. 给 `OfficialAnkiStartupRecovery` 加一个可注入的 `ensureEngine` 回调（默认实现 = `requireImporter`），测试里：
   - catalog 无待办 + 引擎 null → 断言 `ensureEngine` **没被调用**（保启动成本）；
   - catalog 有待办 + 引擎 null → 断言 `ensureEngine` 被调用、维护任务执行、job 标记 completed；
   - 引擎已有（override）→ 行为与现在一致（回归）。

### 注意事项

- `runPending` 的自动模式带阈值（freelist 低于阈值会跳过 VACUUM）——**验收标准是「任务执行了且有日志」，不是「文件变小了」**。真机字节收据按项目惯例记 `deferred`，不填假数字。
- 大库上 GC/VACUUM 可能超 120 秒 RPC 超时然后进重试——这是**已知且继承**的限制，Step 1 明确不修（见范围围栏），只在收据里记录是否观察到。

---

## 执行顺序

```
A（基线实测，修复前）
 └→ 判定：步骤 2 挂？ → B 是救命修复（最高优先）
                        不挂？ → B 是防御加固（照做）
B（staging + commitLive 打开修复 + 测试）
C（启动维护接线修复 + 测试）
A（第二遍实测，验证修复）
 └→ 回填收据到本文件末尾
```

## 验收清单

- [x] 基线实测记录完整（含 logcat/UI 证据；9 步中步骤 6/7 被新发现的课程切换异常阻断，如实记录）
- [x] staging 打开修复落地，严格假引擎顺序测试红→绿（红：`official_anki_open_before_import_test.dart` commitLive 用例修复前抛 `import_before_open`；全套跑亦复现红）
- [x] commitLive 前的幂等打开落地（含真机跟进的 requireImporter 引导）
- [x] Rust 侧「Created 调导入必失败」契约测试存在（新增 `ops.rs::import_on_created_engine_is_invalid_state`，实机 cargo test 通过）
- [x] 启动维护接线修复落地，三种情形的测试齐（`official_anki_startup_recovery_test.dart`：无活不开引擎 / 有活开引擎且 job 完成 / 引擎已在则回归）
- [ ] 第二遍实测：导入→复习→删除→重启全过，重启时能看到 `[OfficialAnkiMaintenance]` 执行日志 —— **部分完成**：导入→删除→重启过；复习被切换异常阻断；维护日志被系统日志静默吞掉无法采集（改用 UI 侧证据，见收据）
- [x] 现有测试套件无新增失败（全套 `flutter test` 与干净树逐条 diff：零新增；`flutter analyze` 的 2 error + 1 warning 均为本分支存量损坏测试文件；Rust 桥测试零新增失败）
- [x] 收据回填，真机字节数据如实标 deferred（本次未观测到可记录的空间回收字节，标 deferred）

## 真机新发现清单（移交 Step 2 设计文档的教训/待办）

1. **提交完成后 ANR**：commit 成功、课程发布后主线程在 APK 内嵌原生库中忙跑 ≥5s（ANR dump：Input dispatching timed out 5001ms），进程被杀。发生在所有 Step 1 修复代码路径之后，符号化留待 Step 2；与围栏里「界面线程同步执行冻屏」（Step 4）同族。
2. **课程切换不生效**：课程管理页点击 anki 牌组条目后回到首页仍显示 Turkish 课程。未归因（疑 scope 持久化或 anki 课程的 sections 视图）。
3. **pending_cleanup 无法完成**：删除牌组后 source 停在 `pending_cleanup`，启动自动清理与修复中心手动重试**同样失败**——围栏里 Step 4 幽灵删除问题的真机实锤。
4. **vivo 日志静默**：应用发生一次 ANR 后，该应用后续进程的 flutter 日志完全不再输出（logcat 全 buffer 为空），阻碍步骤 9 的日志验收。换设备/换日志通道（文件日志）应列入 Step 2。
5. **强杀后 prefs 丢失**：每次 force-stop 后冷启动重现 onboarding（SharedPreferences 未持久化）。影响含 scope 在内的偏好记忆，疑与本机存储/进程被杀时机有关。
6. **测试为什么全绿（补充任务 B 根因链第 5 条的真机版）**：假引擎注入分支恰好调了 openProfile；而 live 会话「由谁先打开」从未有测试覆盖——真机上 due sync 的挂载点（复习页/练习中心/资料页）与「首页会开引擎」的假设不符。Step 2 设计入口测试时应以真实挂载点为准。

## 工作量估计

| 任务 | 估计 |
|---|---|
| A × 2 遍 | 0.5~1 天/遍 |
| B | 0.5~1 天 |
| C | 1~2 天 |
| **合计** | **3~5 天** |

---

## 收据（施工后回填）

环境：Windows 构建宿主 + 真机 vivo V2502A（Android 16，arm64-v8a，serial `10AF9U0P9P002DJ`）。
产物：`dist/turna-v0.4.0-step1-baseline-release.apk`（修复前基线）、`dist/turna-v0.4.0-step1-release.apk`（含全部 Step 1 修复）。两包均校验内嵌 `lib/arm64-v8a/libturna_anki.so`、无多余 ABI。构建注记：`build_release.py` 内的 `flutter pub get` 在本机对镜像在线解析卡死，改用 `pub get --offline` 后按脚本同步骤手动执行（build_runner → course validate/lint → arm64 release apk → .so 校验 → 归档 dist）。测试夹具：`test/fixtures/anki_official/packages/01-basic-unicode.apkg`（56.66 KB）经系统选择器导入。测试机数据在基线/验证前各 `pm clear` 一次。

| 日期 | 事项 | 结果 | 证据（commit / logcat 摘录） |
|---|---|---|---|
| 2026-08-31 | 基线实测 | 步骤 1 过；**步骤 2 挂**：UI `导入失败，请重试 (invalidState)`；步骤 9 重启无任何 `[OfficialAnki*]` 日志 | 基线 APK + UI dump（向导选择步骤条 + 错误文案）；`logcat -d -s flutter` 全量无 OfficialAnki 行。「跑不通」假设证实，任务 B 按救命修复执行 |
| 2026-08-31 | 任务 B（staging + commitLive 打开） | 落地 + 红→绿验证 | `official_anki_staging_manager.dart` acquire 双分支共用 openProfile；`official_anki_import_saga.dart` commitLive 幂等 open + requireImporter 引导。测试 `test/application/anki_official/official_anki_open_before_import_test.dart`（严格假引擎）：修复前 commitLive 用例红（`OfficialAnkiException(invalidState … import_before_open)`），修复后绿；全套跑在干净树上同样复现红 |
| 2026-08-31 | 任务 B（Rust 契约钉死） | 补齐 | `native/turna_anki_core/bridge/src/ops.rs` 新增 `import_on_created_engine_is_invalid_state`（Created → INVALID_STATE；open 后同文件变 PACKAGE_INVALID 证明门是状态机）。`cargo test --lib import_on_created_engine` 通过 |
| 2026-08-31 | 任务 C（启动维护接线） | 落地 + 三情形测试 + 两处连锁缺陷修复 | `official_anki_startup_recovery.dart` 有活才开引擎（`ensureEngine` 可注入）；`official_anki_maintenance.dart` runPending 支持复用外层 lease；`official_anki_repair_executor.dart` 透传 profileId。测试 `official_anki_startup_recovery_test.dart`：无活 ensureEngine 不调用且无 lease 泄漏 / 有活调用且 job → completed / 引擎已在则回归不变，3/3 过 |
| 2026-08-31 | 验证实测 | 步骤 1–5、8 过（4 含 ANR 新发现，5 含切换异常）；6/7 被切换异常阻断；9 日志被系统静默，UI 侧证据见新发现清单 | 第一版验证包在步骤 4 挂 `capabilityMissing` → 补 requireImporter 引导重建后通过：预览/映射/提交/课程发布（`CourseProvider.reloadCourse` ×2）/移除牌组均达成；ANR dump：`Input dispatching timed out … Waited 5001ms`；维护任务字节回收未观测，**deferred** |
| 2026-08-31 | 回归核验 | 零新增失败 | 全套 `flutter test`（1726+ 过 / 34 失败）与干净树（同 34 失败 + 我的两个新测试的红）逐条 diff：**「仅带改动」为空**。`flutter analyze`：2 error + 1 warning 全在存量损坏测试文件（`anki_import_execution_plan_test.dart`、`official_anki_host_ffi_test.dart`，干净树同样加载失败）。Rust `cargo test --lib`：干净树 10-11 个宿主环境存量失败，带改动相同集合，我的新用例不在其中 |

### 遗留与移交（非 Step 1 范围，勿在此修）

- 步骤 6/7（课时练习、复习提交）因课程切换异常未走完——待发现 #2 归因后在 Step 2 补真机用例。
- `[OfficialAnkiMaintenance]` 启动执行日志的真机采集受发现 #4 阻塞；接线正确性以三情形单测 + 任务 C 代码路径审查为准，日志采集通道改造（文件日志/另一台设备）列入 Step 2。
