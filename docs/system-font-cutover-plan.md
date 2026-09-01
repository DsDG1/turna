# 系统字体切换与无障碍字体功能移除计划

> 日期:2026-09-01 · 状态:host 施工完成(2026-09-01,定向 87 passed / analyze 0 新增 issue / rg 归零);真机验收未跑
> 触发证据:[logs/crash-hunt/](../logs/crash-hunt/)(六份 ANR trace、时间线、pause 栈、DNS 日志、采样脚本)
> 定性:用户报告的「导入 Anki 后闪退」= **ANR(输入派发超时)被系统击杀**,不是 native crash。

---

## 1. 触发证据与根因链(为什么做)

真机(PLG110 / ColorOS 16)2026-09-01 六次 ANR(19:57、21:01、21:40、21:41、21:42、21:47)同签名:

```
Input dispatching timed out ... Waited 5000ms for MotionEvent(DOWN)
→ ActivityManager: Killing <pid>: user request after error
```

- 主线程(承载 Dart UI isolate)`state=R`,**utm 高达 124.9 秒 / 进程存活 188 秒**;无 SIGSEGV/SIGABRT、无 tombstone。
- 时间线(8 秒窗口):**241 帧 ≈ 每 vsync 一帧**,每帧全量 LAYOUT+PAINT+COMPOSITING+GPU raster、~2 个 `Canvas::saveLayer`;BUILD 仅 8 次/8 秒——不是重建风暴,是持续帧泵。
- pause-trap 抓到的最热应用层帧:`copyWith ← googleFontsTextStyle ← nunito ← build ← _flushDirtyElements`。
- 网络层:进程对 `fonts.gstatic.com` 的 DNS 解析持续返回 **408**;`run-as` 核实 App 沙箱内 **google_fonts 缓存目录不存在**(字体从未加载成功过一次)。
- 复现矩阵:**欢迎页 3/3 复现风暴,课程页 0/2**——与「Nunito (used by splash + onboarding)」的注释精确重合。

根因链:欢迎页永久动画循环(文字轮播 + 3s 换图)保证页面每秒都有 rebuild → 每次 rebuild 调 `AppFonts.nunito()` → `GoogleFonts.nunito()` 走**运行时字体拉取** → 大陆网络 fonts.gstatic.com 不可达 → 永远失败重试 + 文本 fallback 重解析 → 帧泵永续 → 主线程 CPU 饱和 → 触摸 5s 无人消费 → **ANR 击杀**。硬杀再导致 SharedPreferences 异步写丢失(courseScope/courseOrder 回退,step4.md K14),重启落回欢迎页 → 风暴自续。

**只要不处理,每个大陆网络用户都会走进该循环**——不是设备特例。

## 2. 方案定案

1. **google_fonts 整体移除,全 App 使用系统字体**。调用面实测仅 5 处且全部收敛在 `AppFonts` 包装类后;全 App 主题本就未设 fontFamily(系统字体),中文文案因 Nunito 无 CJK 字形一直走系统回退——视觉变化仅欢迎页拉丁字形(Nunito → Roboto)。
2. **无障碍字体功能(dyslexiaFont / Lexend)整体下线**,含设置项、Provider 字段、备份清单条目、l10n 键。存量 pref 键无消费者后静默无害,不做数据迁移。

## 3. 范围围栏(先说清楚不做什么)

| 不做 | 归属 |
|---|---|
| 欢迎页动画循环治理(轮播/换图加生命周期门控或改有限次) | 独立产品决策;本计划灭掉风暴根因后,动画只剩 ~1 次/秒 setState,无害 |
| K14 prefs 写穿(courseScope/courseOrder 硬杀丢失) | 独立问题;ANR 不再发生则该路径自然不被触发 |
| highContrast / reducedMotion / textScale 等其余无障碍功能 | 只删 dyslexiaFont 一项 |
| 打包 Nunito/Lexend 为资产的混合方案 | 已否决:系统字体零网络依赖、零资产、确定性 100%;Lexend 无障碍价值随功能下线不再需要 |
| web 分支 `_bypass` | 随 `AppFonts` 类整体删除 |

## 4. 任务分解

### A. 移除 google_fonts 与 AppFonts

| # | 文件 | 动作 |
|---|---|---|
| A1 | `pubspec.yaml:24` | 删 `google_fonts: ^8.1.0`;`flutter pub get` 顺带瘦身 lock |
| A2 | `lib/views/app_fonts.dart` | **整文件删除**(全工程唯一 import google_fonts 的文件,已核实) |
| A3 | `lib/views/splash/components/center_display.dart:106,121,136` | 3 处 `AppFonts.nunito(...)` 内联为 `TextStyle(...)`(参数 fontSize/fontWeight/color/letterSpacing/height 全兼容直迁);删 app_fonts import |
| A4 | `lib/views/app.dart:67-72` | dyslexia 主题分叉整段删除(见 B4),`theme`/`darkTheme` 直接取 `light`/`dark`;删 AppFonts import |

### B. 下线无障碍字体功能

