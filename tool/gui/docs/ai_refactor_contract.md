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
- **backend/、application/** 禁止 `from src.app import …`：非 dialog 代码经
  `src.application.runtime_context.current_settings|current_ai_config` 读取
  （MainWindow 启动时注册 provider，关闭时注销）
- 门禁：`python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-app --fail-backend-app`

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

- **生产路径**：树 AI 编辑 → `experience_handlers.edit.handle_node_edit` → `MainWindow._on_ai_edit` → `AiEditController.handle_ai_edit` → **`NodeAiEditDialog`**（`dialogs/ai/node_edit_dialog.py`，2026-09 收口；构造签名 `scope/scope_id/existing_section`）
- **共享引擎**：`ai_generator_dialog.SectionAiDialog` 承载 normal/wish 生成与 edit_mode 引擎的唯一实现；`AiGeneratorDialog` 是其上的工坊生成专用壳（LEGACY 名称保留），公开签名**不再接受** `edit_mode`
- **底层**：`generate_edit` / `regenerate_*_in_section`（经 `GeneratorWorkerHub.make_edit_worker`）
- **LEGACY**：`AiGeneratorDialog`（文件头标注）— 工坊生成 UI + 测试；**禁止**再扩 edit_mode

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
| M5 | 树编辑 → `NodeAiEditDialog`；巨石标 LEGACY | ✅（2026-09 复核落地：`NodeAiEditDialog` 恢复为生产入口，`AiGeneratorDialog` 公开签名去 edit_mode） |
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

## 8. Experience host 契约与债务棘轮（2026-09 补充）

- **host 协议化**：experience handler/controller 的 host 参数统一注解为
  `src.application.experience_host.ExperienceHost`（typing.Protocol，结构化匹配，
  MainWindow 无需改继承）。协议声明了 handler 层实际访问的全部 113 个成员
  （23 公开 + 90 内部契约）。backend 侧（`auto_apply.py` / `precognition.py`）
  刻意保留 `host: Any`，避免 backend → application 反向 import。
- **防漂移门禁**：`--fail-undeclared-host-access` —— 已注解模块出现未声明
  的 `host._x` 访问即失败；新增耦合必须先写进协议。
- **backend → UI 禁令**：`--fail-backend-ui` —— backend/ 禁止 import
  widgets/dialogs/teacher/theme/app（error_mapper、TEMPLATE_BADGES 已下沉 backend）。
- **backend → Qt 禁令**：`--fail-backend-qt`（2026-09 新增）—— backend/ 禁止
  import PySide6。原 4 处 Qt 耦合已清：`credential_store` / `git_remote_catalog` /
  `ai_prompt_library` 迁往 `src/application/`（纯持久化 helper，调用方全在
  dialogs/app 层）；`generate_audio_worker` 拆分为纯逻辑
  `generate_audio_client.run_tts_generation` + Qt 壳 `application/audio_worker.py`。

## 9. P2/P3 债务清理基线（2026-09）

- **MainWindow 瘦身**：app.py 1457 → 1107 行 —— closeEvent→`close_controller`、
  工坊/教材导入 7 方法→`workshop_controller`、总览 4→`overview_controller`、
  资源 3→`resources_controller`、校验报告→`validation_controller`；
  死代码（重复定义的 `_on_undo_index_changed` 等）已删。`_save_course_async`
  保留在 app（与 `save_host.execute_save` 语义不同：后台直存 vs SavePipeline）。
- **Mixin 收口**：`experience_skills_mixin` 691 → 421 行，ambient 组 11 方法
  迁至 `application/ambient_controller.py`（模块函数 + ExperienceHost 注解），
  mixin 仅剩 policy/funnel + 薄包装；协议新增
  `_defer_store`/`_ambient_mute`/`_heartbeat_wait_idle`/`_ambient_heartbeat`/
  `_save_worker`。孤儿心跳定时器代码（无创建点、相关测试整类 skip）暂保留。
- **GitLibraryDialog 按域拆分**：1631 → 425 行壳 + `dialogs/git_library/`
  包（`git_worker_hub`/`sync`/`remotes`/`branches`/`repo_browser`/`lan_share`/
  `memo`，模块函数以 `dlg` 为上下文）；`textbook_library_dialog` 复用
  `GitWorkerHub` 消除镜像 plumbing。全部 widget 属性名与方法名保留。
- **顺延项**：`run_pipeline`（250 行）/`run_item_chip`（243 行）巨型函数拆分；
  138 处内联 `setStyleSheet` 全量收口（硬编码 hex 9 处已清）。
- **吞异常棘轮**：`--max-except-pass 0` —— 全 src 静默 `except: pass` 数量
  已全部清零（0 处）。全仓（含 dialogs/widgets/teacher 等 UI 层）已全部改为
  `logger.debug/warning(..., exc_info=True)` 防御性日志记录，彻底杜绝黑盒静默失败。
  （2026-09 补记：Qt signal disconnect 守卫处曾回归 4 处
  `except Exception: pass`，已改为
  `except (TypeError/RuntimeError[/AttributeError]) + logger.debug(..., exc_info=True)`
  并与 `generator_worker_hub` 既有惯例对齐；门禁重回 0，见
  `dialogs/ai_fix_dialog.py:_disconnect_worker` 与
  `dialogs/ai/design_controller.py:_disconnect_worker`。）
- **循环依赖**：experience 三元环已切（actions 为纯叶子，`is_dangerous_skill_allowed`
  真源在 policy）；`ai_error_analyzer` 直接引用 `dialogs/ai/worker`。
- **完整门禁命令**：

```bash
python3 tool/gui/tool/check_ai_boundaries.py \
  --fail-private --fail-dialogs-app --fail-backend-app \
  --fail-backend-ui --fail-backend-qt --fail-undeclared-host-access --max-except-pass 0
```
