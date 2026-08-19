# P4R3 / P5-B 实施手册

> 文档代号：P4R3-HOWTO  
> 日期：2026-08-18  
> 本文件补充 [`16`](./16-p4r3-production-gate-and-p5b-prep-plan.md) 的「做什么」和 [`18`](./18-p4r3-audit.md) 的「验了什么」。这里只写 **怎么改、怎么跑、怎么才算过**。  
> 口径以 `18` 为准。`17` 和 `artifacts/p4r2/final-decision.txt` 若再次写 GO，必须能用本文命令当场复算；复算失败则 GO 作废。

## 0. 硬约束（全程）

```text
默认 flag 保持 false，只在内部 APK 用 --dart-define 打开
不改 AnkiReviewRoute / AnkiImportRoute 生产默认
不写 LegacyAnkiMigrationFlags.cutoverEnabled = true
不删 Legacy，不伪造 revlog
不把 Device B 缺失写成通过
不把 Host 测试通过写成设备通过
```

内部 APK 的 dart-define（**仅** debug / 内部 release，禁止写进默认 `fromEnvironment`）：

```bash
DEFINES=(
  --dart-define=TURNA_OFFICIAL_ANKI_ENGINE=true
  --dart-define=TURNA_OFFICIAL_ANKI_IMPORT=true
  --dart-define=TURNA_OFFICIAL_ANKI_CATALOG=true
  --dart-define=TURNA_OFFICIAL_ANKI_RUNTIME=true
  --dart-define=TURNA_OFFICIAL_ANKI_PLATFORM=true
  --dart-define=TURNA_OFFICIAL_ANKI_RENDERER=true
  --dart-define=TURNA_OFFICIAL_ANKI_SCHEDULER=true
  --dart-define=TURNA_OFFICIAL_ANKI_DIAGNOSTICS=true
  --dart-define=TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS=true
)
```

设备：`3B15AG00FPB00000`（Device A，PLG110，API 36，arm64）。包名：`me.dsdogs.turna`。  
Collection：`files/official_anki/default/collection.anki2`。不要 wipe 用户卡。

## 1. 开工顺序

无设备时只做 Host（A 组）。设备连上后做 B 组。B 没过不许写 P5-C GO。

```text
A1  文档口径（14 §1、过期 smoke 句）
A2  unrenderable 与 timeout 分码；禁止自动 bury
A3  B03 backup：census → generate → 落盘 → DAO
A4  B06 preview：真实 census + 跑过 saga 的 card map
A5  B07 golden 独立 fixture 文件
A6  跨日 / daily limit 的 Host 或最小脚本

B1  adb 在线后重跑 hash manifest（必须含 deviceApk/deviceSo）
B2  连续 20 张 Good：logcat viewId 不递增，或递增时 timeout+superseded=0
B3  Device A internal-release 100 + RSS / stall
B4  用本文命令复算后，才改 final-decision.txt
```

`A2–A5` 若源码里已经有对应符号，不要再发明第二套 API；按第 3 节验收命令复核，缺哪条补哪条。

## 2. Host 怎么实施

### A1 文档口径

改这些，不改产品行为：

- `14` §1 的 `P4 FORMAL REVIEW INTEGRATION：NO-GO` 改成「已被 Device A artifact / `18` 取代；生产默认仍 NO-GO」
- `artifacts/p4r2/device-a-debug-smoke.txt` 里「release first present blank」加一行：`superseded by device-a-release-smoke.txt`
- 不要在 `17` 里把未复算的设备项写成 PASS

### A2 不可渲染卡 vs timeout

**改哪里**

