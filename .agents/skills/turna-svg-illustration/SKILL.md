---
name: turna-svg-illustration
description: Create, edit, and validate flat-design editable SVG illustrations and icons for Turna (vocabulary cards, story illustrations, listening character avatars). Combines semantic vector authoring rules with flutter_svg compatibility constraints and the Turna Wetland Crane palette.
---

# Turna SVG Illustration (`turna-svg-illustration`)

融合 `syi0808/svg-skills`（语义分件 + 画家算法 + 静态 SVG 校验）与 Turna 项目的 `flutter_svg` 渲染边界及「湿地鹤」品牌色板。

## 1. 适用范围与画幅规范

| 场景 | 推荐 `viewBox` | 风格要求 |
|---|---|---|
| 词汇卡插图（茶杯、咖啡杯、水杯等） | `0 0 240 240` | 居中主体（占画布 65%–75%），圆润几何 + 简练贝塞尔轮廓，可带柔和圆形/椭圆底衬 |
| 听力课角色头像（如店主 Ayşe） | `0 0 160 160` | 扁平半身/头像，五官与发饰特征鲜明，小尺寸（48px–64px）仍清晰可辨 |
| 小故事 / 情景插画（如咖啡馆场景） | `0 0 400 260` | 远景/中景/近景最多 3 层，焦点明确，不堆砌琐碎噪点 |
| UI 徽章 / 小图标 | `0 0 24 24` | 统一 `stroke-width="2"`，`stroke-linecap="round"`，`stroke-linejoin="round"` |

## 2. 四步精简工作流（源自 `syi0808/svg-skills`）

1. **先拆语义部件（Semantic Parts）**：
   动笔写 `<path>` 前，先用 `<g id="...">` 规划好从后到前的图层（如 `bg-aura` → `saucer` → `cup-body` → `tea-liquid` → `cup-rim` → `steam`）。局部修改已有 SVG 时只动目标 `<g>`，不重写整图，不改原有 `viewBox`。
2. **几何原语优先 + 防接缝白边（Overlap over Tangency）**：
   规则图形优先用 `<circle>` / `<ellipse>` / `<rect rx="...">` / `<polygon>`；有机曲线再用 `<path>`。**相邻色块交界处避免「刚好相切」**——下层部件主动向内延伸 1–2 个单位压在上层部件底下，防止栅格化时出现 1px 亮缝（hairline seam）。
3. **只写呈现属性（Presentation Attributes Only）**：
   全部颜色、描边、透明度直接写在元素属性上（`fill="#1F727E"`），保證 `flutter_svg` 一次解析成功。
4. **静态校验**：
   生成或修改 `.svg` 后，运行本技能自带的纯 Python 校验脚本：
   ```bash
   python .agents/skills/turna-svg-illustration/scripts/validate_svg.py <path/to/file.svg>
   ```

## 3. `flutter_svg` 硬性兼容红线

- **严禁标签**：`<style>`、`<script>`、`<filter>`（含 `feDropShadow` / `feGaussianBlur`）、`<foreignObject>`、`<image>`（禁嵌位图伪装矢量）、`<textPath>`。
- **阴影与高光替代方案**：需要阴影或体积感时，使用半透明色块（`fill-opacity="0.12"`）或 `<linearGradient>` / `<radialGradient>`，不用 `<filter>`。
- **无字原则**：课程插图尽量只画图形，不塞 `<text>`（避免跨端缺字体变豆腐块）；确需杯身字母或招牌符号时，直接转为 `<path>` 轮廓。
- **路径克制**：单个 SVG 元素总数控制在 80 个以内，坐标保留最多 1–2 位小数。

## 4. Turna「湿地鹤」色板速查（真源：`lib/core/theme.dart`）

优先使用以下品牌色与辅助色阶，保持全课程视觉统一（70% 雾白中性底 / 20% 湿地冷色轴 / 10% 安纳托利亚暖色点缀）：

| 角色 | Token | Hex | 插画典型用途 |
|---|---|---|---|
| 深水暗部 / 轮廓线 | `brandNavy` | `#19324A` | 主轮廓线、深色阴影、头发/瞳孔深部、咖啡馆深色木质结构 |
| 主品牌青 | `brandTeal` | `#1F727E` | 主体器皿、服饰主色、水面/背景主调 |
| 亮青过渡 | `brandTealLight` | `#2F7F8E` | 受光面、渐变终点、次级结构 |
| 暗青压深 | `brandTealDark` | `#145A64` | 器皿背光面、衣褶暗部 |
| 天青（听力/清透） | `brandSky` | `#4A95A8` | 水杯（`su`）、玻璃器皿反光、天空与窗户 |
| 芦苇柔光 | `brandReed` | `#78C7B8` | 植物叶片、蒸汽/高光点缀、浅色玻璃受光边 |
| 安纳托利亚陶土（暖主色） | `anatolianClay` | `#B85C3F` | 红茶茶汤（`çay`）、陶罐、屋顶、温暖服饰 |
| 暖沙底色 | `warmSand` | `#EAD9B8` | 桌面、盘子底色、浅暖背景衬底、糕点/泡沫 |
| 琥珀暖橙 / 金黄 | `warning` / `success` | `#FF9F43` / `#FFD93D` | 灯光、茶汤亮面、星光/成就点缀 |

> **常用材质补充色（与湿地鹤协调）**：
> 土耳其红茶透亮暗红 `#9E3B24` → 亮面 `#D46548`；土耳其咖啡浓褐 `#4A2C1D` → 油脂泡沫 `#C89B6E`；玻璃高光白 `#FFFFFF`（配 `fill-opacity="0.35"`）。

## 5. Phase Two 核心视觉锚点（保持跨课一致）

- **郁金香茶杯（`çay`）**：标志性束腰郁金香透明玻璃杯 + 小圆托盘（红白或陶土色边），杯中透出红亮茶汤（`#B85C3F` → `#D46548`），上方 2 条简练弧线蒸汽。
- **土耳其咖啡杯（`kahve`）**：厚壁小瓷杯（带几何纹饰或 `brandTeal` 釉色）+ 金属感/暖沙色杯托，顶部可见浅褐色浓密泡沫（köpük）。
- **水杯（`su`）**：简洁透明平底玻璃杯，`brandSky` (`#4A95A8`) 与 `brandReed` (`#78C7B8`) 表现清澈水体与液面椭圆。
- **店主 Ayşe**：温和亲切的咖啡馆女店主，暖色围巾或围裙（`anatolianClay` / `warmSand`）配 `brandTeal` 细节，深海军蓝（`#19324A`）柔和发丝与眉眼。
