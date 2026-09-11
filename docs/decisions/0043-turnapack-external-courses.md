# ADR 0043 — 外部课程经 `.turnapack` 间接进入

- Status: Accepted
- Date: 2026-09-11

## Context

Turna 的课程真理源是原生 JSON（`assets/courses/<dir>/` 同构）。LibreLingo 等外部课程是 YAML 模块/技能树，字段与 Turna 的 14 种 Interaction 不对齐。若在 app 内直接解析 YAML，会把第二种课程契约带进运行时，并与 seeder / validator / SRS 抢同一套 id。

## Decision

- App 运行时识别 `.turnapack` v1（UTF-8 JSON，`format: turnapack/1`）与 v2（zip，`pack.json` 的 `format: turnapack/2` + `media/`）。
- LibreLingo（及其它源）的转换永远在离线工具完成（`tool/librelingo_import.py`）。
- 导入语言的 descriptor（displayName / ttsLocale / signatureChars / license）写入 `courseMeta` 键 `importedLang:<code>`，不修改 packed manifest。
- 导入语言不可覆盖内置 manifest code；资源 id 强制 `ll-<code>-` 前缀。
- 包内媒体以 `turnapack://<code>/<file>` 引用，落在 `imported_courses/<code>/media/`。不做云商店、运行时 YAML、GUI 编辑导入课。

## Consequences

- 课程 JSON 契约仍然只有一份（authoring `course-layout.md` + `course-pack-format.md`）。
- 备份当前覆盖 `course.db`（含导入课行与 `importedLang` meta），**不**覆盖 `appSupport/imported_courses/*.turnapack`。卸载后恢复依赖持久化 pack（v2 会再解压 `media/`）；若用户清数据或备份未带上 pack 文件，UI 提示重新导入。
- v1 JSON 与 v2 zip 靠 `format` 字段区分；未知 format 拒绝。
