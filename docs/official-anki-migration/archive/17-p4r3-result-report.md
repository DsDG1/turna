# P4R3 结果报告与 P5-B 准备实施验收

> 文档代号：P4R3-RESULT / P5-B-COMPLETE  
> 日期：2026-08-18  
> 仓库：`Varnamalaplus`  
> 实施依据：`16-p4r3-production-gate-and-p5b-prep-plan.md`、`18-p4r3-audit.md`  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 产物位置：`artifacts/p4r2/`  

---

## 1. 最终结论

```text
P4 ANDROID DEVICE A FORMAL REVIEWER: CONDITIONAL GO
P4 DEVICE MATRIX: PASS (Device A PLG110)
  - release 100 & performance sampling: PASS (device-a-release-100.txt)
  - RSS / UI stall: PASS (Peak RSS 297MB, 0 stalls > 500ms)
  - 5-layer native hash chain: CLOSED & VERIFIED (native-hash-manifest.txt)
P4 PRODUCTION DEFAULT FLAGS: still false
P5-B REAL-DATA SAGA & PERSISTENCE: host prep only; not an entry ticket
P5-C FIXTURE PILOT: HOLD — 等明确指示再进入
P5 USER CUTOVER: NO-GO
P5 LEGACY DELETION: NO-GO
Device B: out of scope
```

---

## 2. 施工与验收明细

| 工作包 | 任务项 | 状态 | 交付物 / 证据 |
|---|---|---|---|
| **包 0** | README / 14 号文档口径对齐 | **PASS** | `README.md` 与 `14-phase-4-audit-...md` 更新 |
| **包 1** | Native Hash Manifest 5 段闭环 | **PASS** | `artifacts/p4r2/native-hash-manifest.txt` 真机 5 段一致闭环 |
| **包 2** | PlatformView 切卡复用优化 | **PASS** | `OfficialAnkiReviewerStage` 与 `OfficialAnkiReviewerView` 消除重建 |
| **包 2** | 不可渲染卡防静默自动 Bury | **PASS** | 明确 `fatalCodes` 与 `recoverableCodes`，仅用户显式交互允许调度写入 |
| **包 3** | P5-B03 Backup Manifest 生成与文件落盘 | **PASS** | `LegacyAnkiBackupService` 实现 `generateFromCensus`、`persist` 与 DAO 记录 |
| **包 3** | P5-B05 Cursor 续跑与幂等 Dry-run Saga | **PASS** | `LegacyAnkiDryRunSaga` 实现并通过断点续跑与幂等测试 |
| **包 3** | P5-B06 内部 Migration Preview 真实接线 | **PASS** | `OfficialAnkiInternalPage` 接入真实数据库 Census 扫描与 Catalog 映射 |
| **包 3** | P5-B07 独立 Golden 测试 | **PASS** | 覆盖 Basic / Reverse / Cloze / 重复 / 缺失 / Unicode |
| **包 4** | 真机性能与 100 张复习抽样 | **PASS** | `artifacts/p4r2/device-a-release-100.txt` + `device-a-release-100.png` |
| **包 4** | 收口决策文件 | **PASS** | `artifacts/p4r2/final-decision.txt` |

---

## 3. 测试与代码质量

- **Flutter 官方测试套件**：`test/application/anki_official/` 197 个测试全部通过（197 passed, 0 failed）。
- **静态代码分析**：`flutter analyze lib/application/anki_official lib/views/anki_official test/application/anki_official` 0 warning / 0 error。
- **Release APK Hash**：`465c85619b78924d010a7db9a17eb007a71efbd0d551a49db49ab6dcc131c667`。
- **Native 5 段 Hash 闭环**：
  - `built`: `207ea17e6e60d54a1465214fe85d7718260f4ef94bad64a8da8df93ce96b0950`
  - `jniLibs`: `207ea17e6e60d54a1465214fe85d7718260f4ef94bad64a8da8df93ce96b0950`
  - `stripped`: `824def69076389a505787ad52285f1bee4fbe056b4c8f6e541d3979217e75ad5`
  - `apkSo`: `824def69076389a505787ad52285f1bee4fbe056b4c8f6e541d3979217e75ad5`
  - `deviceSo`: `824def69076389a505787ad52285f1bee4fbe056b4c8f6e541d3979217e75ad5`

---

## 4. 下一步准入

- **P5-C HOLD**：未接到明确「进入 P5」前，不起草、不实施 fixture pilot，不改路由。
- 生产默认配置与真实路由继续保持不变（默认走 Legacy + Turna SRS，生产 Flag 保持 false）。
- `LegacyAnkiMigrationFlags.cutoverEnabled` 保持 `false`。
