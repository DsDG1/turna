# ADR 0062 — 彩色玻璃材质：白纸上的淡彩玻璃

> 状态：已接受 ｜日期：2026-10-31
>
> 前置：ADR 0033（湿地鹤色板，scheme A 锁死 `brandTeal`）、ADR 0035（去绿化：主色重锚 + 背景冷化）
>
> 真源：`lib/core/theme.dart`（`GlassLevel` / `GlassMode` / `_GlassSpec`）、`lib/views/widgets/glass_surface.dart`
>
> 关联：取代 ADR 0035 §2「light 背景冷雾中性化」的**背景策略**（色板本身不变）

## 背景

App 的卡片材质此前有三套并行实现，各自演化：

1. **Play / AI 的着色软卡**（`SoftCard` + `AccentIconChip`，8 + 7 个消费点）——accent @10% 平涂 + 中性双层投影。
2. **Lesson 交互系**（`InteractionOptionTile` + `LessonPracticeCard`）——`surfaceL1Fill` 底 + `cardTopLight` 顶光渐变。
3. **Settings 表单系**（`SettingsCard` / `SettingsTile`）——纯白 `cardBg` + `statCardBorder` 1px 线，几乎不碰主题 token。

同一套「卡片」在三个域里长得不一样，且都不是玻璃。`theme.dart` 里还残留了一代 `glassSurface` / `glassHighlight` / `glassStroke`（白霜透背景色），与实际观感不符。

## 决策

### 1. 全 app 统一为「白纸上的彩色玻璃」

**页面背景纯白，玻璃本体带淡彩，投影取同色相投回白纸。**

这与上一代 `glassSurface` 的物理模型**相反**，不可混用：

| | 一代（由本 ADR 取代） | 二代（本 ADR） |
|---|---|---|
| 背景 | 有色的湿地渐变 + 晨雾 | **纯白**（深色纯黑） |
| 玻璃 | 半透明白霜（白 55%） | **淡彩**（accent 9~19%） |
| 颜色来源 | 从背景**透**上来 | 玻璃**自己发** |
| 投影 | 中性 navy 4~8% | **同色相** 12~18% |
| 依赖 `BackdropFilter` | 是 | **否**（背后是白的，糊了还是白） |

### 2. 四个层级，一张参数表

| 层 | 用途 | 淡彩 | 白高光 | 描边 | 投影 |
|---|---|---|---|---|---|
| L0 | 画布 | 纯白 `#FFFFFF` | — | — | — |
| L1 | 内容卡 | accent 9→16% 纵向 | 34%→0 @40% | accent 26% | 16% y6 r10 + 13% y16 r34 |
| L1Subtle | 表单卡 / 长列表 | accent 7→13% | 34%→0 @40% | accent 24% | 15% y5 r9 + 11% y14 r28 |
| L2 | 浮起面 | accent 11→19% | 40%→0 @42% | accent 40% | 18% y5 r10 + 12% y12 r22 |
| L3 | 徽章 / 标签 | accent 13% 平涂 | — | — | 无 |

- 淡彩**上浅下深**，模拟玻璃厚度（上缘薄透光、下缘厚积色）。
- 白高光是一层独立的、集中在上部 40% 内衰减到 0 的提亮。
- 描边用 accent 本色而非白：有色玻璃的边缘因折射比中心更沉。
- **表单卡用 `L1Subtle` 而不是 L1**：中性灰的彩度天然低，`5→9%` 在白底上等于消失；同时长列表每行都带明显色相会让整屏发花，可读性优先。

> 层级表此后又追加了一档：`L1Quiet`（设置域深层页，淡彩与 `L1Subtle` 同档，只削白高光与投影）。定义与理由见 [ADR 0063](./0063-settings-glass-quiet-tier.md)。

### 3. 色相即语义

| 色相 | 承担 |
|---|---|
| `teal`（`glassFocus`） | 路径与焦点：章节头、复习主卡、下一课行、胶囊导航 |
| `sand`（`glassContainer`） | 容器：单元卡 |
| `clay`（`glassAchievement`） | 完成 / 成就：完美通过、完成页统计 |
| `warning` / `error` | 待办状态：待复习 / 需加强 |
| `glassNeutral` `#8CA0AB` | 默认与表单：设置、统计卡、错题列表 |

**章节头不用 section 自身色**。曾试过 `SectionVisuals.colorsFor(id).foreground` 做整卡 accent，section1 的成就黄会把整页染成黄调；换纯中性灰又会读作「脏白」。最终取 `teal` 的最淡档（L1Subtle），色相留在左侧图标块里。

### 4. 深色分支：罩染到不透明基面

深色下**绝不用半透明白做底**——会在纯黑画布上糊成灰雾。一律把淡彩 `alphaBlend` 到不透明基面（`#161616` / `#1C1C1C` / `#141414`，对齐既有 `surfaceL1Fill` / `surfaceL2Fill` / `cardBg`），再叠白高光与 accent 微光描边。投影改「顶部 white@0.05 微光 + 黑双层」，因为黑阴影投在 `#000000` 上等于隐身。

