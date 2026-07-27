# E4 M-01 附件进 Context —— 设计文档

| 字段 | 值 |
|------|-----|
| **文档编号** | `VAR-GUI-EXP-M01-DESIGN` |
| **版本** | v1.1（v4.36 已实施） |
| **日期** | 2026-07-22 |
| **上游规范** | `tool/gui/experienceai.md` v4.36（§2.4 E4、§8.2 attachments、§14.5.3、§16.3 M-01） |
| **状态** | ✅ 已实施（v4.36）；本文档留作契约存档 |
| **范围** | 已有 PDF/Word/图片/文本抽取 → `ExperienceContext.attachments` 摘要快照 + 感知建议 |
| **非范围** | OCR 建议链（M-03）、语音（M-04）、截图解释（M-05）、附件内容自动喂 LLM、课程 JSON 契约变更、附件持久化落盘 |

---

## 1. 背景与问题

`experienceai.md` §16.3 将 M-01 列为 E4 第一项，并标注「需先定附件来源 / 感知建议 / §14.5.3 redaction 设计」。本文档对这三个待定项给出明确决定。

代码现状：

- 抽取能力已就绪：`src/backend/attachment_extractor.py`（纯 Python、懒加载 PyPDF2/python-docx），产出 OpenAI 兼容 content piece。
- 附件载体：`AttachmentRecord`（`src/dialogs/ai/worker.py:20`，dataclass `{temp_path, original_name, content}`，无 Qt）。
- 现状断点：附件生命周期止于「一次 AI 对话的 messages」，**无任何进 Context 的路径**；`ExperienceContext.attachments`（`context_bus.py:107`）字段已占位但恒为空、无消费方。
- 可复用先例：v4.28 `workshop_draft` 链路（纯函数闭集快照 → 窗口 snapshot 方法 → `app.py` → Shell setter → Context/Dock 一行）。

## 2. 设计决定一：附件来源（生产方）

**决定**：唯一生产方为**工坊附件条**（`AttachmentBar.attachments()`，经 `design_panel` 持有的 `AttachmentRecord` 列表）。许愿生成对话框（`ai_generator_dialog`）的附件**本切片不接入**。

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 首选来源 | 工坊 `AttachmentBar` | 最现成生产方；附件在工坊有稳定宿主（chip 条），生命周期与工坊窗口一致，天然适合「窗口 snapshot → Shell」链路 |
| 许愿对话框附件 | 排除（本切片） | 对话框是临时模态会话，附件随对话框销毁；接入会让 Context 持有指向已销毁对象的 ref，stale 风险大于收益。后续若需要，用同一 `attachments.py` 契约加 `source="generator"` 即可扩 |
| 课程磁盘目录扫描 | 排除 | 课程契约（`docs/authoring/course-layout.md`）无附件字段；扫描发明新真源，违反「Single Adapter / JSON Ground Truth」（§6.1） |
| 教材 project.json 持久化 | 排除 | 教材项目契约无附件条目；动契约属语义变更，超出 M-01 最小切片 |

**生命周期**：纯内存快照。附件在工坊增删 → 工坊推送新快照 → Shell 注入 → 关课 `set_adapter(None)` 时一并清空（对齐 §12.4 #8「关课清空」检查项）。

**落盘决策**：**不落盘**。理由：① 对齐 C-13「默认零落盘」与 Timeline「默认仅内存」的既有 ADR（§15）；② 附件原文属 §14.5.3「用户未保存的隐私附件原文」，落盘即制造泄密面；③ 快照只是导航/感知元数据，重建成本为零（用户重新拖入即可）。

## 3. 设计决定二：快照形状（数据契约）

**核心红线**：`AttachmentRecord.content` 含抽取全文 / base64，**一律不进 Context**。Context 只持闭集摘要；原文留在工坊侧，按 `ref_id` 间接取用。

### 3.1 新纯模块 `src/backend/experience/attachments.py`

仿 `workshop_draft.py` 的四件套（无 Qt、永不抛）：

```text
ATTACHMENT_KEYS = frozenset({
    "ref_id",        # 稳定引用 id（工坊侧铸造，如 "att-{uuid8}"）
    "name",          # 原始文件名 basename，不含目录
    "kind",          # "pdf" | "word" | "image" | "text" | "other"
    "char_count",    # 抽取文本字数（图片为 0）
    "preview_hash",  # 内容短 hash（sha256[:12]），用于变更检测与去重，不可逆
    "source",        # "workshop"（本切片唯一值；预留 "generator"）
    "attached_ts",   # float epoch
})

build_attachment_snapshot(records) -> list[dict]   # AttachmentRecord 列表 → 闭集快照列表
normalize_attachments(raw) -> list[dict]           # 任意输入 → 闭集形状；非法条目丢弃；永不抛
format_attachments_line(attachments) -> str        # Dock 一行，如「附件 3 · 2 PDF · 1 图」
```

