# ADR 0041 — OHOS 产品级退役（EOL）

- 状态：已接受
- 日期：2026-08-24
- 关联：[`docs/official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md`](../official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) W1/W2；[ADR 0036](./0036-official-anki-core-migration.md)、[ADR 0037](./0037-anki-course-review-unification.md)
- 编号说明：任务草案曾写 `0038-ohos-product-eol`；仓库内 0038–0040 已占用，本决策记为 **0041**。

## 决策

停止产品级 OpenHarmony / HarmonyOS（OHOS）支持：

1. 不再为 OHOS 构建、发布、适配、修复或新增功能。
2. 不建设 OHOS Official Anki Core；原“OHOS 继续 Legacy”路线作废。
3. 删除 `ohos/` 产品 target、OpenHarmony Flutter fork 依赖覆盖、`tool/apply_patches.sh` 与 `tool/patches/`。
4. 共享 Dart 运行时统一为官方 Android/iOS（及现有桌面/Web）路径：Drift `NativeDatabase`、官方 `file_picker` / `flutter_local_notifications`，无 HarmonyOS RDB / Ohos* 通知 API。
5. 非 Android 平台不得以“没有 Official Core”为由继续打开 Legacy Anki 写入；未知平台 → Anki 不可用（`ankiUnavailable`）。

## Sunset export status

**导出路径已交付，不采用“无外部用户”自动豁免。**

- 实现：[`lib/application/migration/turna_migration_export.dart`](../../lib/application/migration/turna_migration_export.dart) 产出平台中立的 `turna-migration-v1` zip（manifest / profile / settings / course_progress / srs_states / review_history / mistakes / anki_* / introductions / media_manifest / media/`<sha256>` / SHA256SUMS）。密钥与 API key 经 `BackupManifestPolicy` 排除。
- 原因：本施工环境**没有**应用商店安装量、渠道下载或外部 OHOS 用户清单等可审计证据。缺少商店指标记为**环境限制**，**不能**据此写成豁免。
- 因此：导出路径随产品代码一并交付，供任何残留 OHOS 安装做数据出口；产品构建不再以 OHOS 为 target。Android 侧对包内 Legacy Anki 数据的处置为 `legacyPendingMigration`（见 doc 34 §5.4 / §7），不直接成为活动 scheduler。

若日后补齐“确认无外部 OHOS 用户”的书面证据，可在本 ADR 追加豁免附录；在此之前以导出路径满足用户数据出口要求为准。

## 后果

- 活跃文档（README / CLAUDE / project-guide / android-build-setup / official-anki-migration README）改为官方 Flutter + Android 主力；历史 CHANGELOG 与 archive 不重写。
- Architecture guard 测试禁止活跃树再引入 `HarmonyOsRdbExecutor`、`OhosInitializationSettings`、`OhosNotification`、openharmony dependency overrides、`tool/apply_patches.sh`。
- Android 构建路径不得被本决策破坏；Anki 生产收口继续按 doc 34 后续波次推进。
