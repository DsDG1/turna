# GUI AI 重构契约（M0 / M1）

> 新人 10 分钟入口：改 AI 能力时读本文 + `src/backend/ai/`。  
> 配套计划：大批量结构修复 M0–M8。边界扫描：`python3 tool/gui/tool/check_ai_boundaries.py`。

## 1. 红线（不得破坏）

| 红线 | 说明 |
|------|------|
| API Key 不落盘 | 仅内存；Settings 不序列化 `ai_api_key` |
| 写盘必经预览 + 确认 + Undo | Experience / merge / fix 路径 |
| id 默保 | splice / structural_diff / pipeline Fix 回滚删 id |
| 不自动 import 课程 | pipeline 停在 `READY_IMPORT` |
| Prompt 文本稳定 | 拆分不得改 prompt 字符串（cache key / 金测） |

## 1b. 生成入口（M2）

| 路径 | 用途 |
|------|------|
| **`src.backend.ai.facade.generate_course`** | **唯一对外生成入口**（工坊 DesignController） |
| `mode=fast` | single-shot + validate retry |
| `mode=refine`（别名 `phased`） | 全流水线 `run_pipeline` |
| chat_history 非空 | `generate_from_chat` 分支 |
| `ai_phased.request_course` | 遗留 thin wrapper（outline→lesson，非完整 pipeline） |

## 1c. 配置注入（M3）

