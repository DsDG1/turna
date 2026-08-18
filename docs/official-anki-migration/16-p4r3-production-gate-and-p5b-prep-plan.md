# P4 生产门禁收口与 P5-B 准备实施计划

> 文档代号：P4R3 / P5-B-REMAINING  
> 日期：2026-08-18  
> 仓库：`Varnamalaplus`  
> 前置文档：`14-phase-4-audit-remediation-and-phase-5-execution-plan.md`、`15-p5-legacy-inventory.md`  
> 设备证据：`artifacts/p4r2/`  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  

## 1. 结论先行

下一步不是 P5-C cutover，也不是打开生产 flag。下一步是 **P4R3**：把 Device A 上已经打通的正式复习收到可复算的生产门禁，同时补完 **P5-B 尚未可运行的准备 Saga**。

```text
P4 HOST / FORMAL REVIEWER (Device A): CONDITIONAL GO
P4 DEVICE MATRIX (release 100 / RSS / 跨日): OPEN
P4 PRODUCTION FLAGS: NO-GO（默认仍 false）
P5 PREPARATION: GO
P5 CUTOVER / DELETE: NO-GO
Device B: out of scope
```

`14` 写于 Formal Reviewer 尚未联动、首张卡空白之前。它的 P4R2 修补包大部分已经落地；其中 **P4 FORMAL REVIEW NO-GO** 已被 Device A 证据取代，但 **P4 PRODUCTION NO-GO** 和 **P5 CUTOVER NO-GO** 仍然成立。

本轮结束后才允许起草 P5-C fixture / 测试号 pilot。本轮不写 cutover 代码。

## 2. 当前事实（以代码和 artifact 为准）

| 门 | 现状 |
|---|---|
| P4 Host / contract / Formal Reviewer ACK | Device A **GO** |
| Device A debug 100 张 | **PASS**（Again/Hard/Good/Easy 各 25；retries=5；`bury-unrenderable=2`） |
| Device A internal-release 首张 present + Show Answer + Good | **PASS**（APK sha256 `465c85619b78924d010a7db9a17eb007a71efbd0d551a49db49ab6dcc131c667`） |
| Device A internal-release 100 张 | **未跑** |
| RSS / UI stall 500ms / 跨日时区 DST / daily limit 设备矩阵 | **未跑** |
| Native hash manifest | **过期**（2026-08-17，仍写 100-card NOT RUN） |
| Device B | 产品已定 **不在门禁** |
| 生产 flag 默认 | 全部 `false` |
| 正常 `AnkiReviewRoute` | 仍走 Legacy + Turna SRS |
| 正式官方复习入口 | 仍只在内部页 |
| P5-A 只读盘点 / resolver / write-owner / capability | **已落地**（见 `15`） |
| P5-B schema v7 / matcher / preview 页 / DAO CAS | **代码已有** |
| P5-B 真实备份生成、崩溃续跑 Saga、独立 golden | **未完成** |
| P5-C/D/E cutover / 灰度 / 删 Legacy | **NO-GO** |

P4R2 可编码包已经在树里：

- Formal Presenter + `OfficialPresentAck` + 单一 AppBar / 单一 Show Answer
- `OfficialReviewPhase` 穷尽渲染；render error 不写 Scheduler
- catalog **v7** `anki_scheduler_mutations`（prepared / committed / unknown）
- `OfficialAnkiOperationCoordinator`（worker `importFile` + session 写路径）
- Undo/Redo 读官方 status；UI 区分 Bury card / Bury siblings / Suspend
- `OfficialAnkiAuditLog`；`LegacyAnkiMigrationFlags.cutoverEnabled = false`

`14` 的 P5-C 前提仍未齐：release 100、性能/跨日矩阵、当前 APK hash 闭环、以及 debug 100 里 2 张不可渲染却被 bury 的卡。

## 3. 本轮明确不做

不要把「首张卡能显示」当成可以迁用户数据或开生产。

