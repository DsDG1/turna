# 侵入度阶梯 — 人工走查清单（F6）

| 字段 | 值 |
|------|-----|
| **版本** | 2026-09-07（体验 OS tab 落地后重写；Sovereign 档已移除） |
| **前置** | GUI 可启动；可选配置 AI API（设置 → AI 配置） |
| **相关** | `docs/archive/ai-intrusiveness-ladder-sovereign-proposal.md`（已废弃） |

### 已知限制（避免假失败）

- **H3**：课内须有**空课**或 Soft 可修项；无 AI Key 时 LLM 类技能走状态栏降级提示，不弹窗。
- **触发**：Ambient 刷新与静默驱动为**事件驱动**（选中节点/保存/处理建议触发）；周期心跳定时器未接线（`AmbientHeartbeatService` 预留）。
- **确认弹窗**：`lesson.fill_empty` / `resource.fill_stubs` 生成的改动仍经 SectionDiffView 人工确认（auto-apply 未集成到该视图，属安全取舍）。

完成后在下方 `[ ]` 打勾。失败请记档位 / 步骤 / 现象。

---

## H1 — 模式入口（设置 ▸ 体验 OS）

1. 打开 设置 → 体验 OS tab。
2. 模式下拉含 观察者/副驾驶/主动/沉浸 四档；Immersive 子开关与能力开关（Goal / LLM 意图 / 危险技能 / 日配额）在位。

| 期望 | 通过 |
|------|------|
| 默认档 = 副驾驶 Copilot | `[ ]` |
| 切到 观察者 → Ambient 清空、零 AI 写 | `[ ]` |
| 切到 主动 → Soft/伴随建议/战役一次弹出 | `[ ]` |

## H3 — Immersive 静默驱动

1. 体验 OS → **沉浸 Immersive**；弹出风险确认（说明 Ctrl+Shift+D 可降档）。
2. 打开含**空课**或触发 Soft 卫生的课程。
3. 选中节点 / 保存，触发上下文刷新（无周期心跳）。

| 期望 | 通过 |
|------|------|
| 进档弹确认；拒绝则下拉回滚原档 | `[ ]` |
| 无需点 Ambient banner 即可执行白名单 skill（Soft / 批量清待补） | `[ ]` |
| opaque 时 banner 可空，status 偶发 `…` 或 `已自动 N 项` | `[ ]` |
| Ctrl+Z 可撤销自动改动 | `[ ]` |
| 同一建议不重复刷（会话节流）；换课可再跑 | `[ ]` |
| 未配 AI Key 时仅状态栏「AI 配置不完整」，无弹窗 | `[ ]` |

## H5 — 降档与安全阀

1. Immersive 下按 **Ctrl+Shift+D**。
2. 观察状态栏与模式回落。

| 期望 | 通过 |
|------|------|
| 降档后 auto token 失效、静默驱动停止 | `[ ]` |
| 模式持久化（重启仍是 Copilot） | `[ ]` |
| 出站 publish / git.push 永不静默 | `[ ]` |

---

## 自动化对照

```bash
# 在 tool/gui 下
QT_QPA_PLATFORM=offscreen python -m unittest \
  tests.test_settings_dialog tests.test_settings \
  tests.test_experience_demote tests.test_fill_nokey_guard \
  tests.test_policy tests.test_immersive_p3p6 tests.test_presence_drive -q
```

---

*走查完成日期：________  执行人：________*
