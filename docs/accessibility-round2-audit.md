# 第二轮无障碍逐表面审计

审计日期：2026-08-23；2026-09-27 按 `lib/application/accessibility_provider.dart` 现状复核能力列。结论口径：`已实现` 表示能力在该表面有可观察效果；`不适用` 表示该表面没有对应的动态、声音或可裁剪装饰，因而不存在“有开关但无效果”的承诺。

> 口径变更（2026-09-01，`test/BASELINE.md` 同日条目）：`google_fonts` 依赖与「阅读友好字体」能力已整体下线，`lib/` 内 `dyslexia` / `Lexend` 零命中，本表不再保留该列。改为记录 `cardTextScale`（卡片字号 100%–200%），`AccessibilityProvider` 的能力集合因此是 6 项：根文字缩放、卡片字号、减少动态、高对比、安静反馈、专注模式。

| 表面 | 200% 字号 | 卡片字号 | 减少动态 | 高对比 | 安静反馈 | 专注模式 |
| --- | --- | --- | --- | --- | --- | --- |
| 设置 | 已实现：根 `MediaQuery.textScaler`，滑杆与分类页支持换行 | 已实现：`cardTextScale` 滑杆独立于根缩放 | 已实现：页面切换/展开动画使用零时长 | 已实现：根高对比主题、控件边界加粗 | 已实现：全局声音/触觉控制器静音 | 不适用：设置项均为用户主动操作，无推荐或装饰区 |
| Home | 已实现：根缩放，导航和课程树有大字布局测试 | 不适用：Home 不渲染 Anki 卡面 | 已实现：课程树、底栏、滚动隐藏动画静态化 | 已实现：实色底栏与强化边界 | 已实现：欢迎反馈和全局音触觉均受抑制 | 已实现：隐藏随机欢迎装饰，底栏改实色稳定态 |
| 复习概览 | 已实现：Hero/到期卡在大字时改纵向布局，无溢出测试 | 不适用：概览页不渲染卡面；卡片缩放作用于 Anki 复习器 | 不适用：概览没有持续或装饰动画 | 已实现：根主题；状态同时有文字、图标和数值 | 不适用：概览不主动播放声音或触觉 | 已实现：保留今日/待复习，隐藏 streak、质量、来源和洞察推荐入口 |
| 学习洞察 | 已实现：筛选可换行，热力图 200% golden | 不适用：洞察为 Flutter 自绘，不渲染卡面 | 不适用：图表为静态绘制 | 已实现：高对比明/暗 golden；热力格有边框、数值摘要和逐日语义 | 不适用：洞察不播放声音或触觉 | 已实现：保留筛选/KPI/曲线/热力图，隐藏次要统计和来源推荐区 |
| AI | 已实现：根缩放，聊天内容自然换行 | 不适用：AI 对话不渲染 Anki 卡面 | 已实现：流式更新合批；根 `disableAnimations` 关闭装饰过渡 | 已实现：根主题，状态有文本和图标 | 已实现：全局音触觉控制器静音 | 已实现：隐藏快捷推荐 chips，仍可手动输入 |
| Playground | 已实现：根缩放，范围 chips 可换行 | 不适用：Playground 不渲染 Anki 卡面 | 已实现：根 `disableAnimations`；模式入口无持续动画 | 已实现：根主题，选中/不可用均有图标与文字状态 | 已实现：全局音触觉控制器静音 | 已实现：隐藏 Hero 和 AI 推荐工具，保留内容范围与练习模式 |
| 装扮商店 | 已实现：商品详情与购买操作在大字时改纵向排列，价格不省略 | 不适用：商店不渲染 Anki 卡面 | 已实现：商品预览无自动动画 | 已实现：可用/不可用有语义 value、文字和 2px 边界，不依赖透明度 | 已实现：购买链不触发强音效或触觉 | 不适用：目录预览是辨认待购商品所必需，不属于可隐藏推荐 |
| 完成页 | 已实现：根缩放，完成内容可滚动/换行 | 不适用：完成页不渲染 Anki 卡面 | 已实现：装备效果替换为带“静态效果”语义的静态徽章 | 已实现：根主题；徽章以图标、边框及文本语义共同表达 | 已实现：完成效果本身无音效或触觉；全局控制器仍会抑制其他反馈 | 不适用：完成结果和下一步操作均是当前任务必要信息 |

## 卡片字号的实际作用域

`cardTextScale`（`AccessibilityProvider.cardTextScale` / `cardTextScaleOf(context)`）只被 Anki 卡面消费，不作用于上表任何表面：

- `lib/views/anki/anki_html_card_view.dart`：向卡面注入缩放层，100% 时不注入以保持默认。
- `lib/views/review/components/official_template_webview_body.dart`：转成 WebView 的 `textZoom`。
- `lib/views/anki_official/official_anki_reviewer_stage.dart`：官方 Anki 复习器对 HTML 模板与 `typedAnswer` 字号应用同一百分比。

## 可运行证据

- `test/golden/round2_accessibility_golden_test.dart`：学习洞察高对比 + 200% 字号的浅色 / 深色 golden。
- `test/views/review/review_dashboard_page_test.dart`：复习概览 200% 无溢出及专注模式裁剪。
- `test/views/review/learning_insights_accessibility_test.dart`：热力图文字摘要、逐日 Semantics、删除来源状态。
- `test/views/ai/ai_focus_mode_test.dart`：AI 推荐 chips 在专注模式隐藏。
- `test/application/accessibility_provider_test.dart`：6 项能力的默认值、100%–200% 钳制、持久化、预览 setter 与 `AccessibilityCapabilities` 契约。
- `test/views/home/bottom_navigator_test.dart`、`test/views/courses/course_tree_test.dart`：Home 高对比/减少动态/大字号布局。

## 豁免结论

不适用项只覆盖没有对应副作用的静态或任务必要表面；没有以“不适用”掩盖已存在的动画、声音、触觉或推荐区。后续若这些表面新增上述行为，必须同时消费 `AccessibilityCapabilities` 并补测试。新增会渲染 Anki 卡面的表面时，必须消费 `cardTextScaleOf(context)`。