- 不实施 P5-C 单来源真实 cutover
- 不改生产路由（`AnkiImportRoute` / `AnkiReviewRoute` 默认仍 Legacy）
- 不把 `TURNA_OFFICIAL_ANKI_*` / `scheduler` 默认改成 `true`
- 不删 Legacy、不伪造官方 revlog
- 不把 Device B 缺失写成通过
- 不做 Phase 6 AnkiWeb Sync
- 不补 OHOS official Core（capability matrix 已规定 OHOS 继续 Legacy）

## 4. 为什么下一步是 P4R3，不是 P5-C

`14` §14 对 P4 完成的可观察定义是：

```text
正式入口打开一张官方卡
  → 唯一正面
  → 唯一 Show Answer
  → 官方答案 ACK 后才出现四档间隔
  → 评分只产生一条官方 revlog
render error / 双击 / stale / worker death / 重启均不重复或错误写入
APK / native / device 身份可复算
```

现在只证明了 Device A 上 **首张卡 + 一次 Good + debug 100**。还缺：

1. 同一套 present 修复后的 **release 100** 证据
2. 可复算的 **当前 APK hash 链**
3. debug 100 暴露的 **不可渲染卡** 处理
4. RSS / stall / 跨日（这是 P4 设备硬门禁，不是 P5）
5. P5-B 还差「能续跑的 dry-run Saga」，现在只有 matcher + DAO `cursor_legacy_card_id` 字段

因此下一阶段代号 **P4R3**：把 P4 收到「Android Device A CONDITIONAL GO」，同时补完 **P5-B 准备**。完成后才能讨论 P5-C fixture / 无价值测试号 pilot。

## 5. 工作包

### 包 0：把文档口径改成真的

改这些文件，不改产品行为：

- 本目录 `README.md` 状态行，使其与第 1 节口径一致
- 在 `14` 顶部加「Formal Reviewer 设备结论以 `16` / 后续结果报告为准」
- 施工结束后另写结果报告 `17-p4r3-result-report.md`（本文件是计划，不是结果）

### 包 1：Device A 剩余硬证据（P0）

目标：同一份 internal-release APK 上补齐可复算证据。不新开生产入口。

1. 用**当前** `app-release.apk`（或 clean rebuild 后的同一份）重跑 `official_anki_native_hash_manifest.sh`
   - built == jniLibs
   - apkSo == strip(jniLibs) == deviceSo
   - `ENGINE_INFO` 从设备读，不手填
   - 写入 `artifacts/p4r2/native-hash-manifest.txt`（覆盖过期的 2026-08-17 文件）
2. Device A **internal-release 100 张**
   - 同一 German 牌组；不要 wipe 用户卡
   - 记录 rated / retries / timeout / superseded / bury-unrenderable / revlog delta
   - 若 `new_per_day` 仍挡住队列，只改该 deck_config，并写进 artifact
3. 性能抽样（可与 100 张同一 session）
   - 峰值 RSS
   - present P50/P95
   - UI stall > 500ms 次数
4. 跨日 / 时区：先做最小可重复脚本（改设备日期或 mock `answered-at` 测试注入），覆盖 daily limit 翻转。DST 完整矩阵可标 DEFERRED，但 daily limit 不能空着。

退出：release 100 的 `superseded=0`，且 `RENDER_TIMEOUT` 不再作为评分授权；hash 五段一致。

### 包 2：debug 100 留下的产品缺陷（P0/P1）

`artifacts/p4r2/device-a-debug-100.txt` 已记录：

- `retries=5 timeout=5`
- `bury-unrenderable=2`（fatal generic `renderError`，无 Retry，下一张继续）
- 下一张卡 WebView remount（release smoke 里 `viewId=1` 仍能 present）

要修的行为：

1. **不可渲染卡不得静默 bury**
   - 正式页已有 Retry overlay；fatal generic renderError 必须可区分 `unrenderable` 与瞬时 `RENDER_TIMEOUT`
   - 用户显式 Bury/Skip 才写 Scheduler；自动 bury 记为缺陷
