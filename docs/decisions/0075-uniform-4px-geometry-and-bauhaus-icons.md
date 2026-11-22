# ADR 0075 — 全 App 统一 4px 几何与包豪斯 SVG 图标体系

> 状态：已接受 ｜日期：2026-11-22
>
> 前置：[ADR 0033](./0033-turna-wetland-crane-palette.md)（湿地鹤色板）、[ADR 0062](./0062-colored-glass-material.md)（彩色玻璃材质）、[ADR 0063](./0063-settings-glass-quiet-tier.md)（设置弱化档）、[ADR 0065](./0065-glass-chroma-and-surface-roles.md)（表面角色分离）、[ADR 0068](./0068-ambient-light-and-frosted-glass.md)（L0 环境天光与毛玻璃档）
>
> 真源：`lib/core/theme.dart`（`TurnaTheme.radius` / `borderRadius` / `sheetTopBorderRadius`）、`lib/core/turna_icon_id.dart`、`lib/views/widgets/turna_icon.dart`、`lib/views/widgets/turna_controls.dart`、`assets/icons/`
>
> 关联：**部分取代** ADR 0062 / 0065 中关于控件、选项与弹层使用多档大圆角及胶囊的口径；ADR 0063 的「安静档」仅约束材质强度，不再附带设置域独立形状主题。

## 背景

全 App「湿地雾光」翻新进入中段后，出现两处系统性的视觉割裂：

1. **形状语言打架**：卡片已收口为 4px 近直角（`TurnaTheme.cardRadius`），但按钮仍是胶囊（`StadiumBorder` / `radiusRound = 100`），输入框与对话框用 12 / 16px，底部弹层与 SnackBar 用 24px，题型选项用 14px，设置域又另包了一套 `BorderRadius.zero` 的 `SettingsSquareControlTheme`。同一屏内同时出现直角、4px、12px、14px、24px 和胶囊，破坏了包豪斯几何秩序。
2. **图标语言打架**：全 `lib/` 散落数百处 Material `Icons.*`（绝大多数为 `*_rounded` 胖圆头风格），与近直角矩形和细磨玻璃的清晰轮廓相冲突；同时 `IconData` 反向侵入了 `lib/domain/cosmetics/` 与 `lib/application/settings/settings_destination.dart`。

## 决策

### 1. 形状：全 App 统一 4px

除真正的圆形元素外，全 App 仅保留一个圆角半径 `TurnaTheme.radius = 4.0`（保留 `cardRadius` / `cardBorderRadius` 兼容别名）：

| 元素 | 圆角规则 |
|---|---|
| 卡片、纸面、静态玻璃与 `l2Frost` | `4px` |
| 主 / 次 / 文字 / 描边 / 图标 / 危险按钮与分段控件 | `4px`（取消 `StadiumBorder` 与胶囊按钮） |
| 输入框、搜索框、下拉选择、选项条、词块、答案槽、提示与筛选标签 | `4px` |
| 对话框、SnackBar、浮层提示条、底部磨砂导航条及受光选中短条 | `4px` |
| 底部弹层（`TurnaSheet`） | 顶边两角 `4px`，底边贴屏 `0px` |
| 开关与滑块（`TurnaSwitch` / `TurnaSlider`） | 全局统一 `4px` 几何轨道与矩形滑块，撤除 `SettingsSquareControlTheme` 局部覆写 |
| 进度条、热图格、细分隔条 | `0px` 或 `4px`，不使用 2 / 3 / 6 等散值 |
| **真圆形例外** | 头像、播放 / 录音主控、完成标记、计数圆点与几何图形中的圆 / 半圆使用 `BoxShape.circle` 或 `CircleBorder`，不用大圆角矩形模拟 |

`radiusSmall` / `radiusMedium` / `radiusOption` / `radiusLarge` / `radiusXLarge` / `radiusRound` 随迁移清零后移除。

### 2. 图标：包豪斯几何 SVG 图标族（方式 A）

- **资产落点**：`assets/icons/*.svg`（在 `pubspec.yaml` 登记），按 `flutter_svg` 硬性兼容红线（无 `<style>` / `<filter>` / `<text>` / 嵌图）由静态校验脚本把关。
- **视觉规格**：`24×24` 网格、2px 安全边距、统一 `1.8px` 等宽描边、平头端点（`stroke-linecap="butt"`）与尖角/微倒角（`stroke-linejoin="miter"`），由圆、半圆、直线、直角折线与矩形块构成。常规功能图标单色跟随 `IconTheme`；导航、成就、完成等少量核心位允许双色几何（高对比自动退回单色）。
- **语义收敛**：将既有两百余个重复与零散 Material 图标名收敛为统一的语义枚举 `TurnaIconId`（位于纯 Dart 文件 `lib/core/turna_icon_id.dart`，零 Flutter 依赖），由 `TurnaIcon`（`lib/views/widgets/turna_icon.dart`）渲染。
- **分层清理**：`SettingsDestination.icon`、`CosmeticItem.icon`、`AvatarRing` 等改持 `TurnaIconId`，剥离 `domain/` 与 `application/` 对 `package:flutter/material.dart` `IconData` 的依赖。

### 3. 强制门禁

在 `test/architecture/code_conventions_guard_test.dart` 建立双向棘轮：
- 禁止 `lib/views/` 新增裸 `BorderRadius.circular(<数字>)`、`Radius.circular(<数字>)` 与 `StadiumBorder`；
- 禁止 `lib/` 新增 Material `Icons.*` 引用；
- 禁止 `lib/views/` 新增裸 `AlertDialog(`、`showModalBottomSheet(` 与 `CircularProgressIndicator(`（仅共享原语内部豁免）。

## 代价与取舍

- 选择 `flutter_svg` 直渲染（方式 A）而非自定义 `.ttf` 字体：省去外部字体编译工具链并天然支持双色几何，同时让 `domain/` / `application/` 彻底脱离 `IconData`；单次解析成本由 `flutter_svg` 内部缓存分摊，在 24×24 简单几何路径下开销可忽略。
- 统一 4px 会影响既有组件与 Golden 快照，需按迁移阶段同步更新测试与基线。