| 文件 | 改动 |
|---|---|
| `lib/application/anki_official/render/official_anki_render_state.dart` | `recoverableCodes` 只留瞬时码（`RENDER_TIMEOUT` / `RENDER_SUPERSEDED` / `SHELL_NOT_READY` / 资源缺失）。`fatalCodes` 放 `UNRENDERABLE_CARD` / `UNRENDERABLE_TEMPLATE` / `CARD_NOT_FOUND`。`isRecoverableCode` 先查 fatal |
| `lib/application/anki_official/render/official_anki_present_ack.dart` | 空 native code → `RENDER_TIMEOUT`（可恢复）。未知 `renderError` **不要**再默认可恢复；映射为 `UNRENDERABLE_CARD` 或保持 fatal |
| `lib/views/anki_official/official_anki_review_page.dart` | render error 时评分按钮保持 disabled。Retry 只对 recoverable。fatal 只给「Bury card / Skip / Back」，**页面自己不得**调用 `buryOrSuspend` |
| `lib/application/anki_official/engine/official_anki_review_session.dart` | `refreshQueue` / `applyFailure` / presenter error **不得**间接 bury |

**禁止**

- 测试脚本、内部页、session 在 `isRenderError` 时自动 `buryOrSuspend`
- 失败后 `dispose` + 重建 PlatformView 当重试

**测试（必须新增或补强）**

```text
unrenderable_card_does_not_call_bury
render_timeout_shows_retry_and_scheduler_writes_zero
fatal_code_disables_rating_and_keeps_webview
```

spy `OfficialAnkiEngine.buryOrSuspendCards`，render fatal 后调用次数 = 0。

**做完标准**

- `renderError` 不再出现在 `recoverableCodes`
- debug/release 100 artifact 的 `bury-unrenderable` 若 > 0，必须写明是**人手**点的 Bury，并记 cardId

### A3 B03 backup 落盘

现有 `LegacyAnkiBackupService.generate` 只哈希四个整数，不够。按下面补齐，不要新开平行类。

**行为**

```text
LegacyAnkiCensusService.collect
  → generateFromCensus(census, officialBackupId, projectionFingerprint)
  → persist(manifest, File)
  → dao.setBackupInfo(migrationId, backupId, manifest.legacyRowHash)
```

**落盘路径（只写官方 profile 目录，不写 CourseDatabase）**

```text
<app-support>/official_anki/<profile>/backups/legacy-manifest-<migrationId>.json
```

JSON 只含计数和 hash，**禁止**卡片正文、字段、媒体路径。

`officialBackupId` 必须来自已有官方 backup/check API 的返回值；没有 backup 就留空并让 preview 显示「尚未备份」，不要伪造 id。

**测试**

- 同一 census 两次 `generateFromCensus` 的 `legacyRowHash` 相同
- `persist` 后文件可 `fromJson` 还原
- 落盘文件用 `grep` 断言不含 `你好` / `questionHtml` / 绝对路径

### A4 B06 preview 接真实数据

`OfficialAnkiInternalPage._openMigrationPreview` 禁止再构造空 `LegacyAnkiCensusReport(imports: [])` 当成功路径。

**接线**

1. `CourseLoader.databaseOrNull()` / `getIt<CourseDatabase>()` → `DatabaseLegacyAnkiCensusReader` → `LegacyAnkiCensusService.collect`
2. 对每个 import 建或读取 `legacy_anki_migrations` 行
3. 用 `LegacyAnkiDryRunSaga.run`（只读 identity，不 import、不 answer）
4. 把 **saga 产出的** `LegacyAnkiDryRunResult` 传给 `OfficialAnkiMigrationPreviewPage`
5. `diskFreeBytes` 用 `Directory.statSync` / 磁盘 API，不要写死 `500MB`
6. Cutover 按钮继续 `onPressed: cutoverEnabled ? … : null`；`cutoverEnabled` 保持 false

catalog 路径必须走 `OfficialAnkiPaths`，不要手写 `official_anki/default/catalog.sqlite` 字符串分叉。

**测试**

- widget test：有 census 时页面出现 `cards=` / `unmatched=`
- Cutover `onPressed == null`
- `AnkiSourceRouteResolver.resolve` 仍是 `legacy`

### A5 B07 golden

不要只在 `official_anki_p4r2_closeout_test.dart` 里堆一张表。拆成 identity fixture：