约束（对齐 `workshop_draft.py` 既有约定）：

- 所有值强转（str/int/float），`name` 只取 `os.path.basename`；
- `preview_hash` 由抽取内容计算，**不**存内容本身；
- 整个 body 包防御，任何单条损坏不拖垮 rebuild（§14.5.2「quality 计算异常 → 跳过」同款精神）；
- 列表 cap（建议 ≤50 条），防病态输入。

### 3.2 注入链路（复制 workshop_draft 模式）

```text
WorkshopWindow.experience_attachments_snapshot()   # 从 AttachmentBar 读 records → build_attachment_snapshot；异常→[]
        │  （app.py 在工坊附件变化 / 打开工坊时调用，对齐 app.py:1272-1279 现有 draft 接线点）
        ▼
ExperienceShell.set_attachments(list)              # normalize 消毒阀 → invalidate() 防抖
        ▼
build_experience_context(..., attachments=...)     # 新关键字参数，默认 None → []
        ▼
ExperienceContext.attachments                      # 已有占位字段，类型收窄为 list[dict]
```

同步策略：

- `_rebuild_now` 全量路径：传 `self._attachments`（对齐 `set_workshop_draft` 在 `:338` 的处理）；
- `invalidate_focus` 快路径：**附件不随焦点变化**，快路径无需触碰（与 workshop_draft 不同——draft 进 focus 快路径是因钉住/焦点联动；附件无此需求，保持快路径最小）；
- 关课：`set_adapter(None)` 内 `self._attachments = []`（对齐 §12.4 #8）。

### 3.3 原文取用（间接引用）

Context 消费者（未来 skill）需要原文时，**不得**从 Context 取，而是：

```text
skill 持 ref_id → app 层查当前工坊 AttachmentBar → 取 AttachmentRecord.content
```

ref_id 失效（附件已删 / 工坊已关）→ skill 走「无附件」降级路径，**禁止**报错阻塞（§14.5.2 失败安全默认）。本切片没有消费原文的 skill，仅定义此约定供后续（如 M-03 OCR 链、附件感知生成）遵守。

## 4. 设计决定三：感知建议（local_suggestions 落点）

**决定**：新增一条 P2 并列建议，仿 `listening_gaps`（`context_bus.py:435` 一带）的写法。

| 项 | 内容 |
|----|------|
| 触发条件 | `ctx.attachments` 非空 |
| 优先级 | **P2**（与待补/资源卫生同档；附件是「可用素材」而非「课程缺陷」，不配 P0/P1） |
| 标题 | `N 个附件可用于生成`（N = len，cap 显示） |
| action_id | **`attachment.open_in_workshop`**（只读导航：聚焦/打开工坊面板；`needs_confirm=False`，`dangerous=False`） |
| scope | `{"count": N, "ref_ids": [...][:20]}`——只放 id/计数，**不放 name 以外的任何内容**，name 也仅在 Dock 行展示不进 scope |
| 入口 | Dock 建议 + ⌘K 斜杠候选 `/attachments`（路由黄金集同步 +1） |

**明确不做**（本切片）：

- 不自动把附件内容喂给 LLM（「能 local 不 LLM」原则 + 费用红线 §14）；
- 不做 OCR/语音/截图（M-03/M-04/M-05 另行，且各自需独立默认关开关）；
- 不做「附件 ↔ 课程缺口」的语义匹配（需 LLM，属 E4 后续切片，届时新键默认关）。

## 5. 设计决定四：§14.5.3 redaction 规则（核心待定项）

**决定**：继续**调用方纪律**，不给 telemetry 加集中 redact 层。

| 备选 | 取舍 | 理由 |
|------|------|------|
| 集中 redact 层（telemetry 入口扫敏感键） | **不采用** | ① 现状零 redact 先例，加层等于承认「调用方可能乱放」，反而弱化纪律；② 集中层只能按键名猜，附件原文走 `content`/`text` 这类通用键，误伤与漏防并存；③ 闭集快照（§3.1）已从源头保证原文不在 Context/scope 里——**最好的 redact 是敏感数据根本不到达记录点** |
| 调用方纪律 + 闭集快照 + 测试锁定 | **采用** | 与 v4.35 K-24 完全同款：Timeline 只记 action_id + 短 summary，且用「隐私不泄漏」单测锁死 |

**可记 / 不可记清单**（写入 §14.5.3 表格的 E4 行）：

| 可记 | 不可记 |
|------|--------|
| `ref_id`、`kind`、`char_count`、`action_id` | 附件原文、抽取文本任何片段、base64 |
| `name`（仅 basename，且不进 telemetry——仅 Dock 展示） | 完整文件路径（含用户 home） |
| 附件计数（如 `attachment_count`） | `preview_hash` 之外任何可逆内容派生物 |

