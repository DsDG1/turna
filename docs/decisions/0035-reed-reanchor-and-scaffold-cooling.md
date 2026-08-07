# ADR 0035 - 去绿化：brandReed 重锚 + 背景冷化 + 章节换色

- **状态：** 已接受
- **日期：** 2026-08-06
- **前置：** ADR 0033（湿地鹤色板，scheme A 锁死 `brandTeal`）、ADR 0034（AI companion hardening）
- **真源：** `lib/views/theme.dart`、`tool/gui/src/theme_tokens.py`、`android/app/src/main/res/values/colors.xml`、`web/index.html`、`test/views/wetland_palette_contract_test.dart`

## Context

ADR 0033 定稿了「湿地鹤 (Turna = 鹤)」色板：~70% 雾面中性 / ~20% 湿地冷色 / ~10% 暖点缀，并锁死主色 `brandTeal = #1F727E`。但上线后整体视觉读作「绿油油」（草地感），与「湿地 + 鹤」的设计意图不符。根因不在主色（teal 本身没问题），而在三处偏绿 token 被大面积使用：

1. **`brandReed = #78C7B8`**（hue ~169°，薄荷/草绿）-- 被用作深色模式全部交互 chrome（AppBar icon / 按钮 / 底导航）、节点光晕、章节色块、头像装饰、GUI accent。色相偏绿，读作「春草」而非「湿地水」。
2. **淡绿相背景**（`scaffoldBackground #F3F8F7` / `background #F7FAF9` / 渐变末端 `#E8F2F0` 等）-- ADR 0033 原文称「雾白绿相背景」，绿通道略占优，铺满每屏 + 渐变叠加使整体色温偏绿。
3. **章节色块用了真绿**（Section 5 `leagueEmerald #27AE60` 草绿、Section 8 `brandReed` 薄荷）+ 游离硬编码绿（`achievements_provider.dart` Sage `#66BB6A`、`settings_account_section.dart` leagueEmerald icon）。

ADR 0033 仅锁死 `brandTeal`；`brandReed` 与 light scaffold 虽被契约测试断言，但未被 ADR 锁死，可改（须同步测试与三端镜像）。

## Decision

### 1. `brandReed` 重锚为「湿地青」

`brandReed` hex 由 `#78C7B8`（hue ~169° 草绿）改为 `#5FB8C4`（hue ~187° 湿地青）。色相从「草绿」移到「湿地水」，保留其作为 glow / 深色图标强调的角色。

- 对比度自检（`TurnaTheme.contrastRatio`）：reed on dark scaffold `#101B22` ≈ 8.3:1（≥3:1 icon 门槛）；黑字 on reed（HC dark onPrimary）≈ 10:1（≥4.5:1）；reed icon on black ≈ 8.3:1 -- 均通过。
- 23 处 `TurnaTheme.brandReed` 调用点自动跟随；2 处 domain 层 hex 副本（`avatar.dart` / `avatar_ring.dart` 的 `_reed`）手改同步。
- 删除两段 reed 基底死代码：`nodeGlowGradient`、`glowShadow`（全仓 grep 零调用）。

### 2. light 背景冷雾中性化

把淡绿相背景的绿/蓝通道对调，让蓝略占优，由「雾白绿」改为「冷雾中性」：

| Token | 旧 | 新 |
|---|---|---|
| `background` | `#F7FAF9` | `#F6F8FB` |
| `scaffoldBackground` | `#F3F8F7` | `#F3F7F9` |
| `divider` | `#E3EBE9` | `#E3E9ED` |
| `softGradient` 末端 | `#E8F2F0` | `#E8F0F3` |
| `courseTreeGradient` 三段 | `#F7FAF9 / #EFF7F5 / #E8F2F0` | `#F6F8FB / #EEF2F6 / #E8F0F3` |
| `inputFillColor`(light) / `inputDecorationTheme.fillColor` | `#F3F8F7` | `#F3F7F9` |

三端镜像同步：`colors.xml`（`turna_scaffold_light`）、`web/index.html`（scaffold 注释 + `background-color`）、`theme_tokens.py` `_LIGHT_PALETTE`（`bg` / `bg_input` / `toolbar_gradient_start` / `toolbar_gradient_end` / `border` / `ai_chat_bg`）。

### 3. 章节配色去绿（`section_visuals.dart`）

