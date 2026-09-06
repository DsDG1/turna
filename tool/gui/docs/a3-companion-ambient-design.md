# A3 伴随式建议 -- 设计文档

| 字段 | 值 |
|------|-----|
| **文档编号** | `VAR-GUI-EXP-A3-DESIGN` |
| **版本** | v0.1（设计稿，未实施） |
| **日期** | 2026-07-24 |
| **上游规范** | `tool/gui/docs/archive/experienceai.md` v4.65（§4.1「持续度：从按需触发到伴随式」加深轴；§8.7 Ambient/Mute 契约；§17 v4.65 尾注「下一：批3 A3 伴随式建议」） |
| **状态** | ✅ 已实施（v4.66，2026-07-24）；P1–P4 全切片落地，见 §10 |
| **范围** | 三形状合并：① 多提案常驻 Ambient · ② 稍后回灌续作 · ③ 持续驱动重算；分阶段交付 |
| **非范围** | 新 LLM skill；跨课程/跨会话作者记忆（属 C-13 域）；Dock 被动建议列表重构；改 `MuteState` 既有四级语义；新危险 action |
| **上游依赖** | C-03 `invalidate_focus`（`experience_shell.py:281`）；C-14 `inc_ambient` 计数（`metrics.py:102`）；C-16 ConflictGuard；E2.0 `proactive.py` / `ambient_banner.py` |

---

## 1. 背景与问题

`experienceai.md` §4.1 明确：Experience OS 当前残留两个**加深轴**（非主链路断裂）--

> 所谓「起步」残留的是 **覆盖面**（更多字段/面板挂内联）与 **持续度**（从按需触发到伴随式），而非主链路断裂。

A3 = **持续度**轴。§17 v4.65 收官后把 A3 列为批3 首项，但仅给标签，无行为定义。本文档补齐语义并定切片。

### 1.1 现状（E2.0 Ambient）

| 部件 | 现行为 | 位置 |
|------|--------|------|
| `evaluate_ambient` | 最多返回 **1** 条提案；按 priority 排序后取首条非 archived | `proactive.py:154` |
| `AmbientBanner` | 单条横幅；按钮：去处理 / 稍后 / 静音▾ | `ambient_banner.py:28` |
| 「稍后」(archive) | `pid` 进 `_ambient_archived`（**会话级**，关课清空）；提案本会话不再回灌 | `experience_skills_mixin.py:218` + `course_lifecycle.py:103` |
| 重算触发 | 仅 `_on_experience_context_changed` -> 400ms 防抖 -> `_refresh_ambient` | `app.py:1241` + `experience_skills_mixin.py:167` |
| 静音 | `MuteState` 四级 off/hours4/today/permanent，持久化 `experience_mute_json` | `proactive.py:21` + `experience_skills_mixin.py:160` |
| 计数 | `inc_ambient(stage)` ∈ shown/accepted/muted/dismissed；shown 经 `_shown_suggestion_keys` 指纹去重 | `metrics.py:102` + `app.py:1232` |

### 1.2 三个「不伴随」的缺口

1. **单条即清**：归档/接受首条后，若无非 archived 备选 -> `clear()`，Ambient 消失，作者失去「下一合理动作」的常驻提示。Dock 虽有 ≤3 被动列表，但无 accept/archive/mute 的主动语义、不随上下文轮替。
2. **稍后即永远消失**：`_ambient_archived` 会话内不再回灌；作者「稍后」往往意为「现在忙，回头再说」，而非「永不再提」。缺 relevance-based 回灌。
3. **按需触发非持续**：重算只在 `context_changed` 事件（选节点/资源编辑/AI 再校验脉冲）后跑；作者在字段里持续编辑不触发，Ambient 无法反映「刚改出来的新缺口」。

三形状分别对应这三缺口。**全部 local 驱动，零 LLM**（复用 `local_suggestions`）。

---

## 2. 设计决定一：① 多提案常驻 Ambient

