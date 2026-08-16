# ADR 0036 - 官方 Anki rslib 作为唯一 Anki 事实源

- **状态：** 已接受（实施从 Phase 0 Spike 开始）
- **日期：** 2026-08-16
- **前置：** `docs/official-anki-migration/00-overall-migration-plan.md`
- **真源：** `native/turna_anki_core/`、`docs/official-anki-migration/`

## Context

Turna 当前同时维护自研 `.apkg` 解析、模板渲染、HTML/WebView 回退和 SRS 迁移。多个事实源已经造成乱码、Reverse/Cloze/`FrontSide` 语义偏差，以及调度与官方 FSRS/revlog/Undo 不一致。继续扩展自研解析器会把官方格式适配变成永久成本。

## Decision

1. 官方 `ankitects/anki` 的 `rslib` 是唯一 Anki 核心。Turna 不重写 package parser、模板引擎和 Scheduler。
2. 集成方式是 pinned Anki source + Turna Rust `cdylib`（`libturna_anki.so`）+ 极小 C ABI + Turna 自有 contract。Dart 不暴露上游 Protobuf 或 service/method 数字编号。
3. 每个 Turna profile 一个全局官方 Collection。Turna Drift 只保存来源关联、课程位置、语言字段 mapping 和可重建投影。
4. 原始 Anki Card 固定隔离 WebView；Turna 派生练习固定 Flutter。官方失败不静默回退到 Legacy。
5. 首发平台是 Android arm64。OHOS / 桌面 / AnkiWeb 不阻塞 Phase 0。
6. 实施必须先完成 Phase 0 技术 Spike。未通过 Go/No-Go 前，不替换生产 `AnkiImporter`，不删除 Legacy。

## Consequences

- 需要维护 Rust/NDK 构建和 AGPL 源码分发。
- 上游 Rust API 无 semver，必须钉死 commit，升级走独立 PR。
- 安装包增加 native 体积；具体预算由 Phase 0 测量后确认。
- Legacy 导入/渲染/SRS 在 Spike 和正式迁移完成前保持可运行，但冻结功能扩展。

## Rejected alternatives

- 继续维护自研解析/渲染/调度。
- 移植整个 Anki Desktop（Python/Qt）。
- 以 AnkiDroid Backend AAR 作为长期公共接口（仅作构建对照）。
