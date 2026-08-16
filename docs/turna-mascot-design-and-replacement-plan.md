# Turna 吉祥物设计规范、资产替代与优化方案

> **文档状态**：草案 / 规划中  
> **关联决策**：[ADR 0031（Turna 改名）](./decisions/0031-turna-rebrand.md)、[ADR 0033（湿地鹤视觉色板）](./decisions/0033-turna-wetland-crane-palette.md)  
> **单一真理源**：`docs/project-guide.md`、`lib/views/theme.dart`

---

## 1. 背景与目标

本应用已由原上游框架（针对印度语系的 Varnamala）完全重塑为专注于**土耳其语（Turkish）**的本地优先语言学习应用 **Turna**（土耳其语：鹤）。

在非视觉代码层面已完成更名与架构重构，但现有应用内的部分视觉资产仍遗留原版的卡通孔雀（Mala）。本方案旨在建立完整的 **Turna（鹤）吉祥物视觉资产标准**，明确老旧素材的替换映射、缺失资产清单、技术规范及代码迁移步骤。

---

## 2. 吉祥物核心设计规范

### 2.1 形象基准（2D 扁平现代卡通风）
- **物种**：鹤（Turna），融合安纳托利亚文化中“远方信使”的意象。
- **体态与轮廓**：2D 扁平矢量插画风格，线条清晰利落，萌态圆润，带有亲切的陪伴感。
- **标志性特征**：
  1. **头顶冠羽**：微翘的灵动羽冠，点缀安纳托利亚陶土暖红（`anatolianClay`）。
  2. **身体羽色**：腹部为纯净雾白色（Mist Neutral），背羽与双翼为深湿地青绿（`brandTeal`）渐变。
  3. **配件（信使属性）**：身跨纯色安纳托利亚陶土色皮革小邮差包（**无字母、无额外文字**）。
  4. **面部**：大而清澈的眼眸（`brandSky`/`brandReed` 眼神光），温暖黄色小鸟喙。

### 2.2 配色对照（严格对齐 `TurnaTheme`）

| 部位 | 颜色 Token | Hex 值 | 设计作用 |
|---|---|---|---|
| **腹部与主体** | Mist Neutral | `#FFFFFF` / `#F3F8F7` | 保持轻盈与各种明暗背景对比度 |
| **羽翼与背羽** | `brandTeal` → `brandTealLight` | `#1F727E` → `#2F7F8E` | 湿地冷色轴（主品牌色） |
| **头顶冠羽 / 邮差包** | `anatolianClay` | `#B85C3F` | 安纳托利亚陶土暖色（视觉点睛） |
| **鸟喙与爪部** | `warning` / `warmSand` | `#FF9F43` / `#EAD9B8` | 明亮亲切 |
| **高光与特效** | `brandReed` / `brandSky` | `#78C7B8` / `#4A95A8` | 音符、星星与光晕点缀 |

---

## 3. 当前已生成的基准资产

目前已在 `assets/images/` 生成核心姿态与应用图标概念基准图：

| 资产文件名 | 姿态描述 | 主要用途 | 状态 |
|---|---|---|---|
| [`turna_app_logo.jpg`](../assets/images/turna_app_logo.jpg) | 湿地青绿渐变底色，Turna 扁平现代剪影头像，陶土红点缀 | 应用桌面图标（App Icon）、商店主图、启动页 Logo | ✅ 已生成基准 |
| [`turna_waving.jpg`](../assets/images/turna_waving.jpg) | 单翅热情挥手打招呼，跨小邮差包 | 启动页、主页欢迎轮播、Profile 页面 | ✅ 已生成基准 |
| [`turna_reading.jpg`](../assets/images/turna_reading.jpg) | 认真捧着笔记本阅读学习 | 课文学习、生词表、语法解析卡片 | ✅ 已生成基准 |
| [`turna_listening.jpg`](../assets/images/turna_listening.jpg) | 佩戴青绿耳机沉浸式听音频 | 听力题（`listenOnly`）、智能朗读、TTS 播放 | ✅ 已生成基准 |
| [`turna_thinking.jpg`](../assets/images/turna_thinking.jpg) | 托腮歪头思考，头顶小灯泡 | AI 提示面板、AI Hub 导师、题目答疑 | ✅ 已生成基准 |
| [`turna_celebrate.jpg`](../assets/images/turna_celebrate.jpg) | 双翼高举欢呼，彩带与星星飞舞 | 单元通关、满分结算、连胜（Streak）达成 | ✅ 已生成基准 |
| [`turna_encourage.jpg`](../assets/images/turna_encourage.jpg) | 单翼握拳加油，温柔鼓励微笑 | 答错题安慰复习、错题本重做、难度进阶激励 | ✅ 已生成基准 |

---

## 4. 老旧资产替换映射表（Legacy Mala → Turna）

