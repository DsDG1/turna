# 0032 — 关于页面更新 tool/gui 课程编辑器内容

> 状态：**已定稿**（用户已确认：A+B 范围 / 仓库根 README 锚点 / 不动 CLAUDE.md）
> 触发请求：在关于页面（`lib/views/settings/about_turna_page.dart`）更新 `tool/gui` 课程编辑器相关内容。

## 1. 背景

- **目标文件**：`lib/views/settings/about_turna_page.dart`（"关于"Tab）+ `lib/l10n/app_strings.dart`（文案键）
- **目标工具**：`tool/gui/` —— Turna 课程图形编辑器（PySide6 桌面应用，Python 3.11+），是 `course_cli` 的 GUI 前端，面向课程创作者 / 教师。
- **现状**：
  - "关于" Tab 共有 6 个 section：什么是 Turna / 亮点 / 隐私 / 版本 / 链接 / 致谢
  - `app_strings.dart:296` 的 `aboutCreditsFork` 只笼统提到"课程创作工具"，没有指明 `tool/gui`
  - 链接 section 没有指向 GUI 工具的入口
  - 没有任何地方告诉教师/创作者"如果你想自己编课，仓库里附带了 GUI 编辑器"
- **冲突点**：CLAUDE.md 第 108 行写着"~~External GUI editor~~ — Removed (JSON-first approach)"，但 `tool/gui/` 实际存在且活跃维护。**需要在 UI 文案上明确：GUI 工具是面向创作者的桌面端编辑器，不进应用本体**，与历史决策并不冲突，但要在计划里点出这点。

## 2. 候选方案

### 方案 A：最小改动（推荐起点）
只刷新"致谢"section 的措辞，让 `aboutCreditsFork` 显式提到 `tool/gui` 和它在仓库中的位置。零风险，零新 UI。

```dart
// app_strings.dart
static String get aboutCreditsFork =>
    '本构建是一个本地优先的分叉版本，增加了无障碍设置，并在 tool/gui/ 中提供了配套的桌面端课程编辑器。';
```

**成本**：1 行字符串，3 分钟。
**缺点**：教师/创作者找不到入口。

### 方案 B：在"链接"section 追加一项（B 优于 A）
在 `_AboutTab` 的"链接"卡片底部追加一个新 `_LinkTile`：

| 图标 | 标题 | 副标题 | 动作 |
|---|---|---|---|
| `Icons.desktop_mac_rounded` | 课程编辑器（桌面端） | `tool/gui/` · 面向创作者 | 跳到 GitHub 上 `tool/gui/README.md` |

外加在"致谢"section 替换原文为方案 A 的措辞。
**成本**：约 40 行 Dart + 3–4 个新 `AppStrings` 键。
**优点**：用户能从 App 直接跳到 GUI 工具的入口；为后续方案 C 留位置。

### 方案 C：新增"工具"section（最完整）
在"链接"section 后插入一个全新的 `_AboutCard`，专门介绍 `tool/gui`：

- 标题：AppStrings.aboutToolGuiTitle（"课程编辑器"）
- 简介：2–3 句话说明用途（PySide6、本地、面向教师）
- 3 个 highlights：可视化课程树、AI 课程工坊、JSON-first 校验
- 一个 CTA 按钮：跳到 `tool/gui/README.md`

外加 A + B 的改动。

**成本**：约 80 行 Dart + 6–8 个新 `AppStrings` 键。
**风险**：第三个 section 之前已经有"亮点"section，重复感需要克制——亮点走"用户体验卖点"，工具 section 走"创作者入口"，定位要分清。

## 3. 已锁定的路径

**A + B**：
- A：把 `aboutCreditsFork` 从笼统的"课程创作工具"改成显式提到 `tool/gui/`
- B：在"链接"section 追加一个桌面端入口 `_LinkTile`，onTap 跳到 `https://github.com/rshrc/Varnamala#课程编辑器-toolgui`

理由：
- 现状几乎为零，A+B 的信息量已经足够把"`tool/gui/` 是配套编辑器"这件事讲清楚
- 不破坏现有视觉节奏（3 卡片 + 链接列表 + 致谢卡片 = 6 section）
- 与 CLAUDE.md 第 108 行的"External GUI editor removed"立场一致：**GUI 工具是仓库内面向开发者的桌面工具，不进 app 本体**

CLAUDE.md 不动。README.md 需在 "## 框架能力" 内追加一个 `### 课程编辑器 (tool/gui)` 小节作为锚点目标。

## 4. 关键文件 / 改动清单

| 文件 | 改动 |
|---|---|
| `README.md` | "## 框架能力" section 内，于 line 142 现有 bullet 之后追加 `### 课程编辑器 (tool/gui)` 小节（含 2–3 句简介 + 启动命令），作为锚点目标 |
| `lib/l10n/app_strings.dart` | 改写 `aboutCreditsFork`；新增 `aboutToolGuiLinkTitle` / `aboutToolGuiLinkSubtitle` |
| `lib/views/settings/about_turna_page.dart` | `_AboutTab` 的"链接"卡片内追加一个 `_LinkTile`（图标 `Icons.desktop_mac_rounded`），onTap 跳到 README 锚点；"致谢"section 引用改写后的字符串 |

## 5. 最终文案（草稿）

```dart
// app_strings.dart
static String get aboutCreditsFork =>
    '本构建是一个本地优先的分叉版本，增加了无障碍设置，并在 tool/gui/ 中提供了面向创作者的桌面端课程编辑器。';

static String get aboutToolGuiLinkTitle => '课程编辑器（桌面端）';
static String get aboutToolGuiLinkSubtitle => 'tool/gui/ · 面向创作者';
```

```dart
// about_turna_page.dart - 链接 section 新增条目
_LinkTile(
  icon: Icons.desktop_mac_rounded,
  title: AppStrings.aboutToolGuiLinkTitle,
  subtitle: AppStrings.aboutToolGuiLinkSubtitle,
  onTap: () => onLaunchUrl(
    'https://github.com/rshrc/Varnamala#课程编辑器-toolgui',
  ),
),
```

```markdown
<!-- README.md - "## 框架能力" 内,line 142 之后追加 -->
### 课程编辑器 (tool/gui)

`tool/gui/` 是一个面向课程创作者的 PySide6 桌面编辑器，提供可视化课程树、课时蓝图、AI 课程工坊与 JSON-first 校验。需要 Python 3.11+。

```bash
python -m tool.gui.src.main
```

详见 [`tool/gui/README.md`](./tool/gui/README.md) 与 [`docs/project-guide.md`](./docs/project-guide.md) §11。
```

## 6. 验收

- `flutter analyze` 无新增告警
- 在 Android emulator 打开 设置 → 关于 → 链接，能看到新条目，点击可跳到 `https://github.com/rshrc/Varnamala#课程编辑器-toolgui`
- 深色模式下新图标 tile 颜色与现有 `_LinkTile` 一致
- README 锚点跳转后，浏览器自动滚动到 `### 课程编辑器 (tool/gui)` 小节
