# Turna 局部配色刷新

- **状态：** 已接受
- **日期：** 2026-08-04
- **范围：** Flutter 主题、桌面课程编辑器主题 token、Web 启动外壳、当前主题文档与测试。

## 决策

Turna 保留既有 `#1F727E` 主色，只对主题 token、表面、交互状态和少量装饰色进行克制化调整：深色模式改为中性偏蓝的深色表面，主按钮使用 `brandTeal → brandTealLight` 渐变，荧光 mint 改为低强度 `brandReed`，并以 `anatolianClay` / `warmSand` 提供少量暖色层次。

Flutter 与 GUI 使用同一组核心值：`brandNavy #19324A`、`brandTeal #1F727E`、`brandTealLight #2F7F8E`、`brandSky #4A95A8`、`brandReed #78C7B8`、`anatolianClay #B85C3F` 和 `warmSand #EAD9B8`。

## 不变项

本次不重做页面布局、导航、字体、字号、间距、圆角、动画或图片资源。错误、警告、成功和 league 颜色仍保留原有业务语义；高对比度主题继续使用纯黑/纯白核心表面。

## 迁移策略

Flutter 暂时保留 `peacock*` 兼容别名，但新页面调用点使用 `brand*` token。GUI 旧常量已迁移为 `BRAND_*`，四套 palette 保持相同 token 集合。待外部兼容调用清理完成后，再删除 Flutter 别名。

## 验证

主题测试验证四套 palette 的完整性、Flutter/GUI 核心色值一致、主按钮渐变 token 与对比度约束、纯黑/白高对比度表面，以及荧光 mint 不再作为当前主题值出现。