**决定**：`evaluate_ambient` 演进为返回**有界队列**（N≤3），`AmbientBanner` 升级为常驻伴随条：展开最高优先级一条 + 折叠其余，归档/接受后**自动晋升**下一条，仅当队列空才 `clear()`。

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 队列上限 | **N=3** | 与 `local_suggestions(limit=3)`、Dock ≤3 对齐；认知负荷可控 |
| 返回类型 | `evaluate_ambient_batch(...) -> list[AmbientProposal]`；保留 `evaluate_ambient(...) -> AmbientProposal \| None` 作 `batch(...)[0]` 薄封装（向后兼容现有调用与测试） | 不破坏既有签名/黄金；新逻辑走 batch |
| 排序 | priority 升序（P0 先），同 priority 按 `proposal_id` 稳定字典序 | 确定性，可测 |
| 归档语义 | 归档 pid 后**晋升**下一条非 archived，而非清空 | 「常驻」核心行为 |
| 折叠展示 | 展开首条（含 body + 三按钮）；其余折叠为单行标题 + ▾ 展开 + ✕ 归档 | 不抢焦、不高耸 |
| 静音 | 仍走 `MuteState`：mute 生效 -> 整条清空（不变） | 复用 §8.7 |
| observer | `resolve_policy(...).is_observer` -> 清空（不变） | 三零 |
| 默认 | **默认开**（演化既有 default-on 的 Ambient，非新静默能力；mute 已可控） | 对齐 §6.4：display-only 无静默写 |

**非目标**：不与 Dock 被动列表合并。Dock = 常驻被动列表（点击派发）；Ambient = 主动优先队列（accept/archive/mute + 轮替 + 防抖重算）。两者数据同源（`local_suggestions`）但交互语义不同，保持分离。

---

## 3. 设计决定二：② 稍后回灌续作

**决定**：新增 `DeferStore`（持久化，QSettings JSON，镜像 `experience_mute_json` 模式）。「稍后」从「会话内永不再现」改为「冷却期后，若议题仍在且上下文相关，则回灌」。

### 3.1 DeferRecord 契约（闭集）

```text
DeferRecord:
  proposal_id: str          # = proposal_id_for(action_id, scope)，稳定
  action_id: str
  scope_fp: str             # scope 闭集指纹（section_id/first_lesson_id 等）
  deferred_at_iso: str      # 首次延后时间
  re_surface_after_iso: str # 冷却到期时间
  dismiss_count: int        # 累计延后次数（驱动退避）
```

**红线**：`scope_fp` 仅含 id/计数级信息（同 §14.5.3「validate level + 计数」级别），**不含**题目原文/options/prompt/附件原文。`DeferRecord` 不存 `title`/`body`（展示时由当前 `local_suggestions` 重算，避免 stale 文案）。

### 3.2 回灌规则（relevance predicate）

一条 deferred 提案在 `_refresh_ambient` 中**回灌**，当且仅当：

1. `now >= re_surface_after_iso`（冷却到期）；
2. 该 `proposal_id` **仍出现在当前** `local_suggestions(ctx)`（议题未消解）；
3. `dismiss_count < 3`（≤3 次退避；第 4 次起转永久归档，进 `_ambient_archived`，不再回灌）。

冷却退避：`re_surface_after_iso` = `now + base * 2^min(dismiss_count, 3)`，base = 15min。即 15min → 30min → 60min → 永久。**永不**在冷却期内回灌，杜绝 nag。

### 3.3 与 ① 的协作

`evaluate_ambient_batch` 的候选池 = `local_suggestions(ctx)` **减去** `_ambient_archived` **减去** 冷却未到期的 deferred；冷却到期且仍相关的 deferred **回流入候选池**并参与排序。回灌的提案带 `source="deferred_resurface"` 标记（metrics 区分）。

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 存储 | QSettings `experience_defer_json`（JSON list，cap 20，FIFO 淘汰） | 镜像 mute 持久化模式；cap 防膨胀 |
| 默认 | **默认关** `experience/defer_resurface` | nag 风险；对齐 §6.4 默认关；关时「稍后」退回旧行为（会话级 archive） |
| 关课 | 不清空 DeferStore（持久化）；`_ambient_archived` 仍会话级清空（不变） | 跨会话续作前提 |
| observer | observer 下不回灌（`_refresh_ambient` 已 early-return clear） | 三零 |

