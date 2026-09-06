# E4 多模态后续切片 —— 设计文档（M-03 / M-04 / M-05）

| 字段 | 值 |
|------|-----|
| **文档编号** | `VAR-GUI-EXP-M0345-DESIGN` |
| **版本** | v1.0（设计文档，未实施） |
| **日期** | 2026-07-22 |
| **上游规范** | `tool/gui/docs/archive/experienceai.md` v4.37（§2.4 E4、§10.5、§16.3、§14.5.3） |
| **状态** | **M-03 ✅ v4.40–v4.42** · **M-05 ✅ v4.38** · **M-04 ✅ v4.44**（见 §2.6）；三切片均默认关 + 可选依赖懒加载 |
| **范围** | M-03 OCR 建议链（K-23）· M-04 语音→Palette · M-05 试做截图解释 —— 三个 E4 多模态切片的统一设计 |
| **非范围** | 本文档不写实现代码；不新增课程 JSON 契约字段；不引入强制依赖；不改 policy.py 默认档 |

---

## 0. 三切片总览

| 切片 | 一句话 | 触发点 | 输出 | 默认开关 | 可选依赖 |
|------|--------|--------|------|----------|----------|
| **M-03** OCR 建议链 | 图片附件 / 扫描 PDF 抽不出文本时，可选本地 OCR 出文本进生成 | 抽取失败/空 | OCR 文本片段 + 建议 | `experience/ocr_enabled`（默认关） | `pytesseract` + 系统 `tesseract` |
| **M-04** 语音→Palette | ⌘K 支持按住说话转文字进输入框（替代手打） | ⌘K 麦克风按钮 | 转录文本填回输入框 | `experience/voice_palette`（默认关） | `SpeechRecognition` + 系统 `pyaudio` |
| **M-05** 截图解释 | 当前编辑器/某控件截图附进工坊让 LLM 解释 | Dock/⌘K「截图解释」 | 截图进附件 + 只读解释预览 | `experience/screenshot_explain`（默认关） | Qt 截图（内置，无新依赖） |

**统一红线**：三切片都是「**默认关 + 可选依赖懒加载 + 原文不进 telemetry**」。前两个（M-03/M-05）原文走 §14.5.3「隐私附件原文」纪律；M-04 语音原文属未保存隐私输入，同款纪律。

**继承契约**：三切片都消费 M-01（v4.36）已建立的附件链路——`AttachmentRecord` + `AttachmentBar` + `ref_id` 间接取原文约定（见 `docs/e4-m01-attachments-context-design.md` §3.3）。本设计不改附件闭集快照；新增的多模态**原文**一律按 `ref_id` 回工坊取，**不进 Context、不进 telemetry**。

## 1. M-03 OCR 建议链（K-23）

### 1.1 背景与问题

`attachment_extractor._pdf_content`（`attachment_extractor.py:82`）在扫描件/图片 PDF 时返回 `error="PDF 未提取到文本（可能是扫描件或图片 PDF）"`；`_image_content`（`:55`）只产 base64 `image_url`，**无任何文本抽取**。这两类附件当前只能以视觉/空文本进 LLM messages，无法成为可检索、可喂纯文本 prompt 的素材。

**M-03 要解决**：当附件抽取**失败或为空**且属图片类（图片附件 / 扫描 PDF），可选本地 OCR 出文本，转为 M-01 已有的「文本类附件」参与后续生成。

### 1.2 设计决定

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 触发条件 | 抽取 `error` 非空 **或** 附件 kind=image **且** OCR 开关开 | 只在「无文本可取」时提示 OCR，不在已有文本时多余调用 |
| OCR 引擎 | `pytesseract`（Python 封装）+ 系统 `tesseract` 二进制；**懒加载 import** | 纯本地、零网络、零费用；与 `attachment_extractor` 现有 PyPDF2/python-docx 懒加载模式一致；`pytesseract` 是 OCR 事实标准且 pip 可装，系统 `tesseract` 多数 Linux 发行版一行安装 |
| 排除云端 OCR | 明确不做 | 云端 OCR 把附件原文送第三方，违反 §14.5.3「隐私附件原文不入遥测」精神（连本地都不落盘，更不外发）；费用与隐私双红线 |
| 默认开关 | `experience/ocr_enabled` 默认 **false** | OCR 是有副效应的感知能力（读盘、跑外部进程），属 §6.4「新能力新键默认关」；且系统 `tesseract` 非必装，关时零依赖负担 |
| 语言 | OCR `lang` 跟随 `index.language`（如 `tur`），缺省 `eng+chi_sim` | 与课程目标语言对齐；缺省包不保证存在，缺则降级（见 1.3） |

