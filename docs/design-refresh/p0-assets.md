# P0 资产清单（设计翻新 · 全 App 重设计）

> 「湿地雾光」全 App 重设计计划的 P0 交付物之一。清点现有视觉资产的形态、落位与归属，标记 P1 需要重绘 / 新建 / 保持的部分。约束以 [app-design-refresh-plan.md](../app-design-refresh-plan.md) 第 3.3 节为准：教学图像语义优先，鹤形象保留识别特征，基础几何优先代码绘制。

## 栅格图像资产

| 资产 | 位置 | 用途 | P1 处置 |
|---|---|---|---|
| 应用 logo 三规格（`app_logo.png` / `app_logo_store_1024.png` / `app_logo_store_216.png`） | `assets/images/` | 启动页、关于页、商店规格 | 保留鹤识别特征，按新品牌语言统一轮廓/色彩/光感后重绘或校色 |
| 鹤角色 `turna_reading.png`、`turna_waving.png` | `assets/images/turna/` | 空状态、分享海报、致谢 | 清点确认全部使用点后按新语言重绘，保留角色可辨认性 |
| 断签插图 `offFire.png` | `assets/images/` | StreakBrokenDialog | 可被几何「熄灭火焰」构成替代或重绘 |
| Android launcher | `android/app/src/main/res/`（drawable 系含 night 变体） | 应用图标 | 随新应用图标同步；保留 adaptive icon 的前景/背景分层结构 |
| iOS AppIcon | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | 应用图标 | 同上 |
| 鸿蒙图标 | `ohos/AppScope/resources/base/media/`（`app_icon.png` + `foreground.png` + `background.png` 分层） | 应用图标 | 同上；分层结构是构建契约 |

## 代码绘制的品牌系统（重设计的主要载体）

| 系统 | 落点 | 现状 |
|---|---|---|
| 色彩与材质 token | `lib/core/theme.dart`（真源，与 `tool/gui/src/theme_tokens.py` 对等维护，ADR 0033 / 0035 / 0062 / 0065） | 品牌 hex 与玻璃/纸面参数已体系化；P2 按新版面重新校准浓度、投影与层级，不新增裸色 |
| 玻璃表面 | `lib/views/widgets/glass_surface.dart`（`GlassSurface` + 档位，ADR 0063 弱化档） | 轻量材质能力保留，按新版构图重新封装 |
| 几何图形 | `lib/views/widgets/turna_geometry.dart` | 现有涟漪、旅程、连接、成就四类静态绘制；按计划第 3.3 节五类图形语法（圆与半圆 / 平行弧线 / 拱形与竖矩形 / 交叠色片 / 斜切留白）扩展重建 |
| 间距与动效 | `lib/core/spacing.dart`、`lib/core/motion.dart` | P1 用真实内容校准后收口为 token |
| 图标 | Material Icons（全 App 无自绘 SVG 图标库） | P1 决定是否引入品牌图标族；引入则优先代码 / `flutter_svg` 兼容 SVG |
| 启动视觉 | 代码几何 + logo（无独立启动图） | 重设计为独立启动构图（计划 R01） |
| 分享海报 | `_ShareProgressSheet` 代码绘制（360×600，强制浅色常量色板自包含） | 重设计为独立构图，保持数据真实 |
| 空状态 | `PracticeEmptyState`（Material 图标 + 文案） | 按几何小主图方向重做，语义清晰优先 |

## 课程教学资产（不在本轮重绘范围，仅登记边界）

- 课程内容与媒体索引的真源是 [content_inventory_current.md](../content_inventory_current.md)（`python tool/export_content_inventory.py` 生成）；内置课程在 `assets/courses/`（manifest + 新课包），人工录音在 `assets/sounds/turkish/`。
- 课时插图经课程 JSON 引用、由 `CachedAssetImage`（解码上限 600 逻辑像素）渲染；P1 做核心视觉稿时从内容清单交叉出**教学插图清单**，与品牌装饰资产分别维护。
- 教学图像（茶杯、咖啡杯、角色形象等）不以抽象品牌装饰替代（计划第 1.3 节边界）。

## 记忆卡渲染资产（保真约束，不重绘）

- `assets/anki_reviewer/`：`reviewer.html` / `reviewer.css` / `reviewer.js`、`card-frame.html` / `card-frame.js`、MathJax 及其配置、`manifest.json`——第三方模板卡的渲染壳。
- 约束：卡内容区不加任何品牌包装、阴影或缩放（ADR 0062 例外条目 + CSP 白名单）；重设计只动宿主 chrome（上下文、评分带、进度头）。

## 待 P1 决定的资产事项

1. 鹤形象与应用图标的重绘数量：由使用点清点确定（鹤形象使用点 = 启动、关于、空状态、分享海报、致谢）。
2. 是否建立品牌图标族替代 Material Icons 的关键位置（主导航、题型控件、设置分组）。
3. 几何图形系统的浅色 / 深色 / 简化（高对比）三变体规格。
4. 栅格资产的导出规格表（尺寸、用途、落位），随首批视觉稿一并产出。