- `src.application.ai_runtime.AiRuntime` / `runtime_from_host`
- **dialogs/** 禁止 `from src.app import current_ai_config|current_settings`
- 门禁：`python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-app`

## 1d. Experience 分发（M4 / M7）

- **入口**：`src.application.experience_dispatch.dispatch_experience_action`
- **注册表**：`experience_handlers.registry.HANDLERS` — 懒 `getattr(module, "handle_*")`，便于 mock
- **实现体**：`experience_handlers/{fill,regenerate,quality,resources,multimodal,memory_nav}.py`
- **Mixin**：`experience_skills_mixin` 仅 ambient/policy + 薄 `_experience_*` 包装（测试/树直接调用）
- **新增 skill**：`ACTIONS` + `registry.HANDLERS` + `handle_*`（可选 host 包装）
- **测 mock**：`patch("…handlers.fill.handle_fill_empty")`；**不要**只 mock `host._experience_*` 期望 dispatch 命中
- 覆盖测：`tests/test_experience_dispatch.py`

## 1e. Suggestions 拆分（M6）

- **聚合**：`src.backend.experience.suggestions.ambient.local_suggestions`
- **收集器**：`p0_validate` / `p1_empty` / `p2_*` / `p3_*`
- **兼容**：`context_bus.local_suggestions` re-export

## 1f. 节点 AI 编辑（M5）+ 遗留对话框（M8）

- **生产路径**：树 AI 编辑 → `dialogs/ai/node_edit_dialog.NodeAiEditDialog`
- **底层**：`generate_edit` / `regenerate_*_in_section`
- **LEGACY**：`AiGeneratorDialog`（文件头标注）— 工坊生成 UI + 测试；**禁止**再扩 edit_mode
- 新 edit 能力只改 `NodeAiEditDialog`

## 2. 包布局（M1 后真源）

```text
src/backend/ai/
  config.py           # AiApiConfig, AiCourseSpec, ChatMessage, SYSTEM_*
  client.py           # request_chat, verify_connection
  parse.py            # parse_completion, content_text
  prompts.py          # build_prompt / alignment / edit / response_format
  validate_loop.py    # generate_with_validate_loop, coerce_problem_messages
  resource_fix.py    # normalize_resources, auto_fix_resources
  section_ops.py      # fill_*, diff, splice, regenerate, transforms
  course_generate.py  # request_course_with_retry, generate_from_chat, explain, generate_edit
  __init__.py         # 稳定 re-export

src/backend/ai_generator.py   # 兼容薄层：旧 import / monkeypatch 路径
```

**新代码优先** `from src.backend.ai import …`。  
**旧路径** `from src.backend.ai_generator import …` 在过渡期内保持可用。

## 3. 公开 API 白名单（目标态）

### 配置 / 类型
`AiApiConfig`, `AiCancelled`, `AiCourseSpec`, `ChatMessage`,  
`SYSTEM_AUTHORING`, `SYSTEM_EDITING`, `SYSTEM_CORRECTION`,  
`SYSTEM_AUTHORING_CHAT`, `SYSTEM_AUTHORING_EDIT`

### 网络
`request_chat`, `verify_connection`, `chat_json`

### 解析 / 资源
`parse_completion`, `content_text`,  
`normalize_resources`, `auto_fix_resources`, `iter_items`

### 生成闭环
`generate_with_validate_loop`, `coerce_problem_messages`,  
`build_response_format`, `build_prompt`, `build_alignment_prompt`, `build_edit_prompt`

### 课程级
`request_course_with_retry`, `generate_from_chat`, `request_alignment_reply`,  
`explain_course`, `generate_edit`, `detect_genre_from_spec`, `apply_genre_to_spec`

### 局部 / 修复
`fill_needs_review_resources`, `fill_listening_gaps`,  
`regenerate_lesson_in_section`, `regenerate_unit_in_section`,  
`request_lesson_transform`, `request_item_transform`, `request_correction`,  
`splice_lesson_in_place`, `structural_diff`, `full_section_diff`

## 4. 禁止事项

1. **包外** `from src.backend.ai_generator import _foo` 或 `from src.backend.ai.* import _foo`  
   （包内可用 `_` 作实现细节；对外需公开名。兼容层 `ai_generator` 可 re-export 旧 `_` 别名供测试。）
2. **dialogs/** 依赖 `from src.app import current_ai_config` — M3 目标清零（M1 不强制）。
3. 业务模块自写第二套 HTTP 客户端（必须走 `request_chat`）。
4. 为拆分而改 prompt 字面量。

## 5. 热点行数基线（M1 开工前 / 后）

| 路径 | M1 前 | M1 后（实测） |
|------|-------|----------------|
| `ai_generator.py` | ~2670 | **159**（薄 re-export） |
| `ai/config.py` | — | 192 |
| `ai/client.py` | — | 420 |
| `ai/parse.py` | — | 103 |
| `ai/prompts.py` | — | 678 |
| `ai/validate_loop.py` | — | 189 |
| `ai/resource_fix.py` | — | 177 |
| `ai/section_ops.py` | — | 825 |
| `ai/course_generate.py` | — | 276 |
| `ai/__init__.py` | — | 132 |

单文件目标：AI core ≤900 行（`section_ops` / `prompts` 接近上限，M2+ 可再拆）。

## 6. 里程碑状态（M0–M8）

| 编号 | 内容 | 状态 |
|------|------|------|
| M0 | 契约文档 + 边界扫描 | ✅ |
| M1 | `backend/ai/` 拆包 + 薄 `ai_generator` | ✅ |
| M2 | `generate_course()` 单一 facade | ✅ |
| M3 | dialogs 配置 DI（`AiRuntime`），禁止 `src.app` | ✅ |
| M4 | Experience handler 注册表 + dispatch | ✅ |
| M5 | 树编辑 → `NodeAiEditDialog`；巨石标 LEGACY | ✅ |
| M6 | suggestions collectors 拆分 | ✅ |
| M7 | skill 体迁入 `experience_handlers/*` | ✅ |
| M8 | LEGACY 标注 + 契约收口 | ✅ |

## 7. 测试门禁

```bash
# 边界扫描（M1 后 private 跨包应为 0）
python3 tool/gui/tool/check_ai_boundaries.py --fail-private

# 日常
make test-gui-ci

# AI 核心子集
QT_QPA_PLATFORM=offscreen python3 tool/gui/run_gui_tests.py fast
# 或指定：test_ai_generator test_ai_pipeline test_ai_phased test_ai_stream test_ai_cache
```