### 1.3 新纯模块 `src/backend/experience/ocr_skill.py`（无 Qt）

仿 `attachments.py` 四件套，纯函数 + 懒加载，永不抛：

```text
OCR_STATUS: Literal["ok","missing_dep","missing_binary","no_text","disabled"]

is_ocr_enabled(settings) -> bool                          # flag on（policy 委托，签名不变）
ocr_available() -> tuple[bool, str]                        # 懒探测 pytesseract + tesseract 二进制
run_ocr(path_or_bytes, *, lang: str) -> tuple[str, OCR_STATUS]
  # 成功→(text,"ok")；缺依赖→("","missing_dep")；缺二进制→("","missing_binary")；空文本→("","no_text")
  # never raises — 异常归一为状态串
build_ocr_suggestion(attachment_ref, status) -> dict | None  # 闭集建议，原文不进
```

**红线**：
- OCR 文本**不进 Context**（保持 M-01 闭集快照不变）；OCR 后转为「文本类 AttachmentRecord」进工坊侧，经 `ref_id` 间接取用，与 M-01 §3.3 同款；
- `build_ocr_suggestion` 的 scope 仅 `{ref_id, kind, status}`——**不放 OCR 文本、不放路径**；
- OCR 失败（缺依赖/缺二进制/空文本）→ 仅 statusBar + Dock 建议降级，**不阻塞**任何既有保存/生成（§14.5.2 失败安全）；
- 系统二进制路径/OCR 文本**永不进 telemetry**（§14.5.3）。

### 1.4 接入与入口

| 项 | 内容 |
|----|------|
| action_id | `textbook.ocr_suggest`（`needs_confirm=False`，`dangerous=False`，只读触发 OCR + 转附件） |
| 触发 | 工坊附件条：图片/扫描 PDF 附件上的「OCR」按钮；Dock/⌘K 建议（仅当开关开 + 有可 OCR 附件时） |
| 斜杠 | `/ocr`（slash-only，不加「OCR」自由文本关键词，避免误拦截） |
| 执行 | `experience_skills_mixin._experience_ocr`：`ocr_available` → 开关/缺依赖 statusBar；`run_ocr` → 文本写入新 `AttachmentRecord`（kind=text）经 `attachments_changed` 推 M-01 链路 → Dock 附件行刷新 |
| 设置 | `experience/ocr_enabled` 默认 false；设置「体验 OS」tab 复选框；round-trip + clone |

### 1.5 §14.5.3 redaction（M-03 行）

| 可记 | 不可记 |
|------|--------|
| `ref_id`、`kind`、`status`（ok/missing_dep/...）、OCR 触发计数 | OCR 抽出文本任何片段 |
| `action_id`、触发附件计数 | 系统二进制绝对路径、附件完整磁盘路径 |
| 是否成功（bool） | 被截图页/区域坐标（若未来扩页面级） |

### 1.6 实施记录（v4.40，2026-07-22）

已按本设计 §1 落地 M-03（**图片附件 + 扫描 PDF 触发**，v4.40 + v4.41）：

