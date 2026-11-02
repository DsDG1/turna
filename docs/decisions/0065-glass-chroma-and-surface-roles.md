# ADR 0065 — 玻璃降彩度，并分开玻璃对象与扁平纸面

> 状态：已接受 ｜日期：2026-11-02
>
> 前置：ADR 0062（彩色玻璃材质）、ADR 0063（设置域深层页的弱化玻璃档）
>
> 真源：`lib/core/theme.dart`（`glassChroma` / `glassShadowCooling` / `flatPaperDecoration`）

## 背景

ADR 0062 的淡彩浓度（accent 约 7–19%）和同色相描边（约 20–40%）把品牌色的饱和度原样罩进卡面。暖色和描边读起来偏艳。浓度不能再降：ADR 0063 已经记过，中性灰降到约 5–9% 时，白底上的卡会失去边界。

同一时期，课程树用无投影的 `l1Quiet` 渐变假装扁平，首页芯片、AI 浮层和弹层把一代白高光边压在平涂上，复习进度 / 错题 / 洞察则一屏叠多张 `l1Subtle` 玻璃卡。玻璃和扁平叠在同一层，没有角色。

## 决策

### 1. 降彩度，不降浓度

`glassChroma = 0.72`。`_glassMix` 与 `glassStroke` 在罩染前把 accent 的 HSL 饱和度乘上这个系数。`glassSpec` 的浓度、高光、投影强度不动。`cardBackground` 与胶囊导航的淡彩走同一条混色。

同色相投影向 `brandNavy` 靠拢的比例从 0.28 收到 `glassShadowCooling = 0.40`，影子跟卡面一起变灰。

按钮、实色徽章、选中描边、错误色文字不经这层。它们是信号，不是玻璃底。

### 2. 一页三种表面

| 角色 | 材质 | 落点 |
|---|---|---|
| 玻璃对象 | `glassDecoration` | 练习工具卡、复习主卡、语法卡、完成统计、设置落地页、个人页统计卡 |
| 扁平纸面 | `flatPaperDecoration`（实色 + 1px 中性描边） | 课程树旅程、复习进度 / 错题 / 洞察的成组卡片、弹层纸面 |
| 扁平控件 | 低 alpha 平涂或实色，中性或语义描边 | 芯片、选项、图标井、设置行 |
| 磨砂浮层 | `BackdropFilter` + `glassBorder` | 只留底部胶囊和 SnackBar |

`l1Quiet` 继续只服务设置深层页。课程树和统计列表不再借用它。

下一课行是纸面上的焦点：`cardBg` + `brandTeal` 描边，没有渐变。

## 范围外

- 不改品牌 hex，不改字号、间距、圆角。
- 不改设置落地 `l1Subtle`、设置深层 `l1Quiet`、词典列表行、练习选项、对话气泡、记忆卡壳。
- `tool/gui` 不参与。

## 影响面

- `lib/core/theme.dart`：彩度系数、投影冷却、`flatPaperDecoration`。
- 课程树三件（章节头、单元头、课行壳）与复习域四个成组页改为纸面。
- 首页状态芯片、AI 浮层卡片、提示词预览、练习信息弹窗、课程底部弹层去掉 `glassBorder`。
- `CountBadge` 去掉按 accent 着色的投影。
- `test/views/widgets/glass_tokens_test.dart` 增加彩度契约。