这与 `TurnaTheme.softTint()` 的深色分支是同一思路，保持了一致。

### 5. 高对比：短路回退，不是换视觉

`GlassMode` 作为 `ThemeExtension` 注册：light / dark 为 `on`，两套 high-contrast 为 `off`。`off` 时 `glassDecoration` 返回 **`cardBg` + `dividerBg` @1px** 的普通卡。

**这一条曾写错**：最初降级成「纯黑/纯白 + 1.5px 黑白边」，两个后果——黑白卡在 HC dark 下与纯黑页面同色、边界消失；1.5px 让每张卡长高 1px，把 420×760 的热力图 golden 撑变尺寸。降级的语义是**撤回**，不是**换一套**。

## 理由

### 为什么推翻 ADR 0035 §2 的背景策略

ADR 0035 把浅色背景冷雾中性化到 `#F3F7F9`，并确立「平板中性」的表面观。那是**在没有材质模型的前提下**的合理选择：页面与卡片都是近白，靠 1px 描边与微阴影分离。

引入淡彩玻璃后，有色的背景会让卡面那 9~19% 的淡彩失去参照——整页读成「被染过的底 + 灰白卡片」，玻璃感反而消失。**背景必须退场，颜色只能有一个来源。**

色板本身（6 个品牌 hex、`brandTeal` 锁定）不变，ADR 0033 继续有效。

### 为什么新开一条而不是修订 0033

0033 是**色板契约**（hex + 角色），本 ADR 是**材质/表面契约**（多层 alpha 叠法、同色相投影、四级高度）。两者正交，混在一起会让「scheme A 锁死」这个承诺失去意义。

### 为什么单层 gradient

白高光**预混进 `LinearGradient` 的 stops**，而不是叠第二层 fill：

1. `AnimatedContainer` 只能插值单个 gradient。`InteractionOptionTile` 有 180ms 的状态过渡、被 6 个 renderer 共用，双层 fill 会直接跳变。
2. 物理等价：白高光叠加 = 该处 accent 更淡（浅色）/ 基面更亮（深色），两种都能预先算成具体 stop 色值。
3. 少一层 `DecoratedBox`，全 app 数百张卡片各少一次合成。

### 为什么阴影色要降彩度

同色相投影直接用 accent 会出错：`success #FFD93D` / `warning #FF9F43` 会投出明显的黄橙光晕，白纸上尤其脏。统一先 `Color.lerp(accent, brandNavy, 0.28)` 再取 alpha——保留色相辨识，但读作「影子」而不是「发光」。这是对「同色相投影」字面的唯一偏离，集中在 `glassShadow` 一处。

### 为什么需要 `glassSolid`

单元卡与课程行是拆成多个 Sliver 子项逐行拼合的（保留懒加载）。上半用 `glassFill` 渐变，下半如果各自重新起渐变，接缝处会出现一道横断。`glassSolid` 返回淡彩最深端的实色，让下半段接住渐变的最低点。

## 范围外

- **排版 / 字号 / 间距不做**。ADR 0033 §明确不做 #6 的边界不变。
- **Anki WebView 渲染链不动**（第三方 HTML 自带样式）。
- **`tool/gui` 不参与**。GUI 是创作者桌面工具（ADR 0032），不消费玻璃材质层；`test_theme_parity.py` 的 8 色对等契约不变。
- **`glassBorder` 保留**。它（白 50% / 深 15%）服务 AppBar / chip / snackbar / 胶囊导航这类「浮起 chrome」，与内容卡描边语义不同，合并会毁掉顶栏边缘分离感。

## 影响面

- `theme.dart` 新增 `GlassLevel`、`GlassMode`、`glassFill` / `glassShadow` / `glassStroke` / `glassSolid` / `glassDecoration` / `glassEnabled`，以及 `glassNeutral` / `glassFocus` / `glassContainer` / `glassAchievement` 等色相常量。
- 新建 `lib/views/widgets/glass_surface.dart` 作为通用容器。
- 消费方按域推进：Play/AI（`SoftCard`）、Settings（`SettingsCard`）、做题（`InteractionOptionTile` / `LessonPracticeCard`）、课程树（章节 / 单元 / 课程行 / 下一课）、复习域（主卡 / 语法 / 完成 / 统计）。
- `AmbientBackdrop` 从「湿地渐变 + 晨雾 + 滚动视差」退化为无状态纯画布；`courseTreeGradient` 退化为纯白（深色纯黑）。
- `cardTheme.color` 并入玻璃色阶（`cardBackground` / `darkCardBackground` 由 `_glassSpec(l1Subtle)` 算出，不写死 hex）——`Card` 是单色容器画不出渐变，但必须和旁边的玻璃卡落在同一色阶上。
- `listTileTheme` 补齐（缩进 + `iconColor`），把 15 处裸 `ListTile` 的图标色收口。
- 所有 light / dark golden 基线因材质变更重录。
