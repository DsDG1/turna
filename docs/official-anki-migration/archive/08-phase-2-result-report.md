# Phase 2 官方原卡渲染结果报告

> 状态：`P2 IMPLEMENTATION IN PROGRESS` / `P2 TECHNICAL ACCEPTANCE NO-GO` / `P2 PRODUCTION NO-GO`  
> 日期：2026-08-17  
> 分支：`spike/official-anki-core-android`  
> 开工基线：`cc1484b30739bceeba07fe1a3be98b8b0e11018d`  
> P2FIX 基线：`docs/official-anki-migration/artifacts/p2fix/baseline.txt`  
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 明确排除：License、AGPL 展示、源码要约、法律确认

## 1. 决策

```text
P2 IMPLEMENTATION IN PROGRESS
P2 TECHNICAL ACCEPTANCE NO-GO
P2 PRODUCTION NO-GO
```

P2FIX 正在修补媒体 base/IRI/Range、MathJax 打包、真实 AV/TTS、card body class、
per-card sandbox、present ack、dispose 与 Typed Answer。存在任一 P0/P1 未用命令或
artifact 证明时，不得写 Technical Go。

Renderer 保持默认关闭。外部发布条件不在本报告中冒充技术失败或技术完成。

## 2. 基线

P2-000 开工基线见 `{SCRATCH}/artifacts/phase2/p2-000/baseline.txt`。
P2FIX 冻结见 `docs/official-anki-migration/artifacts/p2fix/baseline.txt`。

| 项 | 值 |
|---|---|
| HEAD | `cc1484b30739bceeba07fe1a3be98b8b0e11018d` |
| branch | `spike/official-anki-core-android` |
| submodule | `967aa0d578fc75181e292e95326f9b58698da25c` |
| Host debug `.so` | 215378856 bytes，sha256 `57590f2586cb2e34d706e2dc5e95302c94fcbe192412454a6ff41f71a20f20cb` |
| Android `.so` | 20207384 bytes，sha256 `111b0faee969d3766248a81189650b7ef4c10c975635f8766213ef541177a928`（可编译，真机 render 未测） |
| 审计 debug APK | 225637006 bytes，sha256 `9f2b4b0ef5afdb3156129131382a091c5b0af627e526bbd3013c30f2a8a80951`（可编译，**不是**设备验收；当时 APK **不含** MathJax） |

Android `.so` strings 含 `RENDER_CARD` / typed ops，但仍未完成真机 render/typed-answer 验证。

## 3. 分栏证据

| 能力 | Fake | Host FFI | Android JVM | Android debug | Android release |
|---|---|---|---|---|---|
| Contract 1.1 / optional bodyClass | 通过（命令见 §4） | Host 九套 fixture 曾通过；IRI/bodyClass 以本轮 Rust/Dart 单测为准 | n/a | 未测 | 未测 |
| 9 fixture official raw HTML | Native golden 比较 raw `questionHtml` | 曾通过 | n/a | 未测 | 未测 |
| display IRI vs raw | 本轮 contract/native 单测 | 未重跑全量 Host | n/a | 未测 | 未测 |
| Typed Answer compare/cloze | Fake + Native | 曾通过 | n/a | 未测 | 未测 |
| dispose / handle | Fake 100 次 | Native alloc/free | n/a | 未测 | 未测 |
| media path / Range / MIME | 共享 `media_path_vectors.json` Dart 单测 | n/a | 源码字符串不算通过；JVM 以 gradle 日志为准 | 未测 | 未测 |
| 离线 MathJax | manifest hash | n/a | n/a | 必须以 APK `unzip -l` 为准 | 未测 |
| AV/TTS 生产路径 | coordinator 单测；recorder 仅 test | n/a | n/a | 听测未做 | 未测 |
| per-card sandbox / present ack | JS/结构 + Dart 状态单测 | n/a | n/a | instrumented/真机未测 | 未测 |
| 第二设备 / release APK / clean CI / 5k cancel | 未测 | 未测 | 未测 | 未测 | 未测 |

## 4. 命令

```text
# P2 施工期（历史）
PROTOC=native/turna_anki_core/tools/protoc/bin/protoc \
  cargo test --lib --manifest-path native/turna_anki_core/Cargo.toml
# 当时 51 passed

flutter test test/application/anki_official
# 当时 77–79 passed

# P2FIX 门禁（已跑，见 artifacts/p2fix/ 与 scratch）
flutter test --no-pub test/application/anki_official
# 89 passed（连续两次 + recorder 搬迁后再跑一次）

cd android && ./gradlew :app:testDebugUnitTest --tests 'me.dsdogs.turna.anki.reviewer.*'
# 10 tests, 0 failures

flutter build apk --debug   # internal dart-defines on
unzip -l build/app/outputs/flutter-apk/app-debug.apk
# contains assets/flutter_assets/assets/anki_reviewer/mathjax/tex-svg-full.js
# apk sha256 39b404afa799495867343da7691ceb24117528936435414543f82ba8d9d56c2c
```