- 纯模块 `src/backend/experience/ocr_skill.py`（无 Qt，永不抛）：`is_ocr_enabled` / `ocr_available`（懒探 `pytesseract` + `shutil.which("tesseract")`）/ `run_ocr(path, *, lang)`（PIL+pytesseract 懒；课程 lang 优先、缺 lang 包降级 `eng`；`TesseractNotFoundError`->`missing_binary`；非图->`no_text`）/ `ocr_all_images`（筛 `image_url` record，线程安全，供 `AiRequestWorker` 跑）/ `build_ocr_suggestion`（闭集 scope）。
- `actions.textbook.ocr_suggest`（`needs_confirm=False`，非 dangerous，不入 `DANGEROUS_ACTION_IDS`）；`intent_router` `/ocr`（slash-only，不加自由文本关键词）；黄金 71->72。
- `settings.experience_ocr_enabled` 默认 false（五处 round-trip）+ `settings_dialog`「体验 OS」复选框。
- 工坊回流：`WorkshopWindow.add_attachment_record` / `attachment_records` + `DesignPanel.add_attachment_record` -- OCR 文本写成 temp `.txt` -> 文本类 `AttachmentRecord` -> `attachments_changed` -> M-01 链 + Dock 刷新（temp 文件随条 cleanup，无泄漏）。
- 派发 `experience_skills_mixin._experience_ocr`（镜像 K-24/M-05）：开关 -> 取工坊图片附件 -> `ocr_available` -> `AiRequestWorker` 跑 `ocr_all_images`（`kind=local` job）-> 文本 record 回流 -> timeline 仅 `action_id` + 闭集 scope `{count, status}`（**不记** OCR 文本/路径，§14.5.3）-> metrics。
- `tests/test_experience_ocr.py` +27（is_ocr_enabled 3 / ocr_available 3 / run_ocr 6 含 lang 降级 / ocr_all_images 2 / build_suggestion 2 / 契约 1 / 路由 4 / 派发 6）+ `test_experience_actions.open_only` 登记 + `test_experience_flags_round_trip_matrix` +subTest。

红线保持：只读不写课程树、无 Guard/sandbox/Undo、非 dangerous；默认关；OCR 文本/路径不进 Context/telemetry；永不抛；observer 经 `can_dispatch` 放行只读。基线 1763->**1790**，门禁 32/32，黄金 71->72。

**v4.41 触发补全**（2026-07-22）：
1. 扫描 PDF **触发** ✅ -- `_add_attachment_paths` 抽取失败（含「扫描」）+ 开关开 + `ocr_available` -> `QMessageBox.question` 加时提议 -> emit `ocr_requested(temp_path,name,unlink_after=True)`（不进条、不 unlink，temp 归 OCR；否/不可用维持 warn+skip）；`run_ocr` 加 PDF 分支（PyMuPDF `fitz` 懒渲染 200dpi -> PIL -> `_ocr_pil_image`，缺 fitz->`missing_dep`）。
2. 工坊内 per-chip OCR 按钮 ✅ -- `AttachmentBar` 图片 chip 加「OCR」按钮（仅 `_ocr_enabled` 时）+ `ocr_requested = Signal(str,str,bool)` + `set_ocr_enabled`；信号链 bar->design_panel->workshop_window->app（图片 chip `unlink_after=False`；扫描 PDF `unlink_after=True`）。
3. `_experience_ocr` 重构 ✅ -- `records=None`（/ocr-all + dedup）vs `records=[...]`（单 record）+ `unlink_after` 清理 orphan 扫描 PDF temp。

**v4.42 Dock 建议 + 维护硬化**（2026-07-23）：
4. Dock `local_suggestion` ✅ -- `local_suggestions(..., ocr_enabled=False)` kwarg；开关开 + `ctx.attachments` 含 `kind=="image"` -> P2 `textbook.ocr_suggest`（scope 闭集 `{count}`）；`ExperienceShell.set_ocr_enabled` hint + app `_sync_workshop_ocr_enabled` 推 + `clear_experience_session` 关课清位。**M-03 与设计 §1.4 完全对齐**（工坊按钮 + Dock/⌘K 建议 + 扫描 PDF 加时提议 + 图片 chip 全交付）。
5. 维护：删 `ocr_all_images` v4.40 兼容包装（无 src 调用方）+ 其测试；清陈旧 BASELINE 文案。

M-03 现已无延迟项。

## 2. M-04 语音→Palette

### 2.1 背景与问题

