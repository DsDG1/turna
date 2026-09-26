---
name: testing-turna-ios-simulator
description: How to drive the Turna iOS app end-to-end on a booted Xcode simulator — build/install/launch commands, key UI entry points in the Chinese UI, file-picker staging tricks, and coordinate/log-capture gotchas for GUI testing.
---

# Turna iOS simulator end-to-end testing

Use when testing the Turna Flutter app on macOS with Xcode iOS simulators (no physical device).

## Build / install / launch

- Flutter lives at `~/flutter/bin/flutter` (3.44.x). Build: `~/flutter/bin/flutter build ios --simulator --no-codesign` (~15–70s). For a pristine bundle use `flutter clean` first — incremental `.app` dirs keep stale resource bundles from removed plugins (e.g. leftover Firebase_*.bundle files that are dead files, not crashes).
- Bundle id: `me.dsdogs.turna`. Product: `build/ios/iphonesimulator/Runner.app`.
- Multiple sims may be booted — ALWAYS pin the UDID instead of `booted`: `xcrun simctl list devices booted`. The frontmost Simulator window title shows its OS version.
- Commands: `xcrun simctl install <UDID> <Runner.app>`, `xcrun simctl uninstall <UDID> me.dsdogs.turna` (fresh first-launch), `xcrun simctl launch <UDID> me.dsdogs.turna`, `xcrun simctl io <UDID> screenshot out.png`.
- Sim log capture (catches Dart logger.w/print and crash signals): `xcrun simctl spawn <UDID> log stream --predicate 'processImagePath CONTAINS "Runner"' --level info > sim_log.txt` (run in background).

## First launch

Fresh install shows: iOS notification permission alert → welcome page 「开始使用」 button → home (4 tabs: 学习/练习/我的/设置). On relaunch the app lands directly on home.

## Key UI entry points (Chinese UI)

- 课程管理 (course list + 「从 Anki 导入课程」 card): globe icon at the LEADING edge of the 学习 tab app bar.
- 语音来源 tile: 设置 tab → 「外观与声音」 → 「语音来源」; tap → 播放示例 preview speaks 'Merhaba' and shows snackbar 「正在播放：…」.
- 学习 settings: 设置 → 「学习」; Anki 限额 section is gated by `OfficialAnkiNativeAvailability.current` (false on iOS).
- 数据与备份 export: 设置 → 「数据与备份」 → 「导出数据」 tile → bottom sheet → 「导出」 → iOS share sheet.
- 分享 Turna: 设置 → 「关于 Turna」 → scroll down to 链接 section → 「分享 Turna」.

## Gotchas learned the hard way

- **Tab bar hides on scroll**: on the settings root (and likely other pages) the bottom tab bar auto-hides when the page is scrolled down — scroll up first or your tab taps hit dead space.
- **Document-picker hit area**: in the iOS Files picker sheet, file icons sit ~y≈250 in 1024×768 desktop space (labels ~y≈300), much higher than they look. Zoom or take a simctl screenshot to aim taps — clicks near the label may miss.
- **Staging files into Files app** (for the document picker / UIDocumentPicker): place the file into the sim's `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Shared/AppGroup/<app-group>/File Provider Storage/` directory — that IS "On My iPhone". Find the dir with `find ... -name "turna_export*"` after an in-app export via share sheet → Save to Files, or just copy any file there. It appears under Recents/On My iPhone in the picker. Renaming a saved export's extension in that dir works too.
- **Silent-switch / iPad popover**: not observable on an iPhone simulator — verify share category/popover fixes by code path + absence of crashes only.
- The sim's `log stream` contains benign noise: UIKit `focusItemsInRect`, CoreAudio `processVolumeScalar`, VoiceDBClient `DecodingError` fallbacks, and expected `[OfficialAnki] ... library_missing ... fail closed` warnings on iOS. None indicate real failures.
