# Anki 导入页 UX 改造计划

> 目标：让 `AnkiImportPage`（`lib/views/anki/anki_import_screen.dart`）的**信息架构更清晰、关键决策更易懂**，不改动其底层的导入/解析/SRS 迁移逻辑。
>
> 范围：UI/IA + 文案。仅在确实必要时新增少量辅助 widget，不引入新依赖。

---

## 1. 现状速写

`AnkiImportPage` 是 5 步向导：

| Step | 内容 | 现状 |
|------|------|------|
| 0 选择 | 选文件 / 试用示例 / OHos 兜底 | OK，但 body 标题与 AppBar 重复；示例按钮与主 CTA 抢眼 |
| 1 解析 | 进度条 + 文案 + 取消 | 取消按钮是细小 TextButton，容易被忽略 |
| 2 预览 | 集合概要 / 牌组结构 / 智能组织 / 笔记类型映射 / 冲突报告 / 策略 / 学习进度 / 导入按钮 | **最差的一页**，8+ 个信息块垂直堆叠 |
| 3 导入 | 进度条 + 文案 + 取消 | 同 Step 1 |
| 4 完成 | 已导入 N 张卡 / 源卡 / 结构化 / HTML / 词汇 / 课时 / 暂停 / 埋藏 / 缺媒体 / 学习进度 | 10+ 个 `Text()` 平铺，墙 |

补充观察：

- **没有步骤指示器**：用户进入页面不知道自己在 5 步流程的哪一步
- **策略描述太干**：「更新已存在卡片，添加新卡片」「替换所有已存在数据」——只说了行为，没说**数据后果**（复习历史会不会丢？SRS 状态会怎样？）
- **`ankiMappingOverrideHint` 太长**：「点按可修改识别结果；同一笔记类型中的单选和多选会按每张卡的题面与答案分别判断。」后半段是技术细节，普通用户看不懂
- **AI 智能识别按钮**孤悬在笔记类型映射卡片之外，缺少引导文案
- **OHos 兜底**只在主选择器失败后出现，跨平台用户感知不到

---

## 2. 设计目标

1. **每步只问一个核心问题**：选什么 → 你将导入什么 → 如何识别 → 如何处理冲突 → 完成
2. **关键决策（策略选择）有明确数据后果**：用户选错之前能看明白
3. **进度可视**：步骤指示器让用户随时知道自己在哪
4. **完成页只突出最重要的数字**：细节折叠/分组
5. **零功能回归**：保留所有现有能力（AI 识别、智能分组、4 种策略、兜底流程等）

---

## 3. 推荐方案：分组卡片 + 步骤指示器 + 改写文案

不重构为 Tab/PageView，沿用现有 `_step` 状态机——改动小、风险低、回滚容易。

### 3.1 新增小组件（`anki_import_screen.dart` 内私有）

| 组件 | 作用 |
|------|------|
| `_WizardStepper` | AppBar 下的细条，5 个圆点 + 标签，活跃步高亮 brand teal；用在 Step 0/2/3/4（Step 1 是 loading 不显示） |
| `_SectionCard` | 比 `_InfoCard` 多一层结构：图标 + 标题 + 副标题 + children；用于预览页三大节 |
| `_StrategyOption` | 替代 `RadioListTile`：单张卡片，左侧 Radio，右侧图标 + 标题 + 描述 + "数据后果"小字（用 hint 颜色） |

放在文件底部，私有，不导出。

### 3.2 步骤改造细节

#### Step 0 · 选择文件

- **去掉 body 标题**「导入 Anki 牌组」（与 AppBar 重复）
- **主 CTA 区块**：
  - 大图标（保持 `upload_file_rounded`）
  - 副标题「从 Anki 桌面端导出 .apkg 或 .colpkg 文件，然后从这里导入」
  - 主按钮「选择文件」
- **示例牌组**改成底部独立卡片：「想先看看效果？→ 试用示例牌组」（`auto_awesome` 图标 + 简短说明）
- **OHos 兜底**：仍然只在 `ohos` 平台且主选择器失败时弹出 bottom sheet（保持现状），但**新增"从已下载文件选择"永久入口**作为弱化的 TextButton，让用户主动选择（现在只有选文件失败后才出现）

#### Step 1 · 解析中

- 加 `_WizardStepper` 显示「正在解析」
- 取消按钮升级为 `OutlinedButton` 并加 `Icons.close` 图标

#### Step 2 · 预览（核心改造）

按 3 个分节卡片重排，节与节之间用大间距 + 节标题说明：

**第 1 节 · 牌组内容**（"你将导入什么"）
- 牌组结构卡片：N 个牌组 / M 张卡片 / K 个媒体文件
- 智能组织卡片：识别到 X 个单元 / Y 节课 + 智能分组开关
- 合并展示：每节用 `_SectionCard`，副标题为"源文件统计"

**第 2 节 · 卡片识别**（"系统如何识别每张卡的题型"）
- 笔记类型映射卡片（保留）
- 把 `ankiMappingOverrideHint` 改短："点按可手动调整识别结果"
- AI 智能识别按钮**放进节内**，加一行小字"如未配置 AI，请在「设置 > AI 工具」配置后使用"
- 节副标题"逐卡自动判断单选/多选"放到映射卡片顶部小字