---

## 4. 设计决定三：③ 持续驱动重算

**决定**：新增**编辑驱动**的轻量重算路径，使 Ambient 在作者编辑过程中反映新缺口，而非仅响应 `context_changed` 事件。复用 C-03 `invalidate_focus` 的「原地 mutate + 重算 suggestions」快路径思想，但针对**内容增量**而非焦点增量。

### 4.1 触发点

| 触发 | 频率 | 路径 |
|------|------|------|
| 字段提交（lesson/item 表单 `editingFinished`、Ghost 接受、资源表行提交） | 事件级 | 调 `experience.invalidate(immediate=False)`（已有防抖）|
| 心跳（低频兜底） | 8s `QTimer`（仅 Ambient 可见且窗口激活时运行） | `_ambient_heartbeat_timer` -> 轻量 `_refresh_ambient` |

**不触发**：纯键盘输入 keystroke（避免 <50ms 预算超标 + 抢焦）。只在「提交」级事件触发。

### 4.2 内容增量快路径

`invalidate_focus` 仅刷焦点字段，**跳过** structure/quality/validate（这些是编辑后才会变的）。③ 需要一条「内容增量」路径：标记 `ctx` 为 stale（结构派生字段过期），但**不立即全量重算**；心跳或下一次 `context_changed` 时按需重算。即：

- 编辑提交 -> `experience.mark_stale()`（轻量：设标志 + 重启防抖 timer + 启心跳）
- 心跳/防抖到期 -> 若 stale，跑全量 `build_experience_context`（已有）；否则仅 `invalidate_focus` + `_refresh_ambient`

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 预算 | 重算本身 L-local <50ms（`proactive.py`/`local_suggestions` 纯函数）；全量 build 走防抖不阻塞 UI | §8.6 预算 |
| 抢焦 | Ambient 仅 `show_proposal`/`clear`，永不 `setFocus`；折叠项不展开动画抢眼 | 对齐 Ghost O-11 不抢焦原则 |
| 心跳 | 8s 且 `ambient_banner.isVisible() and self.isActiveWindow()` 才跑 | 窗口非活跃/静音时零开销 |
| 默认 | **默认关** `experience/ambient_live` | 持续重算有 perf/nag 感知；对齐 §6.4 |
| observer | observer 下心跳停、Ambient 清空（不变） | 三零 |

**非目标**：不做「逐字符流式重算」；不做 LLM 预判（能 local 不 LLM）。

---

## 5. 数据契约扩展（汇总）

### 5.1 `proactive.py`

```python
def evaluate_ambient_batch(
    ctx, *, mute=None, now=None, archived_ids=None,
    suggestions=None, limit=3, defer_store=None,
) -> list[AmbientProposal]:
    """N≤3 有界队列。defer_store（DeferStore|None）开启时执行回灌逻辑。"""

# 向后兼容：旧调用与黄金
def evaluate_ambient(ctx, *, mute=None, now=None, archived_ids=None,
                     suggestions=None) -> AmbientProposal | None:
    return (evaluate_ambient_batch(ctx, mute=mute, now=now,
            archived_ids=archived_ids, suggestions=suggestions, limit=1) or [None])[0]
```

`AmbientProposal` 增字段 `source: str = "local_suggestions"`（**已有**，无需改）；回灌提案 `source="deferred_resurface"`。

### 5.2 `DeferStore`（新纯模块 `backend/experience/defer_store.py`，无 Qt 永不抛）