| # | 文件 | 动作 |
|---|---|---|
| B1 | `lib/application/accessibility_provider.dart` | 删 `_dyslexiaFont` 字段(34)、getter(46)、prefs 装载(71-72)、`setDyslexiaFont`(134-137)、类 doc 中对应行(20) |
| B2 | `lib/application/accessibility_capabilities.dart` | 删 `dyslexiaFriendlyTypography` 接口声明(27-28)、生产实现(57)、桩实现(99)及 doc 注释 |
| B3 | `lib/views/settings/widgets/settings_accessibility_section.dart:215-224` | 删 `SettingsDyslexiaFontTile` |
| B4 | `lib/views/settings/pages/accessibility_settings_page.dart:43` | 删 tile 挂载 |
| B5 | `lib/service/locator.dart:278` | 删 `LocalStateKeys.dyslexiaFont` 常量 |
| B6 | `lib/backup/backup_manifest_policy.dart:144` | 删备份 pref 清单条目(旧备份恢复携带该键时无消费者,静默忽略) |
| B7 | `lib/l10n/app_strings.dart:381-382` | 删 `settingsDyslexiaFontTitle` / `settingsDyslexiaFontSubtitle`(手写常量类,无 arb 同步面) |

### C. 测试与文档

| # | 文件 | 动作 |
|---|---|---|
| C1 | `test/application/accessibility_provider_test.dart:26,99-107` | 删 dyslexiaFont 持久化轮回断言 |
| C2 | `test/application/accessibility_capabilities_test.dart:29,49` | 删 `dyslexiaFriendlyTypography` 断言 |
| C3 | `test/BASELINE.md:303-307` | 更新基线记录(persisted flags 清单去掉 dyslexiaFont,Lexend 行为描述删除) |
| C4 | 施工时补查 | `rg -i "dyslex|AppFonts|google_fonts" lib test` 归零;splash/settings 相关测试目录定向复跑 |

已核实零引用面:`SettingsDyslexiaFontTile` 与 `AppFonts` 在 test/ 下无任何引用;dyslexiaFriendlyTypography 无 UI 消费者。

## 5. 数据与兼容

- 设备上已存的 `settings.dyslexiaFont` pref:读取者消失后为死键,无害、不迁移;新备份不再携带。
- 曾打开该开关的设备:恢复默认主题(系统字体),行为等同功能从未开启。
- 视觉回归面:仅欢迎页/引导页拉丁字形("Turna"、"Learn Turkish" 等)由 Nunito 变 Roboto;中文与全 App 其余界面零变化。

## 6. 验收清单

**Host(全部满足才算完):**

- [ ] `rg -i "dyslex|AppFonts|google_fonts" lib pubspec.yaml` 归零(test 仅剩 BASELINE.md 历史记录)
- [ ] `flutter analyze`:改动文件零新增 issue
- [ ] `test/application/accessibility*`、`test/views/settings*`、splash 相关测试定向复跑全绿;受影响面与干净树基线逐名对比零新增失败(Step 3/4 同款 `git stash` 对照法)
- [ ] 无障碍页快照:阅读障碍 tile 消失,highContrast/reducedMotion/textScale 等 tile 原样

**真机(发布门禁,PLG110):**

- [ ] 冷启停留欢迎页 ≥3 分钟:`top` CPU 持续 ≤5%(风暴期实测 30-83%),期间用 `logs/crash-hunt/sampler.js` 抽查栈静默
- [ ] 连续 5 次冷启 + 每次欢迎页停留 1 分钟 + 点「开始使用」:`adb shell dumpsys dropbox --tag data_app_anr` 计数零增长
- [ ] 文字轮播/吉祥物换图动画照常(动画本身保留)
- [ ] 导入一个 apkg → 停留 ≥3 分钟 → 无 ANR(复现用户原始路径)

## 7. 风险与回退

- 视觉变化不可逆于产品层面(欢迎页品牌字形)——已与产品决策确认走系统字体。
- 回退 = 单 commit revert;功能下线无数据迁移负担。
- 若后续要恢复阅读障碍支持:按「系统字体 + 加大字距/行高」重设计,不回 google_fonts 运行时拉取。

## 8. 工作量估计

删除型小步:lib 9 文件 + test 2 文件 + pubspec,预计 **0.5 天 host**(含测试与基线对照),真机验证 0.5 天。

---

## 收据(施工后回填)

| 日期 | 事项 | 结果 | 证据(commit / 测试输出 / 真机数据) |
|---|---|---|---|
| 2026-09-01 | host 施工 A1-A4 / B1-B7 / C1-C4 | 全绿 | `rg -i "dyslex\|AppFonts\|google_fonts" lib test pubspec.yaml pubspec.lock` 归零;`flutter analyze` 改动文件 0 issue(6 个预存在 issue 全在未触碰的 anki/schema 测试文件);定向 87 passed(accessibility×2 + backup_manifest_policy + test/views/settings/ 全目录 + course_ready_guard + wetland_palette_contract);BASELINE.md 顶部已记条目。注:备份清单实际路径为 `lib/application/backup/backup_manifest_policy.dart`(计划中误写 `lib/backup/`) |
| — | 真机验收(PLG110 发布门禁) | 未跑 | 冷启欢迎页 CPU、dropbox ANR 计数、apkg 导入路径均待验 |