```text
test/application/anki_official/fixtures/legacy_match/
  basic.json
  reverse.json
  cloze.json
  duplicate_guid.json
  missing_guid.json
  multi_template.json
  unicode.json
```

每份只有 `legacyCardId / noteGuid / templateOrd / contentFingerprint / officialCardId / expectedMatchState`。  
`LegacyAnkiDryRunMatcher.match` 读文件，断言 `matchState` / `matchMethod`。无卡片正文。

### A6 daily limit / 跨日

设备改系统时间容易伤用户牌组，**先做 Host**：

- 用已有测试注入 `answeredAtMillis`（仅 test flag）
- 同一 deck `new_per_day` 打满后，`GET_REVIEW_QUEUE` 为空且 `congrats` 有值
- 把「今天」推过后，新卡重新出现

设备上若必须跑：只改 **该 deck** 的 `deck_config.new_per_day`，写入 artifact，禁止 wipe Collection。DST 完整矩阵标 DEFERRED。

## 3. 设备怎么实施

入口（不要点「高级」里别的小字）：

```text
设置 → 高级（Anki 保真那一行）→ Official Anki 内部导入 → 正式复习
```

### B1 hash 闭环

设备必须 `adb get-state` = `device`。在仓库根：

```bash
cd Varnamalaplus
export OFFICIAL_ANKI_APK=build/app/outputs/flutter-apk/app-release.apk
export OFFICIAL_ANKI_PACKAGE=me.dsdogs.turna
export OFFICIAL_ANKI_HASH_OUT=docs/official-anki-migration/artifacts/p4r2/native-hash-manifest.txt
bash tool/official_anki_native_hash_manifest.sh
```

通过条件（缺一段就 FAIL，不要手填）：

```text
built == jniLibs
apkSo == stripped == deviceSo
deviceApk == apk
ENGINE_INFO.backendCommit == 967aa0d578fc75181e292e95326f9b58698da25c
```

`ENGINE_INFO` 从内部页 UI 抄到 `artifacts/p4r2/engine-info.json`，`"handFilled": false`。  
`deviceApk: MISSING` 时 **禁止** 把 manifest 写成 CLOSED。

若本地还没有对应 release APK，先内部构建再装，不要拿过期 APK 对当前 dirty tree 充数：

```bash
flutter build apk --release --target-platform android-arm64 "${DEFINES[@]}"
adb -s 3B15AG00FPB00000 install -r build/app/outputs/flutter-apk/app-release.apk
```

### B2 PlatformView 复用

`OfficialAnkiReviewerView` 必须继续使用**固定** `Key('official-anki-reviewer-view')`。`didUpdateWidget` 只调用 `_present()`，不要按 `cardId` 换 Key。

设备验收：

```bash
adb -s 3B15AG00FPB00000 logcat -c
# 正式复习连续 Good 20 张
adb -s 3B15AG00FPB00000 logcat -d | rg 'OfficialAnkiReviewer|viewId|renderComplete|RENDER_'
```

通过：`create viewId=` 在整个 session 只出现一次；或出现多次时 `RENDER_TIMEOUT` + `RENDER_SUPERSEDED` = 0。  
记入 `artifacts/p4r2/device-a-release-20-reuse.txt`。

### B3 release 100 + RSS / stall

**准备**

- 使用设备上已导入的用户牌组。`openDueDeck` 不要钉死 `deckId=1`
- 若今日 new 队列被 `new_per_day` 卡住：只对该 deck 的 `deck_config` 把 `new_per_day` 调到 ≥ 100，并写进 artifact
- 四档尽量 25/25/25/25；做不到就如实记，不要改数字

**计数**

| 字段 | 怎么数 |
|---|---|
| rated | 成功 `answer` 且 queue 前进 |
| timeout | `RENDER_TIMEOUT` overlay |
| superseded | `RENDER_SUPERSEDED` |
| unrenderable | fatal 码；人手 Bury 另记 |
| revlog delta | 官方 Collection `revlog` 行数差，应等于 rated |