**既有纪律确认**（`ai_generator_dialog.py:1890` 已只记 `attachment_count`，本设计不改动）。

**LLM messages 边界**：附件抽出文本进 messages 是既有行为（design_panel/ai_generator_dialog），本切片不新增该路径。纪律维持：messages 不落盘、不进 telemetry payload、Timeline 不记。**新增测试锁定**（见 §6.3）：断言 `build_attachment_snapshot` 输出 JSON 中不含抽取文本子串——把「原文不泄漏」从纪律变成回归测试。

## 6. 与既有契约的一致性检查

### 6.1 设置键

**决定**：**不新增设置键**。附件快照注入是只读感知（非 AI 写、非 LLM、非主动提案），与 `workshop_draft` 同级——后者亦无独立开关。§6.4「新能力默认关」针对的是有侧效应的能力（写树/LLM/自动应用）；纯 Context 字段填充不属于此列。Observer 模式下注入照常（observer 约束的是 AI 行为，不是上下文可见性，§5.2「Observer 不得半关」针对 AI 侧效应）。

### 6.2 policy.py

**决定**：**不加字段**。本切片无 AI 写、无 LLM、无危险 action；`attachment.open_in_workshop` 是只读导航，`can_dispatch` 现有规则（`needs_confirm=False` 放行）已覆盖。

### 6.3 测试规划（实施切片时执行）

| 层 | 测试 | 预估用例数 |
|----|------|-----------|
| 纯函数 | build/normalize/format：闭集、强转、cap、永不抛、**原文不泄漏**（快照 JSON 不含抽取文本子串） | ~8 |
| Shell | set_attachments round-trip、normalize 消毒、关课清空、focus 快路径不触碰 attachments | ~4 |
| 建议 | local_suggestions P2 条目产出 / 空 attachments 不产出 / scope 闭集 | ~3 |
| 路由 | 黄金集 +1（`/attachments`） | ~1 |

预估 BASELINE +16 上下；门禁（G9–G16）不受影响，无需新 G 项（无危险面）。

### 6.4 实施步骤预览（本轮不执行）

按 §12.1/§12.2 清单，后续实施切片最小步骤：

1. 新建 `src/backend/experience/attachments.py`（§3.1 四件套）；
2. `context_bus.py`：`build_experience_context` 加 `attachments=` 参数；`local_suggestions` 加 P2 条目；
3. `actions.py` 注册 `attachment.open_in_workshop`（`needs_confirm=False`）；`intent_router` 加 `/attachments`；
4. `experience_shell.py`：`set_attachments` + `_rebuild_now` 传参 + `set_adapter(None)` 清空；
5. `WorkshopWindow.experience_attachments_snapshot()` + `app.py` 接线（对齐 1272-1279 draft 接线点）；
6. Dock：`format_attachments_line` 一行（对齐 `experience_dock.py:288-290`）；
7. 派发：`_on_experience_suggestion` 单漏斗内聚焦工坊（只读导航，无 Guard/Job）；
8. 测试（§6.3）+ BASELINE + experienceai.md §2/§11/§17 同步（实施时升次版本）。

## 7. 风险与开放项

| 风险 | 缓解 |
|------|------|
| 附件增删时 app.py 接线点遗漏导致快照 stale | 实施时在 AttachmentBar 增删处统一调 snapshot 推送；关课时清空兜底 |
| ref_id 指向已销毁工坊对象 | Context 只持摘要；原文取用走 §3.3 降级约定 |
| 后续「附件内容喂 LLM」诉求绕过本契约 | 本文 §4 明确排除；届时需新切片 + 新键默认关 + 更新 §14.5.3 |
| 快照内存占用 | 摘要仅闭集标量，50 条 cap，可忽略 |

**开放项**（已决，v4.36 实施时定案）：

1. ~~`preview_hash` 是否保留~~ → **保留**：兼作 `ref_id` 派生源（`att-{hash}`，内容派生、跨 rebuild 稳定、天然去重）；`attached_ts` 则**去除**（无消费方，且每次 snapshot 铸造 ts 会造成快照抖动）。
2. ~~`/attachments` 斜杠是否首期上~~ → **上**（slash-only，不加「附件」关键词规则，避免自由文本误拦截）。

**实施记录（v4.36，2026-07-22）**：已按 §6.4 八步落地。`src/backend/experience/attachments.py`（build/normalize/format，闭集 `{ref_id,name,kind,char_count,preview_hash,source}`，cap 50）；Shell `set_attachments` + focus 快路径同步 + 关课清空；`DesignPanel.attachment_records()` + `attachments_changed` 信号（AttachmentBar 转发）→ `WorkshopWindow.attachments_changed` → `app._on_workshop_attachments_changed`；Dock 附件行；`attachment.open_in_workshop` + `/attachments`（黄金 65→66）；`test_experience_attachments.py` 24 测（含原文/base64 不泄漏锁定）。