```text
DeferStore:
  records: list[DeferRecord]            # cap 20
  add(proposal_id, action_id, scope_fp, *, now) -> None   # 退避算 re_surface_after
  is_cooled_down(proposal_id, *, now) -> bool
  should_permanent_archive(proposal_id) -> bool            # dismiss_count >= 3
  resurface_candidates(current_proposal_ids, *, now) -> list[str]
  to_dict() / from_dict()                                  # QSettings JSON
```

### 5.3 `metrics.py` 新 stage

`_AMBIENT_STAGES` 增 `deferred`、`resurfaced`（`inc_ambient("deferred")` / `inc_ambient("resurfaced")`）。`snapshot()` / `export_snapshot()` 自动纳入（已有 dict 旁路）。

### 5.4 `ExperienceContext` -- **不加字段**

伴随式所需全部由现有 `local_suggestions(ctx)` 产出，不扩 Context 维度（避免 C-18 section 缓存元组再扩维）。DeferStore 状态不进 Context（与 mute 同：app 持有，`_refresh_ambient` 注入）。

---

## 6. 分阶段交付切片

| 切片 | 内容 | 默认 | 粗估测 | 依赖 |
|------|------|------|--------|------|
| **P1** ① 多提案常驻 | `evaluate_ambient_batch` + `AmbientBanner` 队列/晋升/折叠 + `_refresh_ambient` 改读 batch + 旧 `evaluate_ambient` 薄封装 | 开 | ~12 | 无 |
| **P2** ② 稍后回灌 | `defer_store.py` + `experience_defer_json` 持久化 + 回灌规则 + `experience/defer_resurface` 设置 + metrics 2 stage | 关 | ~14 | P1 |
| **P3** ③ 持续驱动 | `mark_stale()` + 心跳 timer + 编辑提交触发点接线 + `experience/ambient_live` 设置 | 关 | ~10 | P1 |
| **P4** 收口 | 对抗测（D26-D28 nag/抢焦/脏盘）+ 门禁 G 文档 + experienceai.md §17 v4.66 条目 | - | ~6 | P1-P3 |

每切片独立可发、独立可回退（设置键关即退回旧行为）。**P1 可单独先发**（风险最低、收益最直观）。

---

## 7. 与既有契约一致性

### 7.1 设置键

| 键 | 默认 | 切片 | 说明 |
|----|------|------|------|
| `experience_mute_json` | 不变 | - | 既有 |
| `experience/defer_resurface` | **false** | P2 | ② 开关；关时「稍后」= 旧会话级 archive |
| `experience/ambient_live` | **false** | P3 | ③ 开关；关时仅 `context_changed` 驱动（旧行为） |
| ① 多提案 | 无新键（演化 default-on） | P1 | mute 已控；如需可逆，可加 `experience/ambient_mode`（single\|companion）留开放项 |

### 7.2 policy.py

**不加字段**。无危险 action、无新默认开写能力；`can_dispatch` 现有规则覆盖（accept 仍走 `_on_experience_suggestion` -> `dispatch_experience_action` -> `needs_confirm` + observer 零 AI 写 + M-08 预算闸）。

### 7.3 红线（对齐 §6.2 / §14.5）

| 红线 | 落地 |
|------|------|
| 能 local 不 LLM | 三形状均复用 `local_suggestions`，零 LLM |
| 不抢焦 | `show_proposal`/`clear` 永不 `setFocus`；折叠项无抢眼动画；心跳仅 `isVisible && isActiveWindow` |
| 不脏盘 | 提案为 display-only；accept 仍经 `dispatch_experience_action` -> 预览+确认+Undo（不变） |
| 可静音 | `MuteState` 四级覆盖整条；②③ 默认关 |
| observer 三零 | `_refresh_ambient` early-return clear（不变）；②③ 在 observer 下零触发 |
| redaction | `DeferRecord` 仅 id/计数级；`scope_fp` 闭集；不存 title/body/原文 |
| 失败安全 | `evaluate_ambient_batch`/`DeferStore` 永不抛；挂死路径走 statusBar 不模态 |
| 保 id | 不涉及结构写；accept 后派发的 skill 各自保 id（不变） |
| 无静默 Hard import | 不涉及（display-only） |