**性能（同一 session）**

```bash
# 开始前
adb -s 3B15AG00FPB00000 shell dumpsys meminfo me.dsdogs.turna | rg 'TOTAL RSS|Native Heap'
# 每 20 张再采一次，取峰值
# stall：gfxinfo / presenter log 里 frame > 500ms 的次数
adb -s 3B15AG00FPB00000 shell dumpsys gfxinfo me.dsdogs.turna framestats | tail
```

写到 `artifacts/p4r2/device-a-release-100.txt`，至少包含：apk sha、deviceApk sha、rated、四档、timeout、superseded、unrenderable、RSS 峰值、stall>500ms、是否改过 `new_per_day`。  
截图：首张 question、一张 answer+四档、第 100 张后的下一张或 Congrats。

**做完标准**

```text
superseded = 0
timeout 不解锁评分
unrenderable 自动 bury = 0
revlog delta = rated
```

## 4. 每次改完必跑

```bash
cd Varnamalaplus
flutter test --no-pub test/application/anki_official
flutter analyze --no-pub \
  lib/application/anki_official \
  lib/views/anki_official \
  test/application/anki_official
```

动到 native receipt / bury / hash 时再加：

```bash
cargo test --manifest-path native/turna_anki_core/Cargo.toml --lib
```

默认并行一次即可；失败不要改成 `--test-threads=1` 充数。

## 5. 什么时候才能改 `final-decision.txt`

只有下面全部当场复算成功，才允许写成 Device A CONDITIONAL GO，并且 **仍然** 写：

```text
P4 PRODUCTION DEFAULT FLAGS: still false
P5-C FIXTURE PILOT: HOLD
P5 USER CUTOVER: still NO-GO
P5 LEGACY DELETION: still NO-GO
```

复算清单：

1. `official_anki_native_hash_manifest.sh` 退出 0，且无 MISSING
2. `device-a-release-100.txt` 与当前已装 APK sha 一致
3. `flutter test` official 全绿，含 unrenderable / persist / preview / golden
4. preview Cutover 不可点；`cutoverEnabled == false`
5. `adb devices` 只有 Device A 时，Device B 继续写 out of scope，不写 PASS

缺任一条：保持 `18` 的 NO-GO，不要改 `17` 标题里的 COMPLETE。

## 6. P5-C：已接到「进入 P5」——施工见 `21`

产品已指示进入 P5。P5-C 怎么改、怎么跑、怎么过，以 [`21-p5c-fixture-pilot-implementation-playbook.md`](./21-p5c-fixture-pilot-implementation-playbook.md) 为准。本轮仍按 `14` §8，并且：

1. coordinator 拿 migration lease
2. 用户重选原 `.apkg`，校验 hash
3. backup Legacy 子集 + official Collection
4. 官方 Import Saga
5. dry-run 100% 唯一匹配，否则停
6. 重建 projection
7. 只对 **内部 fixture / 无价值测试号** 写 `cutoverReady`
8. 观察，不删数据

生产路由和默认 flag 仍不动。

## 7. 明确不要做的改法

- 不要为了超时再 `setState` 丢掉 WebView
- 不要在 worker 之外再加一套 coordinator
- 不要把 mutation receipt 放到 `CourseDatabase`（downgrade 会清）
- 不要用 Turna SRS 次数对账官方 revlog
- 不要在 README 状态行写 PRODUCTION GO

## 8. 建议一次提交的切片

```text
commit 1  A2 unrenderable + 测试
commit 2  A3 persist + A4 preview 接线
commit 3  A5 golden fixtures
commit 4  设备 B1–B3 artifact（不改默认 flag）
commit 5  仅在第 5 节清单全绿后更新 final-decision / 17
```

每个 commit 后跑第 4 节命令。设备 commit 必须带 apk sha，避免再出现「报告是新的、APK 是旧的」。