⌘K 命令面板（`widgets/command_palette.py`）当前仅接受键盘自由文本。长指令/外语朗读输入对手打不友好。M-04 给 ⌘K 加一个**按住说话→转录→填回输入框**的输入通道，**仅替代手打**，不改任何派发语义。

### 2.2 设计决定

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 引擎 | `SpeechRecognition`（Python 封装）+ 系统 `pyaudio`（麦克风采集）；**懒加载 import** | 纯本地转录（默认用 Sphinx 离线引擎）；不强制云端（云端选项可后续加但默认关，避免隐私/费用） |
| 默认开关 | `experience/voice_palette` 默认 **false** | 麦克风是隐私侧效应（§14.5.3「未保存隐私输入」），属 §6.4 默认关；且 `pyaudio` 系统依赖非必装 |
| 触发 | ⌘K 输入框旁的麦克风按钮（开关关时隐藏） | 不抢键盘焦点；转录完成文本填回输入框，用户照常 Enter 派发（仍走 `route_intent`/`match_commands`，M-09 仍按 dispatch 计） |
| 转录原文 | **不进 telemetry** | 语音原文是未保存隐私输入，同 §14.5.3 纪律；只记「语音输入 N 次 + 是否成功」 |
| 失败 | 缺依赖/无麦克风/超时 → statusBar + 输入框不变 | §14.5.2 失败安全；不阻塞派发 |

### 2.3 新纯模块 `src/backend/experience/voice_skill.py`（无 Qt）

```text
VOICE_STATUS: Literal["ok","missing_dep","no_mic","timeout","disabled","too_long"]

is_voice_palette_enabled(settings) -> bool
voice_available() -> tuple[bool, str]                       # 懒探测 SpeechRecognition + pyaudio
transcribe_once(*, lang: str, timeout: float) -> tuple[str, VOICE_STATUS]
  # 成功→(text,"ok")；缺依赖→("","missing_dep")；无麦克风→("","no_mic")；超时→("","timeout")
  # never raises
build_voice_metrics(ok: bool) -> dict                       # 闭集 metrics：count + status，无原文
```

### 2.4 接入与入口

| 项 | 内容 |
|----|------|
| action_id | **不新增写树 action**；这是输入通道，非课程写能力。`app.voice_input` 仅作 ⌘K 内建入口（registry 不必登记为 AI 写 action） |
| 触发 | `command_palette` 麦克风按钮（开关关时按钮隐藏） |
| 执行 | `palette_controller` 加 `transcribe_to_palette(win)`：`voice_available` → 开关/缺依赖 statusBar；`transcribe_once` → `command_palette.set_input_text(text)`（用户再 Enter；不自动 dispatch，对齐 C-06「LLM 候选不自动 Enter」精神） |
| 设置 | `experience/voice_palette` 默认 false；设置「体验 OS」tab 复选框 |

### 2.5 §14.5.3 redaction（M-04 行）

| 可记 | 不可记 |
|------|--------|
| 语音输入触发计数、`status`、是否成功（bool） | 转录文本任何片段（用户未保存的语音原文） |
| `action_id`、所用引擎名 | 音频波形/base64、麦克风设备名 |

### 2.6 实施记录（v4.44，2026-07-23）

已按本设计 §2 落地 M-04：

- 纯模块 `src/backend/experience/voice_skill.py`（无 Qt，永不抛）：`is_voice_palette_enabled` / `voice_available`（懒探 `speech_recognition` + `pyaudio`）/ `transcribe_once`（默认 `recognize_sphinx` 离线；可注入 recognizer/source 供测）/ `build_voice_metrics` 闭集 `{status,ok,engine}` / `status_message`。
- 设置 `experience/voice_palette` 默认 false（`settings.py` 五处 + `settings_dialog`「体验 OS」复选框）。
- `CommandPalette`：输入行旁麦克风 `QToolButton`（默认隐藏）+ `set_voice_enabled` / `set_voice_busy` / `set_input_text`（**不** emit `command_triggered`）+ `voice_requested`。
- `palette_controller.transcribe_to_palette`：开关关 / offscreen / 缺依赖 → statusBar 非模态；JobTray `voice-palette` kind=local + worker 跑 `transcribe_once` → 成功则 `set_input_text`；timeline 仅闭集 scope（**无原文**）。
- `open_command_palette`：读 settings 推 mic 可见性 + 接线 `voice_requested`；parent 仅在 host 为 QWidget 时传入。
- `tests/test_experience_voice.py` +21；门禁 32/32；黄金集不变（无新斜杠）。

