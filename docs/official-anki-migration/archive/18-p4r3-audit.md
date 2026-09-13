# P4R3 验货报告

> 文档代号：P4R3-AUDIT  
> 日期：2026-08-18  
> 审查对象：`16-p4r3-production-gate-and-p5b-prep-plan.md`、`17-p4r3-result-report.md`、`artifacts/p4r2/`、当前 dirty worktree  
> HEAD：`81ba44b3bf11fc91846f787346245a17fd96a897` + dirty  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 方法：不采信 `17` 勾选；同时核对源码、本次复跑的测试、APK 内 `.so`、artifact 文本。本轮 `adb devices` 为空，**没有重跑设备**。

## 1. 结论先行

`17` 和 `artifacts/p4r2/final-decision.txt` 写早了。Host 测试和 P5-B 骨架属实，但 Device A 剩余硬门禁和「可对真实 Legacy 数据跑的准备 Saga」都还没关。

```text
P4 HOST / FORMAL REVIEWER (Device A): CONDITIONAL GO
P4 DEVICE MATRIX (release 100 / RSS / 跨日 / device hash): OPEN
P4 PRODUCTION FLAGS: NO-GO
P5-B HOST SKELETON: GO
P5-B REAL-DATA SAGA: NO-GO
P5-C FIXTURE PILOT: NO-GO（17 的 allowed next 作废）
P5 USER CUTOVER / DELETE: NO-GO
Device B: out of scope
本轮设备: NOT CONNECTED
```

`17` 仍可当作「P4R3 编码做过哪些文件」的索引，**不能当作退出门槛已满足**。

## 2. 本次复跑

| 检查 | 结果 | 判定 |
|---|---|---|
| `flutter test --no-pub test/application/anki_official` | **197 passed / 0 failed** | PASS，与 `17` 一致 |
| `flutter analyze --no-pub` official lib/views/tests | No issues found | PASS |
| `app-release.apk` sha256 | `465c85619b78924d010a7db9a17eb007a71efbd0d551a49db49ab6dcc131c667` | 与 release smoke / manifest 一致 |
| `jniLibs` `libturna_anki.so` | `207ea17e6e60d54a1465214fe85d7718260f4ef94bad64a8da8df93ce96b0950` | 与 manifest `built`/`jniLibs` 一致 |
| APK 内 `lib/arm64-v8a/libturna_anki.so` | `824def69076389a505787ad52285f1bee4fbe056b4c8f6e541d3979217e75ad5` | 与 manifest `apkSo`/`stripped` 一致 |
| `adb devices` | 空 | 无法核 deviceApk / deviceSo，无法重跑 100 张 |
| release 100 artifact | 不存在 | OPEN |
| RSS / stall artifact | 不存在 | OPEN |

## 3. 对 `17` 逐条验货

| `17` 声称 | 实地 | 判定 |
|---|---|---|
| 包 0 文档口径已对齐 | README 状态行已改；`14` 仅顶部加了一句，§1 正文仍写 Formal Review **NO-GO**；`device-a-debug-smoke.txt` 仍写 release 首张空白（已被后续 smoke 否定） | PARTIAL |
| Native hash **闭环** | Host 三段一致。manifest 写 `deviceApk: MISSING`、`deviceSo: MISSING`。无设备就不能闭环 | **FAIL**（相对「闭环」） |
| PlatformView 切卡复用 **PASS** | `OfficialAnkiReviewerView` 使用固定 `Key`，`didUpdateWidget` 只 `present()`。这是正确方向。但 release smoke 仍记录 `viewId=1` remount；之后没有新的连续 20 张设备证据 | CODE PARTIAL；DEVICE NOT PROVEN |
| 不可渲染卡禁止自动 bury **PASS** | 生产 `OfficialReviewSession` **没有** render-error 自动 bury。`renderError` 仍在 `recoverableCodes`，没有独立 `unrenderable`。debug 100 artifact 的 `bury-unrenderable=2` 未被新设备跑否定 | HOST PARTIAL；DEVICE OPEN |
| Backup Manifest 服务 **PASS** | `LegacyAnkiBackupService.generate` 只对调用方传入的四个整数做 base64。不读 census、不调官方 backup、不落盘 | HOST STUB，不是 B03 定义 |
| Dry-run Saga 续跑 **PASS** | `LegacyAnkiDryRunSaga` + 内存 catalog cursor 测试存在且本次套件已覆盖 | HOST PASS |
| Preview 已挂载 **PASS** | 内部页有按钮，但 `_openMigrationPreview` 传入 **空 census / 空 dryRun** | UI STUB |
| Golden **PASS** | `matcher goldens cover reverse cloze duplicate and unicode` 是一张 identity 表，不是独立 fixture 文件 | THIN PASS |
| `P5-C FIXTURE PILOT: allowed next` | `16` 要求先过 release 100、hash 闭环、unrenderable 处理。这三项都还开着 | **REVOKE** |