**第 3 节 · 导入方式**（"如何处理已存在的卡片和学习进度"）
- 冲突报告卡片：X 新 / Y 已存在（用进度条可视化比例）
- 策略选择（用 `_StrategyOption`，4 个卡片竖排）：
  - 合并：默认。新增 + 更新已存在。**SRS 与复习历史保留**。
  - 跳过已存在：只新增。已存在卡片不动，**SRS 与复习历史保留**。
  - 强制替换：删除旧牌组数据再重建。**SRS 状态与复习历史会丢失**。
  - 追加为新：作为独立副本添加（加后缀）。**两份数据共存**。
- 学习进度开关（用 SwitchListTile 但加更明确的副标题）
- **Sticky 底部按钮**「开始导入」用 `BottomAppBar` 或 `SafeArea + Padding` 固定，不随滚动消失

#### Step 3 · 导入中

- 加 `_WizardStepper` 显示「正在导入」+ 子步骤文案（"复制媒体" → "构建课程树" → "迁移 SRS" → "保存元数据"）
- 取消按钮升级为 `OutlinedButton`

#### Step 4 · 完成

重排为分层结构：
- **顶部大数字**："X 张卡片已就绪"（headline）+ 副标题"已创建 N 节课"
- **详情分组**（只显示非零项）：
  - **源数据**：源卡片 X / 结构化 Y / HTML 保真 Z
  - **词汇**：V 个词条已加入词典（如 > 0）
  - **状态提示**（合并到一起）：暂停 / 埋藏 / 缺失媒体（如有）
- **学习进度**：1 行，"已保留" 或 "已重置"
- **按钮区**：
  - 主按钮「立即学习」（保持）
  - 次按钮「完成」（保持）
  - 新增「查看牌组」链接到 `AnkiReviewRoute`

### 3.3 文案修改（`app_strings.dart`）

新增：

| key | 文案 |
|-----|------|
| `ankiImportSelectBody` | "从 Anki 桌面端导出牌组文件 (.apkg / .colpkg)，然后从这里导入。" |
| `ankiImportStepSelect` | "选择文件" |
| `ankiImportStepParse` | "解析中" |
| `ankiImportStepPreview` | "预览" |
| `ankiImportStepImport` | "导入中" |
| `ankiImportStepDone` | "完成" |
| `ankiPreviewSectionContent` | "牌组内容" |
| `ankiPreviewSectionContentHint` | "你将导入什么" |
| `ankiPreviewSectionMapping` | "卡片识别" |
| `ankiPreviewSectionMappingHint` | "系统如何识别每张卡的题型" |
| `ankiPreviewSectionStrategy` | "导入方式" |
| `ankiPreviewSectionStrategyHint` | "如何处理已存在的卡片和学习进度" |
| `ankiStrategyMergeDetail` | "SRS 与复习历史保留" |
| `ankiStrategySkipExistingDetail` | "SRS 与复习历史保留" |
| `ankiStrategyForceReplaceDetail` | "SRS 状态与复习历史会丢失" |
| `ankiStrategyAppendAsNewDetail` | "两份数据共存" |
| `ankiDoneSummary` | "%s 张卡片已就绪" |
| `ankiDoneDetailsSource` | "源数据" |
| `ankiDoneDetailsVocab` | "词汇" |
| `ankiDoneDetailsNotes` | "状态提示" |
| `ankiDoneProgressKept` | "学习进度：已保留" |
| `ankiDoneProgressReset` | "学习进度：按新卡重置" |
| `ankiDoneViewDecks` | "查看牌组" |

修改：

| key | 旧 → 新 |
|-----|---------|
| `ankiMappingOverrideHint` | 长文 → 短文 "点按可手动调整识别结果" |
| `ankiImportSelectTitle` | "导入 Anki 牌组" → 删除（与 AppBar 重复） |
| `ankiSampleHint` | "无需选择文件，立即体验 Anki 导入流程" → "想先看看效果？试用一个内置示例牌组" |

---

## 4. 涉及文件

| 文件 | 改动 |
|------|------|
| `lib/views/anki/anki_import_screen.dart` | 主要 UI 改造，新增私有组件 |
| `lib/l10n/app_strings.dart` | 新增 ~20 个 key，修改 3 个 key |
| `docs/anki-import-page-redesign.md` | 本文档 |

不改动：导入逻辑、解析器、组装器、SRS 迁移、AI 识别等所有 `lib/application/anki/*` 业务代码。

---

## 5. 验证方式

- [ ] 选文件 → 解析 → 预览 → 导入 → 完成，主流程跑通
- [ ] 4 种策略（合并/跳过/替换/追加）行为与之前一致
- [ ] AI 智能识别按钮工作正常
- [ ] OHos 兜底流程仍可用
- [ ] 学习进度开关在两种状态下的文案都正确
- [ ] 重新导入同一文件：冲突报告 Y 已存在 > 0，策略默认"合并"
- [ ] 窄屏（如 360dp 宽）：预览页无横向滚动条，所有卡片能完整显示
- [ ] 完成页：大数字醒目，详情分组清晰；零值不显示

## 6. 不在范围

- 不重构 `_step` 状态机为 declarative state
- 不引入新依赖（如 `stepper` 包）
- 不动导入/解析/SRS 等业务代码
- 不动样例牌组对话框
- 不动兜底 bottom sheet 的内部逻辑

## 7. 风险与回滚

- 改动集中在 `anki_import_screen.dart` 一个文件 + 一份 strings 文件
- 保留所有现有 `AppStrings.anki*` 旧 key，只新增不删除（兼容性零风险）
- 如需回滚：单文件 `git revert` 即可
