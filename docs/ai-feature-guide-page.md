# AI 助手功能介绍页

## 背景

`lib/views/ai/ai_hub_page.dart` 是 AI 助手的总入口，目前只有「最近任务」+「功能宫格」+「点击启动」三段，**没有任何一处解释每个功能是干嘛的、什么时候用、怎么操作**。对老用户够用，对新用户（包括从未碰过 AI 助手的 1.x 老用户和首次配置 AI 引擎的新用户）几乎是黑盒。

这次的目的是补一个**功能手册性质的介绍页**，让用户在任何时候都能翻一翻搞清楚 AI 助手都能做什么、怎么用得更好。

## 决策（已与用户对齐）

| 项 | 决定 |
|---|---|
| 入口位置 | AI Hub AppBar 右上角 ❓ 图标，push 进入新独立路由 |
| 内容深度 | 完整版：图标 + 作用 + 适用场景 + 操作流程 + 小贴士 |
| 覆盖范围 | 只列当前主推的 6 个（伴学板块 4 + 复习 2），创作类暂略 |

## 覆盖的功能（6 个，按 AI Hub 现有顺序）

### 伴学板块（4 个，对应 `_StartSection` 的 GridView）

1. **自由问答** — `Icons.chat_bubble_outline_rounded` / `brandTeal` / `AiTutorChatRoute`
2. **学习诊断** — `Icons.analytics_outlined` / `brandSky` / `AiDiagnosisRoute`
3. **收藏的回答** — `Icons.bookmark_outline_rounded` / `amethystLeague` / `AiSavedListRoute`
4. **深度讲解** — `Icons.account_tree_outlined` / `brandReed` / `AiDepthTutorSheet`

### 复习板块（2 个，对应 `_StartSection` 的 ToolsTile）

5. **按错题练习** — `Icons.history_toggle_off_rounded` / `brandTeal@0.85` / `TutorLaunchSheet(mistakes)`
6. **按弱词练习** — `Icons.quiz_rounded` / `brandReed@0.85` / `TutorLaunchSheet(weakWords)`

**不收录**：`设计课程` / `教材导入` / `课内助手` / `一键生成` / `词典扩展`（创作/课内小工具，后续可单独再补一版）。

## 目标页结构

```
AppBar   AI 助手 · 功能介绍        (左 ← 返回, 右 × 关闭)
─────────────────────────
[ Hero 渐变卡 ]
  大标题：6 个 AI 能力，一次看懂
  副标题：所有功能都依赖 AI 引擎
  chip 1：当前引擎状态(已配置 / 未配置)
  chip 2：i 隐私提示·仅本机
─────────────────────────
📘 伴学
[ 自由问答      ] [ 学习诊断      ]
[ 收藏的回答    ] [ 深度讲解      ]
─────────────────────────
🎯 复习
[ 按错题练习    ] [ 按弱词练习    ]
─────────────────────────
(底部空白 24)
```

**每个功能卡**（`_FeatureCard`）的内容块：

```
┌─────────────────────────────────────────────────┐
│ [icon chip]  自由问答                  [→打开]  │  ← 标题行
│                                                 │
│ 作用                                            │
│ 跟 AI 老师自由对话，问任何土耳其语相关问题。     │
│                                                 │
│ 适用场景                                        │
│  · 学完语法点想再追问                            │
│  · 想知道某个词的真实用法例句                    │
│  · 想让 AI 解释一段土耳其语句子                  │
│                                                 │
│ 操作流程                                        │
│  1. 点击卡片进入聊天页                           │
│  2. 写下问题，回车发送                           │
│  3. AI 实时流式回答                              │
│  4. 满意的回答可点 ❤ 收藏                        │
│                                                 │
│ 💡 小贴士：问题越具体，AI 越懂你。               │
└─────────────────────────────────────────────────┘
```

每张卡：
- 整卡是 `SoftCard`，accent 跟随该功能原色（保持 AI Hub 一致）
- 标题行：左 AccentIconChip + 功能名，右「打开」小按钮（点击 = 直接跳到对应路由）
- 段落标题（作用/适用场景/操作流程/小贴士）小一号、accent 着色
- 段落正文用 bodyMedium / bodySmall
- 列表用 `•` 前缀 / 数字编号