## 4. 仍成立的事实（不要连同 17 一起否定）

这些有代码或 artifact 支撑，验货予以保留：

- Formal Reviewer 单一 AppBar / 单一 Show Answer；评分依赖 answer ACK
- Device A debug 100：`rated=100`，`superseded=0`，四档各 25
- Device A internal-release 首张 present + Show Answer + Good：**PASS**（`device-a-release-smoke.txt` + 两张截图）
- catalog v7 mutation receipt；coordinator 接到 worker import 与 session 写路径
- Undo/Redo 读官方 status；Bury card / Bury siblings / Suspend 分开
- `OfficialAnkiFeatureFlags` 默认全 `false`
- `LegacyAnkiMigrationFlags.cutoverEnabled = false`
- 正常入口 `AnkiReviewRoute` / Play / Profile 仍走 `AnkiReviewAssembler` + Turna SRS
- 正式官方复习仍只从内部页进入
- Device B 不在门禁

## 5. 与 `16` 任务板对照

| 任务 | 验货状态 | 下一步 |
|---|---|---|
| P4R3-01 文档口径 | PARTIAL | 改 `14` §1；作废过期 smoke 句；以本文件为准 |
| P4R3-02 hash + ENGINE_INFO | HOST PASS；device **MISSING** | 设备连上后抽 deviceApk/deviceSo |
| P4R3-03 unrenderable vs timeout | 未完成产品语义 | 独立错误码；禁止脚本/产品自动 bury |
| P4R3-04 PlatformView 复用 | 代码有、设备未证 | 连上后连续 20 张看 viewId |
| P4R3-05 release 100 + RSS/stall | **未跑** | 设备门禁，优先于 P5-C |
| P4R3-06 daily limit / 跨日 | **未跑** | 最小脚本即可 |
| P4R3-07 backup 落盘 | stub | 接 census + 官方 backup id + 写文件 |
| P4R3-08 cursor 续跑 | Host PASS | 用真实 Legacy 行再跑一遍 |
| P4R3-09 preview / golden | stub / thin | preview 必须喂真实 census |
| P4R3-10 final-decision | **已降级** | 见本文件第 6 节 |

## 6. 已执行的文档纠正

验货当下改了这些会误导后续施工的文件：

- 本文件（验货结论）
- `artifacts/p4r2/final-decision.txt`：撤销 `P5-C allowed next`
- `17` 顶部加降级声明
- `README.md` 索引指向本文件

未改产品代码，未开 flag，未切路由。

## 7. 下一步（仍按 `16`，不另开阶段）

设备连上之前只能做 Host：B03 真落盘、preview 接 census、`unrenderable` 错误码。

设备连上之后的硬顺序：

```text
1. 抽当前已装 APK 的 deviceApk / deviceSo
2. 修 unrenderable / 确认无自动 bury
3. Device A internal-release 100 + RSS/stall
4. 再写 final-decision；那时才能谈 P5-C fixture pilot
```

在此之前保持：

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
P4 PRODUCTION NO-GO
P5-C NO-GO
P5 CUTOVER NO-GO
P5 LEGACY DELETION NO-GO
```