| Section | 旧 | 新 | 角色 |
|---|---|---|---|
| 5 出行 | `leagueEmerald #27AE60` | `anatolianClay #B85C3F` @0.16 | 鹤冠暖红（兑现 ADR 0033 clay 上位） |
| 8 启程 | `brandReed` @0.22 | `brandNavy #19324A` @0.18 + brandTeal fg | 湿地深水（避免与 Section 2 brandSky 撞色） |

8 个 section 现色相：黄 / sky青 / 橙 / 紫 / clay红 / diamond蓝 / ruby红 / navy深蓝 -- 无草绿，冷暖均衡。

### 4. 收敛游离硬编码绿

- `achievements_provider.dart` Sage `#66BB6A` -> `#4A95A8`（≡ brandSky；保持 domain 层不引 UI 的既有 hex 模式）。
- `settings_account_section.dart` 课时完成 icon `leagueEmerald` -> `anatolianClay`（clay 为 ADR 0033 指定的「完成/完美标记」色，语义贴切）。
- `avatar.dart` `_emerald` -> `_jewelGreen`（改名 + 注明 cosmetics 皮肤色，非品牌 token；ADR 0033 声明 league/cosmetics 皮肤 out-of-scope，hex 保留）。
- `leagueEmerald` token 保留（联赛皮肤用），但不再当章节底。
- GUI `theme_tokens.py` `success #27AE60` -> `#1E8449`（降饱和深青绿，保留 success 语义；`success_text` 与 HC 变体不动以保对比度）。

### 锁死边界（不动）

ADR 0033 scheme A 锁死的 `brandTeal #1F727E` / `brandNavy #19324A` / `brandTealLight` / `brandTealDark` / `brandSky` / `anatolianClay #B85C3F` / `warmSand #EAD9B8` 全部不变。主 CTA 渐变仍为 teal->tealLight。ADR 0033 的 5 个 clay 结构调用点（course_tree / learning_stats / about / play_hub / achievements）只增不移（本 ADR 在 settings 课时完成 icon 新增一处 clay）。

## Migration

1. `lib/views/theme.dart`：reed hex + 7 处背景 hex + 删 2 段死代码
2. `lib/domain/cosmetics/{avatar,avatar_ring}.dart`：`_reed` hex 副本同步
3. `lib/views/courses/components/section_visuals.dart`：Section 5/8 换色
4. `lib/application/achievements_provider.dart` + `lib/views/settings/widgets/settings_account_section.dart`：游离绿收敛
5. `tool/gui/src/theme_tokens.py`：`BRAND_REED` + `_LIGHT_PALETTE` + `success`
6. `android/.../colors.xml` + `web/index.html`：scaffold 同步
7. `test/views/wetland_palette_contract_test.dart`：`brandReed` 断言（L22）与 `turna_scaffold_light` 断言（L162）更新为新 hex
8. `test/golden/` 4 个 golden 基线 `--update-goldens` 刷新

## Consequences

- **视觉**：深色模式交互 chrome 由薄荷绿转为湿地青；浅色背景由淡绿相转为冷雾中性；课程页两个绿色块消失。整体读作「湿地 + 鹤」而非「草地」。
- **用户可感**：已装备 `ring_reed` 芦苇环的用户，环边框色由薄荷变为湿地青（预期内视觉收敛）。
- **契约**：`wetland_palette_contract_test.dart` 的 `brandReed` 与 scaffold 断言更新为新 hex；其余 23 条断言（含 brandTeal 锁死、clay 结构点、对比度闸门）不变。
- **Golden**：4 个 golden 基线刷新（纯色变，无布局变化）。
- **Breaking（库内）**：外部若依赖 `brandReed == #78C7B8` 需改 `#5FB8C4`。

## Follow-up

- 视觉资产任务（图标 / 吉祥物 / splash）按新 reed 取色（底 brandTeal/brandNavy，冠 anatolianClay，高光 brandReed #5FB8C4）。
- Phase 5（clay 补暖）的更多候选点（课程树完成非完美叠 warmSand、错题列表语法类 clay 暖底）留待视觉验证后择机补。
- 可选：`brandAsh` 羽灰 token（ADR 0033 follow-up，本轮不做）。

## Supersedes / relates

- Supersedes ADR 0033 中 `brandReed = #78C7B8` 与 light scaffold `#F3F8F7 / #F7FAF9` 的 hex 契约（scheme A 锁死的 `brandTeal` 不变）。
- Complements ADR 0033（湿地鹤色板）：在不改主色的前提下完成去绿化 polish。
