# ADR 0033 — Turna「湿地鹤」视觉色板

- **状态：** 已接受
- **日期：** 2026-08-05
- **前置：** ADR 0031（Turna 改名）、`turna-partial-color-refresh`（局部配色刷新）
- **真源：** `lib/views/theme.dart`、`tool/gui/src/theme_tokens.py`；Web 外壳 `web/index.html` / `web/manifest.json` 与契约同步

## Context

产品已改名为 Turna（土耳其语：鹤）。局部配色刷新引入了 `brand*` token 与 clay/sand 暖点缀，但 Flutter 仍保留 `peacock*` 兼容别名，第二品牌色（`anatolianClay`）在高频路径使用不足，跨端契约缺少定稿 ADR。

## Decision

### 主色方案：**A — 锁死主色**

保持 `brandTeal = #1F727E` 及下列核心契约，**不做**方案 B 雾青微调、**不做**方案 C 灰蓝重锚。

### 设计语言

| 占比 | 角色 | Token 族 |
|------|------|----------|
| ~70% | 雾面中性 | scaffold / surface / card / text |
| ~20% | 湿地冷色 | navy / teal / sky / reed |
| ~10% | 暖点缀 | clay / warmSand |

- 主 CTA / 主按钮渐变：`brandTeal → brandTealLight`（禁止 clay 替换主 CTA）
- 第二品牌色：`anatolianClay`（`ColorScheme.secondary`）；`warmSand` 为 `secondaryContainer` / 浅暖底
- 删除全部 `peacock*` API 别名；现役代码与文档只使用 `brand*` / clay / sand

### Token contract（核心色）

| Token | Hex | 职责 |
|-------|-----|------|
| `brandNavy` | `#19324A` | 深色锚点、阴影染色、渐变起点 |
| `brandTeal` / `primary` | `#1F727E` | 主品牌色；白字按钮底；链接；选中 |
| `brandTealLight` / `primaryLight` | `#2F7F8E` | hover / 主按钮渐变终点 |
| `brandTealDark` / `primaryDark` | `#145A64` | pressed（Flutter `primaryDark` ≡ GUI `BRAND_TEAL_DARK`） |
| `brandSky` / `info` | `#4A95A8` | info、听力、次强调冷色 |
| `brandReed` | `#78C7B8` | glow、深色图标强调（禁止大面积浅底正文） |
| `anatolianClay` / `secondary` | `#B85C3F` | 第二品牌暖 accent |
| `warmSand` / `secondaryLight` | `#EAD9B8` | 暖浅底 / secondaryContainer |
| Light scaffold | `#F3F8F7` / `#F7FAF9` | 雾白绿相背景 |
| Dark scaffold | `#101B22` 系 | 中性偏蓝深色 |

**对比度底线：** 白字 on `brandTeal` ≥ 4.5:1；正文 on scaffold/card ≥ 4.5:1；次要文字 ≥ 3:1。高对比主题继续纯黑/纯白核心表面。

### Flutter ↔ GUI 命名对照

| Flutter (`TurnaTheme`) | GUI (`theme_tokens`) |
|------------------------|----------------------|
| `brandNavy` | `BRAND_NAVY` |
| `brandTeal` / `primary` | `BRAND_TEAL` |
| `brandTealLight` / `primaryLight` | `BRAND_TEAL_LIGHT` |
| `primaryDark` / `brandTealDark` | `BRAND_TEAL_DARK` |
| `brandSky` | `BRAND_SKY` |
| `brandReed` | `BRAND_REED` |
| `anatolianClay` / `secondary` | `BRAND_CLAY` |
| `warmSand` / `secondaryLight` | `BRAND_SAND` |

### Clay 使用规范（产品化）

- **用：** 课程树完成/完美暖角标；Profile 成就向指标 icon；About 品牌条 sand/clay 细饰；Play Hub 至多一处次要 soft tint
- **不用：** 整屏 clay 背景；主 CTA 替换 teal；与 error 红同时大面积出现

### 角色边界（语义色 vs 品牌色）

| 角色 | Token / 控件 | 用途 | 禁止 |
|------|--------------|------|------|
| **主 CTA / 链接 / 选中** | `brandTeal`、`buttonGradient` | 开始学习、Continue、FAB、BottomNav 选中 | 用 clay 或 success 黄当主按钮底 |
| **即时正误反馈** | `success` 黄 / `error` 红 / `warning` 橙 | 答题对错、会话反馈、提示条 | 把进度成就改成 success 黄冒充品牌 |
| **进度 / 完美 / 成就** | `anatolianClay` + 可选 `warmSand` 浅底 | 完成角标、完美 pill、成就 icon、品牌条 | 整页 clay；与 error 同屏大面积 |
| **连胜 (streak)** | `streakChipBg` / `streakChipText`（橙系） | 仅 streak chip；**不与 clay 叠在同一控件** | 用 clay 替换连胜语义 |
| **高对比主题 secondary** | HC light → `primaryDark`；HC dark → `brandReed` | 对比度优先，**可偏离 clay** | 为品牌一致性削弱 HC 黑白表面 |
| **Android 状态栏 / 导航栏** | 对齐 AppBar / scaffold 表面（light 白 / dark `#182832` / HC 纯黑白） | 冷启动 `styles.xml` + 运行期 `SystemChrome` / `AppBarTheme.systemOverlayStyle` | 用 `brandTeal` 大面积铺 status bar |

面积比例仍为 ~70% 中性 / ~20% 湿地冷色 / ~10% 暖点缀。方案 A 核心 hex **不变**。

### Out of scope（本 ADR 明确不做）

1. 吉祥物 / mascot 重绘  
2. App 图标（各平台）  
3. Splash / 商店截图 / 宣传 KV 插画  
4. `assets/images/mala/*` 及任何 bitmap 资产替换  
5. 课程 JSON 内容、听读素材  
6. 布局/字号/间距体系大改  
7. 联赛/成就皮肤大重做（league 语义色可保留）  
8. 方案 B/C 主色重调  

> 原则：**色先于图**。图标到位后再做半档 hex 校准即可。

## Migration

1. 删除 `peacockDeep` / `peacockTeal` / `peacockCyan` / `peacockTurquoise` / `peacockMint` / `peacockGradient`  
2. 调用点仅使用 `brand*` / clay / sand  
3. 硬编码品牌 hex 收敛到 token；GUI fallback 必须等于本契约  
4. 历史 ADR（0031、partial-refresh）保留原文；本 ADR 声明 peacock 别名已退役

## Consequences

- **Breaking（库内）：** 外部若依赖 `TurnaTheme.peacock*` 需改为 `brand*`  
- Golden 可能因 clay 点缀像素变化而需更新  
- Flutter / GUI / Web 必须同一窗口同步 hex  

## Follow-up

- 视觉资产任务：图标/吉祥物按本契约取色（底 `brandTeal`/`brandNavy`，冠 `anatolianClay`，高光 `brandReed`）  
- 可选后续：`brandAsh` 羽灰 token（本轮不要求）  
- 色板 polish（无图）：关键主 CTA 挂 `buttonGradient`、对比度自动化闸门、theme 内魔法数收敛、GUI secondary 深色 hover（见实施后续）

## Supersedes / relates

- Supersedes migration note in `turna-partial-color-refresh` regarding temporary peacock aliases (aliases removed)  
- Complements ADR 0031 (rebrand; visual tokens were out of that ADR’s scope)