Native 关键用例：`render_goldens_match_official_html`（比较 **raw** HTML）、
`typed_answer_uses_official_compare_and_cloze_extract`、
`alloc_free_returns_handle_count_to_baseline`、
`engine_info_capabilities_include_render_ops`、
本轮 `encode_display_html` / bodyClass 单测。

不得把“源码存在某字符串”记为 Android 通过。

## 5. 任务收口

| ID | 结果 |
|---|---|
| P2-000 | 完成。基线已记录。 |
| P2-001 | 骨架完成。dispose 先 RPC；P2FIX 把超时 `engineClose` 移出 UI isolate。Android 反复进出未测。 |
| P2-002 | 完成。生产 worker 失败 fail closed。 |
| P2-003 | **未关闭**。新 debug/release APK、第二设备、5k Native cancel、clean CI 均未测。 |
| P2-004 | 完成。无 official→Legacy fallback。 |
| P2-010 | 完成 contract 1.1 三操作。bodyClass/IRI 为 P2FIX 加法字段，不升 1.2。 |
| P2-011 | 完成 Engine/FFI/Fake/Session 同一接口。 |
| P2-020 | 完成骨架 PlatformView。真机 100 卡复用未测。 |
| P2-021 | **路径规则已修补并有 Dart+Kotlin JVM 共享向量**（`media_path_vectors.json` 40+）。设备播放/拦截器计数仍未测，不得写成 Android 真机通过。 |
| P2-022 | **改为 per-card sandbox frame**（`card-frame.html`，无 `allow-same-origin`）。instrumented/真机脚本隔离未测。 |
| P2-023 | **策略+JVM CSP/path 测试已有**。无运行时 WebView 计数，不得写成 Android instrumented 通过。 |
| P2-030 | **正式页改为 `OfficialAnkiAvPlayerAdapter`**；recorder 仅在 test。coordinator 单测通过。听测未做。 |
| P2-031 | 空字段/未知字段/compare 失败可恢复；FrontSide `<hr id=answer>` 顺序有 Dart 单测。设备 IME 未测。 |
| P2-032 | **debug APK 已包含** `assets/flutter_assets/assets/anki_reviewer/mathjax/tex-svg-full.js`（见 `artifacts/p2fix/apk-debug-mathjax.txt`）。飞行模式真机未测。 |
| P2-040 | 完成内部预览入口。 |
| P2-041 | 完成 flags。`TURNA_OFFICIAL_ANKI_RENDERER` 默认 false。 |
| P2-050 | Host/Dart 曾回归。Android instrumented / 真机截图未测。 |
| P2-051 | **未完成（降级）**。Dart 路径套件 ≠ 设备拦截器计数。源码字符串断言不算 Android 通过。 |
| P2-052 | **未完成（降级）**。Native/Host render 回归 ≠ RSS/WebView 生命周期预算。 |
| P2-053 | **未测**。无签字用 debug/release APK、无第二设备。 |
| P2-060 | 本报告。状态为 Implementation In Progress，不是 Technical Go。 |

## 6. 产物

### Reviewer assets

`assets/anki_reviewer/manifest.json`：

- assetVersion：以文件内值为准（P2FIX 更新后不得再写过期的 p2-1/p2-2 混用而不更新 hash）
- MathJax：`3.2.2` `mathjax/tex-svg-full.js` sha256 `a4354ff94fd868aea0cc6eaaa79a57fda0588646fc46ee3700a349ee0a11cbe6`
- 来源：npm `mathjax@3.2.2` `es5/tex-svg-full.js`，运行时不访问 CDN
- debug APK **已包含** `assets/flutter_assets/assets/anki_reviewer/mathjax/tex-svg-full.js`
- 新 debug APK：225646697 bytes，sha256 `39b404afa799495867343da7691ceb24117528936435414543f82ba8d9d56c2c`
- 记录：`docs/official-anki-migration/artifacts/p2fix/apk-debug-mathjax.txt`

### Feature flags（默认 false）

```text
TURNA_OFFICIAL_ANKI_RENDERER
TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS
```

`allowsOfficialRenderer = renderer && engine && catalogReady && runtimeCapable && platformReady`

Renderer 不隐式打开 import。official source 失败不 fallback Legacy。

## 7. 未测与阻塞生产的条件

1. 用本轮 native 重编 Android `libturna_anki.so` 和新 debug/release APK。
2. 设备：official import → reopen → render → 翻面 → AV/TTS → Typed Answer。
3. 第二台不同 API/WebView 设备 smoke。
4. 真实 Native 5k import cancel 后恢复。
5. clean CI runner 一次完整成功。
6. 100 次进入/退出 reviewer 的 handle/WebView 计数。
7. 飞行模式 MathJax 与恶意卡拦截器计数。

在以上关闭前不得打开生产 `TURNA_OFFICIAL_ANKI_RENDERER`。

## 8. 回滚

关闭 `TURNA_OFFICIAL_ANKI_RENDERER`。不删除 Collection、catalog 或 Legacy 数据。
旧 native 缺 capability 时新 Dart 会 fail closed。