红线保持：输入通道非写树、无 Guard/sandbox/Undo、非 dangerous；默认关；可选依赖懒加载；**不自动 dispatch**；§14.5.3 转录原文不进 telemetry；offscreen 不触麦。

## 3. M-05 试做截图解释

### 3.1 背景与问题

作者编辑课程时偶有「想让 AI 看我现在屏幕上的状态来解释/建议」的诉求（如某题卡布局怪、某树状态异常）。当前只能口头描述。M-05 提供一条**截图当前主窗/某控件 → 进工坊附件 → 让 LLM 解释**的只读链路。

### 3.2 设计决定

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 截图方式 | Qt 内置 `QWidget.grab()` / `QScreen.grabWindow()` 截主窗或全屏；**零新依赖** | 不引入 Pillow/screenshot 库；Qt 截图已是内存 QPixmap，转 PNG base64 即可作 `image_url` 附件，复用 M-01 链路 |
| 默认开关 | `experience/screenshot_explain` 默认 **false** | 截图含编辑器当前内容（可能含未保存隐私），属 §6.4 默认关；且喂 LLM 视觉有费用（§14 成本红线） |
| 截图范围 | 仅主窗可见区（不截全屏其他应用） | 隐私最小化；截全屏会带入无关桌面内容 |
| 原文纪律 | 截图进 LLM messages 是既有行为（M-01 image_url）；**不落盘、不进 telemetry**；解释结果只读预览，不写课程树 | 与 M-01 同款；Timeline 只记 `action_id` + 短 summary |
| 失败 | 截图失败/无 LLM 配置 → statusBar | §14.5.2 失败安全 |

### 3.3 新纯模块 `src/backend/experience/screenshot_skill.py`（无 Qt）

```text
SCREENSHOT_STATUS: Literal["ok","disabled","no_window","no_config","failed"]

is_screenshot_explain_enabled(settings) -> bool
capture_widget_to_png_bytes(widget) -> tuple[bytes, SCREENSHOT_STATUS]
  # QWidget.grab() → QImage → PNG bytes；widget None → ("","no_window")
build_screenshot_attachment(png_bytes, *, name="screenshot") -> AttachmentRecord
  # 转 base64 image_url AttachmentRecord，进 M-01 工坊链路
```

> 注：`capture_widget_to_png_bytes` 需 Qt（QWidget.grab），故该 helper **非纯无 Qt**——这与 §7.4「禁止 Qt 进 backend/experience 纯逻辑包」冲突。**解决**：截图 helper 放 `application/screenshot_controller.py`（应用层，可依赖 Qt），`screenshot_skill.py` 只放**纯**的 `is_*_enabled` / `build_screenshot_attachment`（PNG bytes → record，无 Qt）与闭集 metrics。截图动作本身在 controller。

### 3.4 接入与入口

| 项 | 内容 |
|----|------|
| action_id | `app.screenshot_explain`（`needs_confirm=False`，`dangerous=False`，只读：截图+解释+预览） |
| 触发 | Dock「截图解释」按钮（开关关时隐藏）/ ⌘K `/screenshot-explain` |
| 执行 | `application/screenshot_controller.explain_current(self)`：开关/无窗 statusBar → `capture_widget_to_png_bytes(self)` → `build_screenshot_attachment` 进工坊附件 → `AiRequestWorker(request_chat)` 解释 → 只读预览对话框（仿 K-24 `_show_git_skill_result`，headless offscreen 走 statusBar）；Timeline 不记截图/回复原文 |
| 设置 | `experience/screenshot_explain` 默认 false；设置「体验 OS」tab 复选框 |

### 3.5 §14.5.3 redaction（M-05 行）

