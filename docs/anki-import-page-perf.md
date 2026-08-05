# Anki 导入页性能优化计划

> 目标：减少 `AnkiImportPage` 交互时的卡顿感，主要面向万级卡片的导入场景。
> 原则：只做低风险、聚焦的优化，不重写状态机，不引入新依赖。

---

## 1. 卡顿源头（已诊断）

按"感知到的影响 × 修复成本"排序：

### 高影响

**A. `AnkiOrganizationResolver.preview` 在每次预览重建时都跑一遍**
- 位置：`lib/views/anki/anki_import_screen.dart` `_buildOrganizationBlock` 调用 `resolver.preview(notes, notetypes)`
- 复杂度 O(notes) — 万级卡片下每次切换策略/智能分组开关都会重新跑一遍
- 实际：用户改一次策略 → setState → 整页 rebuild → 重新跑 1 万次 `resolve()`
- 修复：`_preparePreview` 算一次，存到 `_organizationPreview` 字段，build 直接读

**B. `_preparePreview` 没有进度反馈，用户看到解析 spinner 一动不动**
- 位置：解析完成后才看到 `_step = 2`，但 `_preparePreview` 还在跑（hash 查 DAO、SRS 状态比对、词条数计算）
- 实际：用户感觉"卡住了"——特别是万级卡片的 SRS 比对（O(cards)）
- 修复：进入解析 spinner 时显示"正在准备预览…"，加 stepper 进度提示

**C. 整页 setState 重建粒度太粗**
- 位置：策略切换、智能分组开关、学习进度开关都触发全页 setState
- 实际：每次切换都重建 3 个 SectionCard + 所有 N 个映射行 + 4 个策略卡
- 修复：把策略区段和映射区段拆成独立子 widget，子 widget 只依赖自己关心的状态

### 中影响

**D. 解析/导入 progress 回调每次 setState 都重建 Stepper + body**
- 位置：`_parseFile` 和 `_executeImport` 的 onProgress 回调
- 实际：Stepper 是静态 5 步指示，每次都重建浪费
- 修复：把 Stepper 抽成只依赖 `_step` 的独立 widget（当前是 `Column` 内的子节点），或者用 `ValueListenableBuilder` 包裹

**E. AppBar 标题字符串拼接**
- 位置：build 方法里 `_isSample ? '...${...} · ${...}' : ...`
- 影响：每次 build 都重新拼字符串，浪费但极小
- 修复：移到 `initState`/构造期缓存为局部变量

### 低影响

**F. `_InfoRow` 重建** — 已经是独立 widget，可控
**G. `_Badge` / `_DoneGroup` 重建** — 廉价

---

## 2. 推荐方案

按优先级，4 步走。每步独立可回滚。

### 优化 1：缓存组织结构预览结果（最大单点收益）

**改动范围**：`anki_import_screen.dart`

- 在 `_AnkiImportPageState` 加字段 `AnkiOrganizationPreview? _organizationPreview;`
- `_preparePreview` 算完后赋值
- `_buildOrganizationBlock` 改为读取缓存字段，**不再调用 `resolver.preview()`**
- 处理：失败/取消时不更新缓存（保持 null，下次重试时算）

预期：万级卡片下，切策略/智能分组的体感从 100-300ms 降到 <16ms（1 帧内）。

### 优化 2：拆分子 widget 减少重建范围

**改动范围**：`anki_import_screen.dart`

- `_buildStrategySection` 返回的子树抽成独立 `StatelessWidget`（如 `_StrategySection`），构造参数只接收 `_strategy` + 必要 handlers
- 策略切换时，`_StrategySection.build` 重建，但内容区/映射区都不重建
- 同理，碰撞条 `_CollisionStrip` 已经是独立 widget，OK；映射行 `_NotetypeMappingRow` 也是独立 widget，OK
- 把 `_buildContentSection` / `_buildMappingSection` / `_buildStrategySection` 改成顶层 private widget（不再依赖 build 闭包内的局部变量）

预期：策略切换时，只重建 ~150px 高度的小区域，不再重建 3 个 SectionCard。

### 优化 3：parse 完成后给一个"准备预览"过渡

**改动范围**：`anki_import_screen.dart`

- 在 `_parseFile` 解析完 `collection` 后、调用 `_preparePreview` 前，加一段 `setState(() => _progressMessage = '正在准备预览…')`
- 同步在 Step 1 spinner UI 那里不需要改（已显示 `_progressMessage`）
- 用户感知：spinner 文字从"正在解析 Anki 集合…"变成"正在准备预览…"，知道在做事
- 进一步：把 `_preparePreview` 里的 DAO 查询和 SRS 比对也加进度更新（"查找历史导入记录…"、"比对已有复习进度…"）

预期：消除"卡住错觉"，万级卡片过渡更平滑。

### 优化 4：缓存 AppBar 标题字符串

**改动范围**：`anki_import_screen.dart`

- 在 `State` 字段加 `late final String _appBarTitle = ...`
- 在 `initState` 里根据 `_isSample` 计算一次
- build 时直接用 `_appBarTitle`

实际收益微乎其微（每帧 1 次字符串拼接 < 1μs），但代码更清晰，列为可选。

---

## 3. 改动文件

| 文件 | 改动 |
|------|------|
| `lib/views/anki/anki_import_screen.dart` | 全部 4 个优化都在这里 |
| `docs/anki-import-page-perf.md` | 本文档 |

不新增依赖，不动业务代码（导入器、组装器、SRS 迁移等）。

---

## 4. 验证方式

- [ ] 选大文件（> 5000 卡片）→ 解析 → 预览：进预览页后，切换策略/智能分组开关，无明显卡顿
- [ ] 解析阶段 spinner 文案有"正在解析…" → "正在准备预览…" → 跳到预览的过渡
- [ ] 重新导入同文件：策略默认 merge，碰撞数字正确（行为不回归）
- [ ] 切换策略：只有策略卡片视觉变化，上面的内容/映射区不闪烁（视觉确认重建范围收窄）
- [ ] 导入阶段进度条平滑（无明显跳变）
- [ ] 小文件（< 100 卡片）流程不变，体验无差异

## 5. 不在范围

- 不引入新依赖
- 不动状态机（`_step` 状态机保留）
- 不把 setState 替换成 ValueNotifier（属于较大重构，本次不做）
- 不把重计算移到 `compute()` 隔离（如果优化 1 + 3 够用就不做）
- 不动导入/解析/SRS 等业务代码

## 6. 风险与回滚

- 4 个优化独立、互不依赖；任何一个出问题都可单独 revert
- 行为不变化（仅性能提升），可对比旧版本逐步验证
