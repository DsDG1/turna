# ADR 0044 — Anki 底座 v2 复活（2026-09-02）

- 状态：**已接受**（2026-09-02）
- 关联：[ADR 0043](./0043-anki-v2-single-source-of-truth.md)；[复活记（起因经过结果）](../ankiUpdate/v2-revival-story.md)（架构设计原文，状态由本 ADR 修订为「执行中」）；[ankiUpdate README](../ankiUpdate/README.md)（2026-09-01 失败结论，保留为历史记录）；[step4.md](../ankiUpdate/step4.md)（Step 4 施工状态）
- 取代：原「PR2：catalog 迁 drift 后台」计划（作废，由 v2 的 D4 删表终局吸收）

## 背景与依据

v2 于 2026-09-01 判「未交付失败」，直接卡点是 **C3 真机强杀矩阵未跑**——发布门禁永远无法满足。

2026-09-02 的 crash-hunt（证据：`logs/crash-hunt/`，收据：`test/BASELINE.md` 当日条目）把「导入后点开始学习卡死闪退」根因为**向导页 UI 层死循环**，与 v2 架构无关：

```
PopScope(canPop: false) 写死不放行
→ onPopInvokedWithResult 里确认后重试 context.router.maybePop()
→ 被 canPop 挡回 → 回调再触发 → 无限微任务乒乓
（每秒 ~100 次 Scavenge、1.6GB/s 短命分配、主 isolate 100% CPU，触摸即 ANR 处决）
```

该 bug 使**任何真机导入流程都在完成页终结于卡死**——C3 矩阵的多行（尤其 K13「大库期间无 ANR」）当年结构性地不可能变绿。v2 架构从未在真机上被证伪；杀死它的是一个已修复的 UI bug。

修复已落地：`anki_import_screen.dart` 四处离开路径 `maybePop` → `context.router.pop()`（绕过 canPop 闸门，同 `ai_api_config_page` 既有修法），守卫测试 `anki_import_pop_loop_guard_test.dart` 锁死复发；真机（PLG110）实测通过。

## 决策

1. **复活 v2**。ADR 0043 恢复为「执行中」，架构设计原文不变；本 ADR 只重开执行线。
2. Step 4 账面状态：任务 A/B/C2 均 ✅（host 落码 + 31 用例全绿），剩余执行线如下（R1→R4 为 Step 4 关闭条件）：

| 步 | 内容 | 备注 |
|---|---|---|
| R1 | 重建 arm64 `libturna_anki.so`（含 op 41/42，契约 1.12；`verify_symbols.sh` + SHA 收据） | 现网设备 .so 旧于 op 41/42（`[OfficialAnkiV2] unimplemented` 日志为证），C3 硬前置 |
| R2 | C3 真机强杀矩阵 K1–K14 | 设备以实际 serial 记录取证（不限于原计划 vivo 机）；debug/release 双跑纪律不变 |
| R3 | C4 大库 P95 冷重建定标 | 测量面已在（重建器 `elapsedMillis`） |
| R4 | 内部观察期 → `productionAndroid` 翻 `v2ImportChain=true` → Step 4 关闭 | dev/QA 构建即刻 `copyWith` 开 flag 投喂 |

3. **新增前置（R1.5，本轮抓捕带出）**：v2 链 `OfficialAnkiV2ImportService.commit` 的 `upsertCardBatch` 是每卡一行同步 sqlite 写在主 isolate（与 v1 已修复的同款问题），须先照抄 v1 `commitReceipt` 的 worker 下沉模式，否则 K13 大库行必挂。
4. **原「PR2 catalog 迁 drift」计划作废**：v2 的 D4（catalog 18→5 表）在 Step 6 直接删除多余副本，先迁 drift 再删等于做两遍。v1 侧已落地的 PR1 主线程止血（投影/词表/回执后台化）保持有效，与 v2 正交。
5. Step 5（存量迁移）随复活重新决策；Step 6（删 v1 面）吸收原 PR2 目标。

## 风险与纪律

- 翻生产 `v2ImportChain` 仍要 R2/R3/R4 **实机过了**（2026-09-02 修订：host 测试、logcat、诊断导出、bugreport **不构成完成，也不再作为推进条件**）。一行过不过只看操作者在真机上的确认。
- 2026-09-01「门禁不满足就不翻 flag」仍有效，门禁内容改为实机，不再是取证包。