| 可记 | 不可记 |
|------|--------|
| 截图触发计数、`status`、是否成功（bool） | 截图 PNG/base64 任何片段 |
| `action_id`、解释回复**短摘要**（≤80 字，调用方截断） | 解释回复全文、截图区域坐标含其他窗口内容 |

### 3.6 实施记录（v4.38，2026-07-22）

已按本设计 §3 落地 M-05：

- 纯模块 `src/backend/experience/screenshot_skill.py`（无 Qt）：`is_screenshot_explain_enabled` / `png_bytes_to_data_url` / `build_screenshot_messages`（OpenAI 兼容 text+image_url，空 PNG 降级 text-only）/ `run_screenshot_skill`（懒 import `request_chat`/`_content_text`，temperature=0.4）/ `truncate_reply`（≤80，供 redaction）。永不抛。
- 应用层控制器 `src/application/screenshot_controller.py`（可 Qt，守 §7.4）：`capture_widget_to_png_bytes`（`QWidget.grab()` → `QImage` → PNG bytes，None→`no_window`，异常归一 `failed`）+ `explain_current(win)`（镜像 K-24 `_experience_git_skill`：未开启/无配置/无窗/offscreen→statusBar 非模态 → job → `_make_ai_worker` → `_on_ok`/`_on_err` → 复用 `_show_git_skill_result` 只读预览）。
- `actions.app.screenshot_explain`（`needs_confirm=False`，非 dangerous，不入 `DANGEROUS_ACTION_IDS`）；`intent_router` `/screenshot-explain` + 关键词；黄金 67→68。
- 设置 `experience/screenshot_explain` 默认 false（`settings.py` 五处：字段/load/构造/save/clone + `settings_dialog.py` 「体验 OS」tab 复选框三处）。
- 派发分支 `experience_skills_mixin._on_experience_suggestion` → `explain_current(self)`。
- `tests/test_experience_screenshot.py` +25（message builder 4 / run skill 3 / redaction 3 / enabled 4 / 契约 1 / 路由 3 / 截图 2 / 控制器派发 5：未开启/offscreen/无配置/全路径预览/AI 错误非模态）。

红线保持：只读不写树、无 Guard/sandbox/Undo、非 dangerous；默认关；§14.5.3 redaction（Timeline 只记 action_id + 固定短标签，不记截图/回复原文，测试断言 `_record_experience_event` scope={} 且 reply/base64 不进 args）；offscreen 守卫复用 K-24 `app.platformName() == "offscreen"`；永不抛。基线 1695→**1720**（+25），全量 338s 绿（skipped=3），门禁 32/32。**M-03 ✅ v4.40–v4.42 · M-04 ✅ v4.44**（见 §1.6 / §2.6）。

## 4. 与既有契约的一致性检查

### 4.1 设置键（三切片统一）

| 键 | 含义 | 默认 |
|----|------|------|
| `experience/ocr_enabled` | 图片/扫描 PDF 本地 OCR 建议链 | **false** |
| `experience/voice_palette` | ⌘K 语音输入通道 | **false** |
| `experience/screenshot_explain` | 截图→LLM 只读解释 | **false** |

三键均独立 bool，不并入 `experience/mode`（对齐 §5.2「未来模式必新键或扩枚举」与 v4.2「Soft 独立 bool」先例）。observer 模式下：M-03/M-05 经 `can_dispatch` 拦（observer 零 AI 写/LLM，对齐 §8.15）；M-04 是输入通道非 AI 写，observer 下可保留（同「Observer 不得半关」针对 AI 侧效应，非输入可见性）。

### 4.2 policy.py

**不加字段**：三切片默认关，触发前各 controller 读 `is_*_enabled`（委托 `resolve_policy` 语义可在实施时加 `allow_ocr`/`allow_voice`/`allow_screenshot` 派生字段，但本设计不强制——`can_dispatch` 现有 `needs_confirm` + observer 规则已覆盖只读路径）。**M-03 转附件后进生成**属既有 AI 写路径，仍走既有 `can_dispatch`。

### 4.3 依赖与懒加载