### 7.4 计数去重

`shown` 仍走 `_shown_suggestion_keys` 指纹去重（`app.py:1232`）。多提案下：每条提案独立指纹，shown 计真实曝光条数；回灌提案 `source="deferred_resurface"` 但 `proposal_id` 不变 -> 同指纹不重复计 shown，回灌计 `resurfaced`。

---

## 8. 测试门禁

| 层 | 测试 | 切片 | 数 |
|----|------|------|----|
| `evaluate_ambient_batch` | 队列上限 N=3 / 排序稳定 / archived 跳过 / 空 ctx 返回 [] / mute 生效返回 [] / observer 由调用方清空（纯函数不测 observer） | P1 | 6 |
| AmbientBanner | 队列展示 + 晋升（归档首条 -> 显示次条）/ 队列空 clear / 折叠展开 / 不抢焦（无 setFocus） | P1 | 6 |
| 旧 `evaluate_ambient` 兼容 | 仍返回首条或 None（黄金不破） | P1 | 2 |
| DeferStore | add 退避 / is_cooled_down / dismiss_count>=3 永久 / resurface_candidates 仅返回当前仍存在的 / cap 20 FIFO / 永不抛 / 闭集无原文 | P2 | 8 |
| 回灌集成 | 冷却未到期不回灌 / 到期且议题在则回灌 / 议题消失不回灌 / dismiss>=3 转永久 / `defer_resurface=False` 退旧行为 | P2 | 5 |
| 设置 round-trip | `experience/defer_resurface` + `experience/ambient_live` default false + clone + 五处 round-trip | P2/P3 | 4 |
| mark_stale + 心跳 | 编辑提交 -> mark_stale -> 防抖到期全量 / 心跳仅 isVisible&&isActiveWindow 跑 / `ambient_live=False` 退旧行为 / observer 零心跳 | P3 | 5 |
| metrics | `inc_ambient("deferred")`/`("resurfaced")` 计数 + snapshot 含新 stage | P2 | 2 |
| 对抗 D26-D28 | D26 nag（冷却期内不回灌 + dismiss>=3 永久）/ D27 抢焦（无 setFocus）/ D28 脏盘（accept 仍经确认+Undo） | P4 | 6 |
| **合计** | | | **~44** |

**门禁**：不新增 G（沿用 G9/G10/G11 既有 observer/dangerous/预算闸语义）；P4 对抗测进 `test_adversarial_matrix` docstring 覆盖表。

**验证命令**（日常 L0+L1，发版 full）：

```bash
make test-gui          # L0 gate + L1 fast
make test-gui-gate     # Experience 门禁
make test-gui-full     # 全量（BASELINE 真源）
```

---

## 9. 风险与开放项

| 风险 | 缓解 |
|------|------|
| 多提案与 Dock 被动列表视觉重叠 | 语义分离（Ambient 主动+轮替+accept/archive/mute；Dock 被动列表）；折叠展示降视觉占用；必要时 Ambient 限定 source=proactive 子集 |
| ② 回灌变 nag | 冷却退避（15→30→60min→永久）+ dismiss_count>=3 永久归档 + 默认关 + 仅议题仍在才回灌 |
| ③ 心跳耗 CPU | 8s 且仅窗口活跃+Ambient 可见时跑；`ambient_live` 默认关；stale 标志避免无谓全量 |
| `evaluate_ambient` 旧调用方漏改 | 薄封装保持签名；全量 grep 调用方；黄金集回归 |
| DeferStore 持久化膨胀 | cap 20 FIFO；dismiss>=3 转会话级 archive 不进 store |
| ③ 编辑触发点遗漏 | 仅接 `editingFinished`/Ghost 接受/资源行提交三个稳定信号；keystroke 不接 |

**开放项**（留远期，不在本批次）：