## 关键改动

### 1. 新文件 `lib/views/ai/ai_feature_guide_page.dart`

- `AiFeatureGuidePage`（`@RoutePage()`，对应 `AiFeatureGuideRoute`）
- 私有 `_FeatureGuideContent`（拆出来便于将来复用 / 静态预览）
- 私有 `_FeatureCard`（每张功能卡）
- 私有 `_FeatureSpec`（不可变 data class：icon / accent / title / purpose / scenarios / steps / tip / route / routeArg）

内容数据**硬编码**在文件顶部一个 const list 里（与 `changelog_page.dart` 的 `journeySteps` 风格一致；**不上 i18n**——这次是面向中文用户的 1.x 介绍页，等真要出英文版时再走 AppStrings）。

> **重要 trade-off**：硬编码文案放弃了多语言能力。**理由**：介绍页是 1.x 阶段的功能，AI 引擎本身也只在中国区试用；先让中文用户看清楚，比同时维护 6×5 段中英文案更聚焦。如果后面要做 i18n，把 `_FeatureSpec` 里的 5 个 String 字段改成 `AppStrings.xxxFn(int)` 的函数即可，结构不用动。

### 2. 修改 `lib/views/ai/ai_hub_page.dart`

`AppBar.actions` 加一个 `IconButton(Icons.help_outline_rounded)`：
- tooltip：「功能介绍」
- onPressed：`context.router.push(const AiFeatureGuideRoute())`

位置放在删除按钮（`Icons.delete_sweep_outlined`）**之前**（返回/关闭类放最右，辅助放左侧——这是 AppBar 通用约定）。

### 3. 修改 `lib/routing/routing.dart` + `lib/routing/routing.gr.dart`

`routing.gr.dart` 是 `auto_route` 自动生成的，**不直接改**——改完后跑一次 `dart run build_runner build --delete-conflicting-outputs` 让它自己重新生成 `AiFeatureGuideRoute`。`routing.dart` 一般不需要手动加，看下 `AutoRoute.declarative` 列表是否需要新页面注册（90% 情况下 build_runner 就能搞定）。

### 4. 复用现有组件

- `SoftCard` / `SectionTitle` / `AccentIconChip` — 来自 `lib/views/play/components/play_tiles.dart`
- 配色直接用 `TurnaTheme.brandTeal / brandSky / amethystLeague / brandReed`
- 路由跳转一律走 `context.router.push(...)`
- 文案以外的数字 / icon / 颜色 / 跳转行为全部沿用 `ai_hub_page.dart` 现有写法，确保**用户在介绍页点「打开」和从 AI Hub 直接点 tile 跳到的是同一处**

## 不做的事（明确边界）

- ❌ 不做 onboarding 首次引导弹窗（这次是「常驻手册」）
- ❌ 不做 12 个全功能版（只做 6 个主推）
- ❌ 不做英文文案
- ❌ 不动 AI Hub 现有 tile 布局
- ❌ 不新增工具组件
- ❌ 不引入新依赖

## 验证

1. `dart analyze lib/views/ai/ai_feature_guide_page.dart lib/views/ai/ai_hub_page.dart` — 无报错
2. `dart run build_runner build --delete-conflicting-outputs` — 重新生成 `routing.gr.dart`，新路由出现
3. 启动后：
   - AI Hub 右上角出现 ❓ 图标
   - 点击后进入介绍页，AppBar 标题为「功能介绍」/ 文案
   - 6 张功能卡按上述顺序展示
   - 任意卡上点「打开」直接跳到对应功能页
   - 返回键 / 顶部 ← 能正常回到 AI Hub
4. 暗色模式（`TurnaTheme` 自带）下 accent 颜色对调后无对比度问题
5. 滚动到底部，BottomBar 无 overflow

## 下一步

- 等用户在本 turn 确认本 plan
- 确认后顺序执行：
  1. 写 `ai_feature_guide_page.dart`（一次性写完整文件）
  2. 改 `ai_hub_page.dart` AppBar 加 ❓
  3. 跑 `build_runner` 重新生成路由
  4. `dart analyze` 验证
  5. 跑通后给用户做 commit 总结

预计 1 个完整 turn 内交付。