| 切片 | 可选依赖 | 懒加载 | 缺依赖降级 |
|------|----------|--------|------------|
| M-03 | `pytesseract` + 系统 `tesseract` | `import` 在 `run_ocr` 内 | `missing_dep`/`missing_binary` statusBar |
| M-04 | `SpeechRecognition` + 系统 `pyaudio` | `import` 在 `transcribe_once` 内 | `missing_dep` statusBar |
| M-05 | 无（Qt 内置） | — | `no_window` statusBar |

`tool/gui` 依赖清单（`requirements*.txt`）**不**把这些列为强制依赖；README 加「可选：OCR/语音需 X」说明。懒加载保证主路径在缺依赖时仍导入与运行（对齐 `attachment_extractor` 现状）。

### 4.4 测试规划（实施时执行）

| 切片 | 纯函数测（无 Qt/无依赖） | 接入测 |
|------|--------------------------|--------|
| M-03 | `is_ocr_enabled`/`ocr_available` mock/`run_ocr` 状态归一/闭集建议无原文/redaction 锁定 | ~8 |
| M-04 | `is_voice_palette_enabled`/`voice_available` mock/`transcribe_once` 状态/闭集 metrics 无原文 | ~6 |
| M-05 | `is_screenshot_explain_enabled`/`build_screenshot_attachment` 闭集/redaction | ~5（controller 截图用 Qt 测） |

预估合计 **+19 测**，门禁 32 不变（三切片无危险面，不开新 G）。黄金集 +2（`/ocr` `/screenshot-explain`；M-04 不加斜杠，按钮入口）。

### 4.5 实施步骤预览（本文档不执行）

各切片独立可发，互不依赖。最小步骤（以 M-03 为例，M-04/M-05 同形）：

1. 新建 `src/backend/experience/ocr_skill.py`（§1.3 四件套）；
2. `actions.py` 注册 `textbook.ocr_suggest`（`needs_confirm=False`）；`intent_router` `/ocr`；
3. `settings.py` 加 `experience/ocr_enabled` 默认 false + 设置 UI 复选框；
4. `experience_skills_mixin._experience_ocr`：开关/`ocr_available` → `run_ocr` → 转 AttachmentRecord 经 `attachments_changed`；
5. 工坊附件条「OCR」按钮（开关关时隐藏）；
6. 测试（§4.4）+ BASELINE + experienceai.md §2/§8/§11/§16.3/§17（实施时升次版本）。

## 5. 风险与开放项

| 风险 | 缓解 |
|------|------|
| OCR/语音系统依赖在不同发行版可用性不一 | 懒加载 + `*_available` 探测 + 缺依赖降级 statusBar，绝不崩 |
| 截图含未保存隐私内容外发 LLM | 默认关 + 仅截主窗可见区 + 不落盘/不进 telemetry + §14.5.3 redaction 锁定 |
| 语音转录误识别导致错误派发 | 转录填回输入框**不自动 dispatch**，用户照常审阅 Enter（对齐 C-06 不自动 Enter 精神） |
| OCR 文本被误当课程真源 | OCR 只产「文本类附件」，进 M-01 闭集快照，不直接写课程 JSON；进树仍经 Diff 确认 |
| 三切片各自默认关导致「装了但没人用」 | 设置 UI 文案标明用途 + Dock 在开关开且有可触发附件时才出建议（不噪音） |

**开放项**（实施时定案，本文档留决）：

1. M-03 OCR `lang` 包可用性——按 `index.language` 选 `tesseract` lang 包，缺则降级 `eng`；是否提示用户安装 lang 包留实施时；
2. M-04 是否支持云端转录（Whisper API 等）——默认关，本设计只定本地；云端另切片；
3. M-05 截图是否支持「框选区域」——本设计只截主窗可见区，框选留远期；
4. 三切片是否合并一个「多模态总开关」——**不合并**，各自独立 bool（对齐「新能力新键默认关」+ 避免一开全开）。

**下一步**：本文档为 E4 M-03/M-04/M-05 的统一设计契约，待排期后按 §4.5 各自切片实施。实施任一切片须升 `experienceai.md` 次版本并补 §17 变更记录。