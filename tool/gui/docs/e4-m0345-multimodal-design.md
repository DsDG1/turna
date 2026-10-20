# E4 多模态后续切片 —— 设计文档（M-03 / M-04 / M-05）

| 字段 | 值 |
|------|-----|
| **文档编号** | `VAR-GUI-EXP-M0345-DESIGN` |
| **版本** | v1.0（设计文档，未实施） |
| **日期** | 2026-07-22 |
| **上游规范** | `tool/gui/docs/experienceai.md` v4.37（§2.4 E4、§10.5、§16.3、§14.5.3） |
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

**红线**：OCR 文本**不进 Context**（保持 M-01 闭集快照不变），OCR 后转为「文本类 AttachmentRecord」进工坊侧、经 `ref_id` 间接取用（与 M-01 §3.3 同款）；`build_ocr_suggestion` 的 scope 仅 `{ref_id, kind, status}`——**不放 OCR 文本、不放路径**；OCR 失败（缺依赖/缺二进制/空文本）→ 仅 statusBar + Dock 建议降级，**不阻塞**任何既有保存/生成（§14.5.2 失败安全）；系统二进制路径/OCR 文本**永不进 telemetry**（§14.5.3）。

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
