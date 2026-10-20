# ADR 0032 — 关于页面更新 tool/gui 课程编辑器内容

> 状态：**已定稿**（用户已确认：A+B 范围 / 仓库根 README 锚点 / 不动 `CLAUDE.md`（已删））
>
> 触发请求：在关于页面（`lib/views/settings/about_turna_page.dart`）更新 `tool/gui` 课程编辑器相关内容。

## 决策

**方案 A：最小改动（推荐起点）** — 只刷新「致谢」section 的措辞，让 `aboutCreditsFork` 显式提到 `tool/gui` 及其在仓库中的位置。零风险，零新 UI。成本：1 行字符串，3 分钟。缺点：教师/创作者找不到入口。

**方案 B：在「链接」section 追加一项（B 优于 A）** — 在 `_AboutTab` 的「链接」卡片底部追加一个新 `_LinkTile`：

| 图标 | 标题 | 副标题 | 动作 |
|---|---|---|---|
| `Icons.desktop_mac_rounded` | 课程编辑器（桌面端） | `tool/gui/` · 面向创作者 | 跳到 GitHub 上 `tool/gui/README.md` |

外加在「致谢」section 替换原文为方案 A 的措辞。成本：约 40 行 Dart + 3–4 个新 `AppStrings` 键。优点：用户能从 App 直接跳到 GUI 工具入口；为后续方案 C 留位置。

**方案 C：新增「工具」section（最完整）** — 在「链接」section 后插入全新 `_AboutCard`：标题 `AppStrings.aboutToolGuiTitle`（课程编辑器）；2–3 句简介（PySide6、本地、面向教师）；3 个 highlights（可视化课程树、AI 课程工坊、JSON-first 校验）；CTA 跳到 `tool/gui/README.md`。外加 A + B。成本：约 80 行 Dart + 6–8 个新 `AppStrings` 键。风险：与「亮点」section 重复感——亮点走用户体验卖点，工具 section 走创作者入口，定位要分清。

**已锁定的路径：A + B。**

- A：把 `aboutCreditsFork` 从笼统的「课程创作工具」改成显式提到 `tool/gui/`
- B：在「链接」section 追加桌面端入口 `_LinkTile`，onTap 跳到 `https://github.com/rshrc/Varnamala#课程编辑器-toolgui`

关键文件 / 改动清单：

| 文件 | 改动 |
|---|---|
| `README.md` | "## 框架能力" section 内追加 `### 课程编辑器 (tool/gui)` 小节（含 2–3 句简介 + 启动命令），作为锚点目标 |
| `lib/l10n/app_strings.dart` | 改写 `aboutCreditsFork`；新增 `aboutToolGuiLinkTitle` / `aboutToolGuiLinkSubtitle` |
| `lib/views/settings/about_turna_page.dart` | `_AboutTab` 的"链接"卡片内追加一个 `_LinkTile`（图标 `Icons.desktop_mac_rounded`），onTap 跳到 README 锚点；"致谢"section 引用改写后的字符串 |

最终文案：

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

````markdown
<!-- README.md - "## 框架能力" 内追加 -->
### 课程编辑器 (tool/gui)

`tool/gui/` 是一个面向课程创作者的 PySide6 桌面编辑器，提供可视化课程树、课时蓝图、AI 课程工坊与 JSON-first 校验。需要 Python 3.11+。

```bash
python -m tool.gui.src.main
```

详见 [`tool/gui/README.md`](../../tool/gui/README.md) 与 [`docs/project-guide.md`](../project-guide.md) §11。
````

## 理由

`tool/gui/` 是 Turna 课程图形编辑器（PySide6 桌面应用，Python 3.11+），`course_cli` 的 GUI 前端，面向课程创作者/教师。现状：关于页 6 个 section 里没有任何地方告诉创作者「仓库里附带了 GUI 编辑器」；`aboutCreditsFork` 只笼统提到「课程创作工具」，未指明 `tool/gui`；链接 section 无 GUI 入口。

选 A + B 而非方案 C 的理由：

- 现状几乎为零，A+B 信息量已足够讲清「`tool/gui/` 是配套编辑器」
- 不破坏现有视觉节奏（3 卡片 + 链接列表 + 致谢卡片 = 6 section）
- GUI 工具是仓库内面向开发者的桌面工具，**不进 app 本体**，与历史决策不冲突

## 影响与边界

- 不新增 section；README 需在「## 框架能力」内追加 `### 课程编辑器 (tool/gui)` 小节作为锚点目标。
- 验收：`flutter analyze` 无新增告警；Android emulator 上设置 → 关于 → 链接 能看到新条目且点击可跳到 README 锚点；深色模式下新 tile 颜色与现有 `_LinkTile` 一致；锚点跳转后浏览器自动滚动到该小节。