2. **切卡尽量复用同一 PlatformView**
   - remount 不是 blocker（已 present 成功），但是 timeout/retry 的主要来源
   - 验收：连续 20 张 Good，viewId 不递增；或递增时 `superseded + timeout = 0`
3. 若 release 100 再出现 timeout：先查 poll / `__turnaLastRender` / iframe `anki.local`，不要再加「失败就重建 WebView」

### 包 3：补完 P5-B（仍禁止 cutover）

代码已有 catalog v7、`LegacyAnkiDryRunMatcher`、preview 页、`LegacyAnkiBackupManifest` DTO、DAO `cursor_legacy_card_id`。缺的是**可运行的准备 Saga**，不是再发明一套 schema。

| 任务 | 要做的事 | 不要做的事 |
|---|---|---|
| B03 | 从真实 Legacy census + official backup id + projection fingerprint **生成** manifest 并落盘 | 不切路由、不改 engine |
| B05 | 用 cursor 做 dry-run 分页；中断后从 `cursor_legacy_card_id` 续跑；同一输入两次 JSON 相同 | 不写 scheduling、不 import |
| B06 | 内部页挂上 preview（来源 / 卡数 / 三选一策略 / unmatched / 磁盘）；Cutover 按钮保持 disabled | 即使内部状态到 `cutoverReady` 也不改 `AnkiSourceRouteResolver` |
| B07 | 独立 golden：Basic / Reverse / Cloze / 重复 GUID / 缺 GUID / 多模板 / Unicode；只比 identity | 不需要真卡正文 |

`LegacyAnkiMigrationFlags.cutoverEnabled` 保持 `false`。

### 包 4：收口决策（文档，不改默认 flag）

包 1–3 通过后，写 `artifacts/p4r2/final-decision.txt`：

```text
P4 ANDROID DEVICE A: CONDITIONAL GO
P4 PRODUCTION DEFAULT FLAGS: still false
P5-C FIXTURE PILOT: allowed next
P5 USER CUTOVER: still NO-GO
P5 LEGACY DELETION: still NO-GO
```

**只有这份 decision 写了 `P5-C FIXTURE PILOT: allowed next` 之后**，才开始下一份计划：单来源 fixture / 无价值测试号 pilot（`14` §8 P5-C）。本轮不写 P5-C 代码。

## 6. 施工顺序

```text
P4R3-01  改 README / 14 口径（本计划落地后即可做）
P4R3-02  当前 release APK 四段 hash + ENGINE_INFO
P4R3-03  修 unrenderable vs timeout；禁止自动 bury
P4R3-04  切卡复用 PlatformView（若 03 后 timeout 仍高）
P4R3-05  Device A release 100 + RSS/stall 抽样
P4R3-06  daily limit / 跨日最小脚本
P4R3-07  P5-B03 生成 backup manifest
P4R3-08  P5-B05 cursor 续跑 + 幂等
P4R3-09  内部页挂 preview；golden fixtures
P4R3-10  final-decision.txt + 17 号结果报告
```

`01–06` 是 P4 收口；`07–09` 可与 `05` 并行编码，但 **P5-C 仍要等 `10`**。

## 7. 验收

- Flutter official 测试仍过；新增 unrenderable / dry-run resume / golden
- `flutter analyze` 无新问题
- release flag 默认仍全 `false`；preview Cutover 不可点
- `artifacts/p4r2/` 更新：hash manifest、release-100、ENGINE_INFO、final-decision
- 本目录不再把 Device A Formal Reviewer 写成 NO-GO

## 8. 风险与诚实声明

- Device A 单机 CONDITIONAL GO **不等于** 生产 GO
- OHOS 仍要 Legacy，共享删除继续禁止
- debug 100 的 5 次 timeout 说明 present 路径在长 session 里还不稳；先修再跑 release 100，避免用同一缺陷再刷一遍数字
- 生产默认必须继续保持：

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
P4 PRODUCTION NO-GO
P5 CUTOVER NO-GO
P5 LEGACY DELETION NO-GO
```