1. `experience/ambient_mode`（single\|companion）可逆开关 -- 若 P1 默认开 companion 后用户反馈过吵再加；
2. 跨会话作者意图记忆驱动回灌（与 C-13 `ExperienceMemory` 联动）-- 属 C-13 域；
3. 多提案优先级的作者画像调权（`author_profile` 影响 priority）-- 需画像成熟度，远期；
4. ③ 的「内容增量」精确快路径（只重算受影响 section 的 quality）-- 需 section 级脏标记，超本批次。

---

## 10. 实施记录

**实施记录（v4.66，2026-07-24）**：已按本设计落地 P1–P4 全部切片。

- **P1 多提案常驻**：`proactive.evaluate_ambient_batch`（N≤3 队列 + 去重 + 排序 + archived 跳过 + defer_store 内联隐藏/回灌标签）；`evaluate_ambient` 降为薄封装（向后兼容 1 生产调用方 + 3 测试）；`AmbientBanner` 队列展示（首条展开 + 余折叠 + ✕归档，永不 `setFocus`）；`_refresh_ambient` 改读 batch + `show_proposals`；`_on_ambient_accepted` 改 `_refresh_ambient` 晋升（不清屏）。默认开。
- **P2 稍后回灌**：新纯模块 `backend/experience/defer_store.py`（`DeferRecord` 闭集 + `DeferStore` 退避 15→30→60min→永久，cap 20 FIFO，永不抛）；`experience_defer_json` QSettings 持久化（镜像 mute）；`_on_ambient_archived` 按 `experience_defer_resurface` 分流（defer vs 会话 archive）；`_refresh_ambient` 接 defer_store + `purge_resolved`；`metrics._AMBIENT_STAGES` 加 `deferred`/`resurfaced`。默认关。**实现偏差**：批处理 defer 逻辑改为内联（隐藏 in_cooldown + 标签 cooled_defer），保留真实 priority，比原「追加 priority=98」更准。
- **P3 持续驱动**：`ExperienceShell.mark_stale()` + `_content_stale` 标志（`_rebuild_now` 清除）；`app.py` 8s 心跳 `_ambient_heartbeat`（`_on_ambient_heartbeat` 守卫：`ambient_live or defer_resurface` + observer + `isActiveWindow && isVisible`，stale→invalidate 否则 `_refresh_ambient`）；`_on_experience_resources_changed` 改 `mark_stale`。默认关。
- **P4 对抗+收口**：`test_adversarial_matrix` 加 D26（defer 不 nag + 永久）/ D27（无 setFocus 源码契约）/ D28（accept 经 dispatch 漏斗）。

**实测**：新增测 `test_experience_ambient_batch`(15) · `test_defer_store`(8) · `test_experience_defer_resurface`(6) · `test_experience_ambient_live`(5) · `test_experience_shell` +3(stale) · `test_adversarial_matrix` +3(D26-28) · `test_experience_metrics` +2(stage) · `test_settings_dialog` +1(round-trip) +1(check count 14→16)。L1 fast 1380→约 1399+；gate 32/32 不降。红线保持：能 local 不 LLM / 不抢焦 / 不脏盘（accept 经 `dispatch_experience_action`+确认+Undo）/ 可静音 / observer 三零 / redaction（DeferRecord 闭集无原文）/ 永不抛。无新 G 门禁、不加 Context 维度、不加 policy 字段。

**实施前置确认**（已完成）：

- [x] P1 前确认 `evaluate_ambient` 全部调用方（`grep -rn evaluate_ambient src/`）已兼容薄封装 — 仅 1 生产调用方 + 3 测试；
- [x] P2 前确认 `experience_defer_json` QSettings 键名不与既有键冲突；
- [x] P3 前确认 `mark_stale` 与 C-03 `invalidate_focus` 的 stale 语义不冲突（前者内容 stale、后者焦点 fast-path）；
- [x] 每切片跑 `make test-gui-gate` + 对应新测文件；
- [x] 对抗测 D26-D28 进 `test_adversarial_matrix` 覆盖表。