需将现有 `assets/images/mala/` 下的孔雀素材按以下关系进行替换与归档：

| 原素材（`assets/images/mala/`） | 新素材（`assets/images/turna/`） | 替换策略 |
|---|---|---|
| `mala_wave.png` / `mala_waving.png` | `turna_waving.png` | 直接替代（欢迎姿态） |
| `mala_reading.png` | `turna_reading.png` | 直接替代（阅读姿态） |
| `mala_excited.png` | `turna_celebrate.png` | 直接替代（欢呼姿态） |
| `mala_asking.png` / `mala_doubtful.png` | `turna_thinking.png` | 直接替代（思考/疑问姿态） |
| `mala_cute.png` | `turna_standing.png` / `turna_listening.png` | 替代为通用常态或听力态 |
| `mala_angry.png` / `mala_lusty.png` | `turna_encourage.png` | **移除愤怒/不合时宜情绪**，替换为温暖鼓励态 |

---

## 5. 尚缺少的资产清单（Gap Analysis）

为了完成全平台的完整交付，后续仍需补齐以下资产：

### 5.1 缺失的姿态切图（需透明背景 PNG）
1. ⏳ **`turna_encourage.png`（温暖鼓励）**：
   - 姿态：单翼握拳或手抚胸口，眼神温柔坚定（用于答错题、错题本复习，配合“去焦虑”教学法）。
2. ⏳ **`turna_flying.png`（展翅信使）**：
   - 姿态：双翼平展在天空/湿地上空翱翔，衔着小信封（用于 Anki 导入、等级跨越升级 A1→A2、分享海报）。
3. ⏳ **`turna_sleeping.png`（空状态/休息）**：
   - 姿态：窝在草窝里闭眼睡觉，带 `Zzz` 气泡（用于复习队列已清空、无错题的空状态展示）。
4. ⏳ **`turna_avatar.png`（圆形头像）**：
   - 姿态：Turna 正脸/微侧脸圆形头像切图（用于默认用户头像、AI 对话助手头像）。

### 5.2 应用图标与商店宣传资产（App Icons & Branding）
1. ⏳ **`app_logo.png` / `app_logo_store_1024.png`**：
   - 规范：1024x1024 高清母版，湿地青绿（`#1F727E`）圆角底色 + Turna 极简现代剪影/头像。
2. ⏳ **多端原生启动图标（Platform Launch Icons）**：
   - Android：`android/app/src/main/res/mipmap-*/ic_launcher.png` 及自适应图标（Adaptive Icons）。
   - iOS / macOS：`ios/Runner/Assets.xcassets/AppIcon.appiconset/`。
   - OpenHarmony (OHOS)：`ohos/AppScope/resources/base/media/app_icon.png`。
   - Windows / Linux / Web：`favicon.png`、`icons/Icon-*.png`。

---

## 6. 技术规格与交付标准

1. **格式要求**：
   - 正式发布资产必须为 **带 Alpha 透明通道的 PNG**（避免白色方块底）。
   - 推荐同步保留 **SVG 矢量源文件**，便于未来导出 @1x, @2x, @3x 各种分辨率。
2. **尺寸规范**：
   - 场景插画（如阅读、欢迎、庆祝）：基准建议 `512x512 px` 或 `1024x1024 px`。
   - 图标/头像：`1024x1024 px`（应用商店主图）、`256x256 px`（UI 头像）。
3. **去背处理流程**：
   - 当前生成的概念图为白色背景 JPG，在正式进入代码前需使用去背工具/矢量描摹工具转为纯净透明背景 PNG。

---

## 7. 代码迁移与接入步骤（Roadmap）

当透明 PNG / 矢量素材全部就绪后，执行以下代码接入工作：

1. **资源目录迁移**：
   - 创建 `assets/images/turna/` 目录，放置全套 `turna_*.png` 素材。
   - 运行 `flutter pub run build_runner build` 重新生成 `lib/gen/assets.gen.dart`。
2. **组件重构与替换**：
   - 重构 [`lib/views/home/mala_welcomes.dart`](../lib/views/home/mala_welcomes.dart) → 重命名为 `turna_welcomes.dart`，轮播接入新生成的 `turna_waving`、`turna_reading`、`turna_celebrate` 等。
   - 更新 [`lib/views/profile/widgets/share_progress_card.dart`](../lib/views/profile/widgets/share_progress_card.dart) 的海报底图与吉祥物。
   - 更新 [`lib/views/splash/components/center_display.dart`](../lib/views/splash/components/center_display.dart)。
3. **原生平台图标替换**：
   - 使用 `flutter_launcher_icons` 或脚本批量替换各平台的原生 Launcher 图标。
4. **清理与回归**：
   - 确认无任何残留的 `Assets.images.mala` 引用后，彻底删除 `assets/images/mala/` 目录。
   - 运行 `flutter test` 与 `flutter analyze` 确保测试基线稳定。
