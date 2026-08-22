# P5-C 收口结果报告（对齐 24 §4）

> 文档代号：P5C-CLOSEOUT  
> 日期：2026-08-19  
> 前置：[`14`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8–11、[`15`](./15-p5-legacy-inventory.md)、[`21`](./21-p5c-fixture-pilot-implementation-playbook.md)、[`23`](./23-p5c-audit.md)、[`24`](./24-p5-remainder-and-p6-ankiweb-plan.md) §4、[`22`](./22-p5c-result-report.md)  
> 本报告不覆写 `23`；`23` 作为作废 GO 的审计记录保留。本报告是 24 §12 所指「P5-C 收口做完」的新结果报告。  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 产物：`artifacts/p5c/`（以其中 `baseline.txt` / `host-pilot.txt` / `device-a-fixture-pilot.txt` 为事实源）

## 1. 最终结论

```text
P4 PRODUCTION DEFAULT FLAGS: still false
P5-A 只读盘点 / resolver / write-owner: 已落地，不再重做
P5-B registry / dry-run / 预览: 已落地，不再重做
P5-C isolated fixture (Host): HOST CONDITIONAL GO
P5-C isolated fixture (Device A 3B15AG00FPB00000): DEVICE RE-VERIFIED (P5C-20)
P5-C 作为「可迁用户数据」: NO-GO
P5 USER CUTOVER: NO-GO
P5-D 生产路由: HOLD（要产品书面「进入 P5-D」）
P5-E 删 Legacy: HOLD（至少跨一个正式 release 观察）
P6 AnkiWeb Sync: 已取消（2026-08-20；本报告当时为不开工）
catalog: v8 (recordedKind)
```

24 §4 的 P5C-14…20 在本报告周期已全部落地（代码 + 测试 + Device A 重验），因此 24 §4 自本报告起视为**已收口**；但仍满足 `P5 USER CUTOVER: NO-GO` 与 `P5-D/E HOLD`，符合 24 §12 的收口语义。`22` 保留作历史记录，结论以本报告为准。

## 2. 24 §4 P5C-14…20 收口对照

| ID | 24 要求 | 本周期交付 | 证据 |
|---|---|---|---|
| P5C-14 | 可复现 fixture：`classic-basic.apkg` 为设备默认；`basic-cloze.apkg` 标 stub；allowlist 只认 `p5c-fixture-` / sha256 | `classic-basic.apkg` 已入仓（`28d89bb7...`，经典 `collection.anki2` 1 卡 hello/world）；`basic-cloze.apkg` 保留并标 Legacy≠Official；`fixture-allowlist.txt` 已对齐 | `sha256sum fixtures/p5c/*.apkg`、`fixture-allowlist.txt`、`official_anki_p5_prep_test` 的 P5C-01 |
| P5C-15 | `createPhysicalBackup` 缺/空文件不得成功；5 文件非空 | 已改为 fail-closed：缺 `collection.anki2` / `official_catalog.sqlite` 或任一备份文件空即抛 `StateError` | `backup_files_exist_and_contain_no_card_html`、`official_anki_backup_manifest.dart` |
| P5C-16 | catalog `recordedKind` 列；`cutover` 写 `official` | `OfficialAnkiDatabase` v7→v8 迁移新增 `recorded_kind TEXT`；`verifyAndCutover` 写入 `official`；`cutoverEnabled` 仍 false，生产路由本批不读 | `official_anki_database.dart` v8、`official_anki_migration_dao.setRecordedKind`、测试 `recordedKind_*` |
| P5C-17 | WriteGuard 接真实写路径（`recordCardReviewed` / `anki_note_dao` / `OfficialReviewSession` / `projection`） | `AnkiSrsMigrator.migrate` + `AnkiDeckManager.recordCardReviewed` + `AnkiNoteDao.setCardState` 均接 `AnkiWriteGuard`；`OfficialReviewSession` 由 `coordinator.guardSchedulerWrite` 守护 | `cutover_fixture_source_denies_turna_srs_answer`、`legacyAnkiDao setCardState denies`、`official_anki_review_session.dart` |
| P5C-18 | 回滚读 `official_mutation_count_at_cutover` 列 | `rollback()` 读 DAO 列的 stored count；`mutation==0 → rollbackEligible + recorded_kind→legacy`，`>0 → noLegacyScheduleRollback` | `rollback reads official_mutation_count column`、`cutover_with_official_mutation_cannot_restore_legacy_schedule` |
| P5C-19 | Host 真导入（至少一条非 Fake） | Host 已跑真实 `.apkg` bytes + sha 校验到 `backingUp`，并以 `OfficialAnkiImporter` contract 跑通 `importOfficial` 到 `indexingOfficial` | `p5c-19 host real import path for classic-basic.apkg` |
| P5C-20 | 设备复算清单（Device A） | 已重装 HEAD `5930f615...` 到 Device A，catalog 7→8，hash 闭环，fixture 1:1 observing，投影 1/1，`allowedCardIds` 过滤，用户 181 张不动，不 wipe | `device-a-fixture-pilot.txt`（P5C-20 checklist 全 ✓） |

## 3. 设备事实（P5C-20）

- `apk sha 5930f615fea505dfdea76e787c065912ac7c45c3d8904cb0814e80063850fa1c == device apk`；`official_anki_native_hash_manifest.sh` OK（`built==jniLibs 207ea17e...`，`stripped==apkSo==deviceSo 824def69...`）
- `official_catalog.sqlite` `user_version 8`；`mig-p5c-fixture-device state=observing recorded_kind=official mutations_at_cutover=0 official_source_id=src-fe0822...`
- `legacy_anki_card_map`：`1375933503610 → 1375933503610 noteGuidAndOrdinal matched`
- `anki_sources`：`src-bc0f 181 cards`（用户牌组）、`src-fe08 1 card`（`28d89bb7...`）、`src-00bf 2 cards`（历史 stub 残留）
- `anki_source_projection_state`：`src-fe08 state=active count=1`
- `collection.anki2`：WAL 合并后 `revlog 160`，fixture `1375933503610` 2 行（两次 Good），`cards 184`，`collection.anki2` 仍在
- `backups/p5c/mig-p5c-fixture-device`：5 文件齐且非空；`SHA256SUMS` 齐

## 4. 测试与命令证据

```text
flutter test --no-pub test/application/anki_official/official_anki_p5_prep_test.dart   34 passed
flutter test --no-pub test/application/anki_official                                   230 passed
flutter analyze --no-pub lib/application/anki_official lib/views/anki_official test/application/anki_official   0 issues
cutoverEnabled == false
preview_cutover_button_stays_disabled (read preview_page.dart source) == true
routing still Legacy (ankiweb_not_linked_from_production_routes)
```

## 5. 仍保持 NO-GO / HOLD 的原因

- `P5 USER CUTOVER: NO-GO` — fixture observing 不代表用户牌组可迁；用户既有牌组仍不在 allowlist
- `P5-D HOLD` — 未收到产品书面「进入 P5-D」；未改 `AnkiReviewRoute` / `AnkiImportRoute`，未动 `TURNA_OFFICIAL_ANKI_*` 默认
- `P5-E HOLD` — 需至少跨一个正式 release 观察
- `P6 已取消` — 2026-08-20 书面不考虑与 AnkiWeb / 官方 Anki 同步；不写 sync 代码
- `Device B: out of scope`

## 6. 后续入口

- Device A §5.4 回滚两条路径已演练（`artifacts/p5c/rollback-drill.txt`）：mutation>0 → `noLegacyScheduleRollback`/`official`；mutation=0 → `rollbackEligible`/`legacy`。用户 181 张与 collection 未 wipe。
- 若继续收 fixture：可在 `P5-C+` 加第二个 isolated fixture（≤20 张）
- 若产品说进入 P5-D：先书面确认方案 B，再另写 P5-D HOWTO（对标 24 §5），再改路由
- 若有人提 AnkiWeb / 官方同步：拒绝。P6 已取消（24 §7）
