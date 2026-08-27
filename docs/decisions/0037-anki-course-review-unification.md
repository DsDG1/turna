# ADR 0037 — Anki 课程与复习大一统合同

- 状态：已接受（施工中）
- 日期：2026-08-20
- 取代：已交付的 anki-review-unification-construction-plan（正文在 Git 历史）中与本 ADR 冲突的“已完成”表述；官方迁移文档中“一卡多投影 / 未学可复习”相关产品合同

## 决策

同一张 Anki 源卡在课程与复习中只有一个身份、一个 active presentation、一个 introduction 状态和一个 ledger 写入者。

```text
CanonicalCardKey
  = CourseCardPlacement
  = active CardPresentation
  = CardIntroductionState
  = StudyLedgerOwner
```

正式复习资格是：

```text
authoritative due ∩ active placement ∩ introduced ∩ not suspended/buried/retired
```

课程决定第一次怎么学、学过没有、用哪种题型。Official collection/scheduler 仍是官方卡排期唯一事实；Turna FSRS 只服务 Turna-owned / Legacy 卡。禁止双写。

## 后果

- 普通词汇默认 Flip，不得仅因牌组干扰项生成第二张正式 MCQ。
- 课程式 practice surface 必须用 renderer-neutral PresentationReceipt，不得依赖未挂载 WebView 的 ACK。
- 新代码不得用 `id.startsWith('anki-')` / `official-anki-` 推断 backend。
- 施工主计划已压缩为兼容入口：[`docs/anki-course-review-unification-plan.md`](../anki-course-review-unification-plan.md)（原 `# Anki 课程与复习大一统实施计划.md`，正文由 Git 保存）。

## P5–P10 落地（2026-08-21）

- 课程 first-learn 与正式复习共用 `AnkiStudySessionHost` / `StudySessionController`；Official 写入失败不得回落 Turna。
- 所有正式复习入口经 `FormalReviewLauncher` 落到同一 session host；Official 不可用 fail-closed。
- 新导入走 `UnifiedAnkiImportOrchestrator`：Official 可用时不写 Turna Anki SRS；同 hash 再导入 no-op。
- 旧数据 census / owner / introduction 回填 / 投影收敛不把 Turna 历史重放到 Official。
- 产品统计按 `eventId` 去重；`loading` / `unavailable` / `error` / `stale` 与 0 可区分。
- 正式路径不再运行时二次 classify，产品 UI 为二元 recalled/forgotten，旧表暂不物理删除。
