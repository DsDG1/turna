# ADR 0026 — 本地资源库编辑器增强

> 状态：Accepted ｜ 日期：2026-07-20

## 决策

1. **跨 tab 统一搜索**：`ResourceEditorDialog` 顶部搜索栏同时过滤三个 tab（任意单元格的大小写不敏感子串匹配）；`ResourceTableWidget.apply_filter(text)` 隐藏不匹配行。
2. **多选批量删除**：表格改用 `ExtendedSelection` 模式；「批量删除」按钮一次删除全部选中行，带确认。
3. **查重**（`CourseAdapter.detect_duplicates`）：扫描 vocab 与 expressions，按归一化词条（转小写、去空白）匹配；返回 `{type, id, term, duplicate_in}` 字典列表，由「查重」按钮展示。
4. **资源包导入导出**（`CourseAdapter.export_resource_pack` / `import_resource_pack`）：把三张资源表导出为单个 JSON 文件 `{"vocab": [...], "expressions": [...], "grammar_points": [...]}`；导入支持按 id 合并（跳过重复）或整体替换两种模式。
## 理由

`ResourceEditorDialog`（vocab / expressions / grammar_points 的本地资源库）已有分 tab 的增删与 CSV 导入导出，但缺跨 tab 搜索、批量操作、查重、资源包导入导出，以及任何能识别 vocab 与 expressions 之间跨表重复的方式。
## 影响与边界

- 大资源表可快速过滤，不必逐 tab 搜索。
- 批量删除减少重复的确认对话框。
- 跨表重复（例如「nasılsın?」同时出现在 vocab 与 expressions）会被暴露。
- 资源包让整理好的资源集能在课程或团队之间共享。
- 包格式是纯 JSON，可纳入 git 版本管理。
