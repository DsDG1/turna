# P4 其余完善实施计划

> 文档代号：P4-POLISH  
> 日期：2026-08-18  
> 前置：`16` / `18` / `19`，以及 `artifacts/p4r2/device-a-timeout-fix.txt`  
> 本文件是 timeout 修好之后的 **其余完善**，不是 P5。

## 1. 结论先行

```text
已修：cardAccepted 误报 RENDER_TIMEOUT
本轮：PlatformView remount + Device A 20/100 门禁 + 诊断口径
Device A：B2 PASS / B3 PASS（artifacts/p4r2，APK a8161e88…）
P5-C：施工见 `21`（fixture only）
生产 flag：默认仍 false
```

## 2. 不要重做

- poll 只认 `renderComplete` / `renderError`（Device A：18 Good，timeout=0，35 次 renderComplete）
- unrenderable 分码；自动 bury = 0
- Host preview loader / golden / daily-limit 测试已在树里
- `cutoverEnabled = false`

## 3. 还开着的项

| 项 | 现状 | 本轮 |
|---|---|---|
| PlatformView remount | 18 张会话仍有一次 `create viewId=1` | 修 |
| B2 连续 20 张复用 | 未过（Congrats / remount） | 修完 remount 后重跑 |
| B3 release 100 + RSS/stall | 今日 due 已空，只打到 18–28 | 改 `new_per_day` 或跨日后再跑 |
| 内部页 `mode=none` | idle 显示 none，正式复习仍能开 | 修口径或提前起 worker |
| 评分脚本遇 Congrats | exit 2 | 队列耗尽且 timeout=0 算成功 |

## 4. 包 1：同一会话只创建一个 PlatformView

拆树点：

1. `_hcpp == null` 时先 `CircularProgressIndicator`，探测完成再换 `PlatformViewLink`
2. `card` 与 `_heldCard` 皆空时 Stage 换成 ProgressIndicator
3. fatal 整页 `ColoredBox` 盖住 WebView
4. 页面启动瞬间 `controller == null` 走另一套 surface

做法：

- 不要「占位 → 换 PlatformView」。默认 HCPP 建 View，失败再降级；或把 HCPP 结果缓存在 isolate，避免每个 State 闪一次占位。
- Stage 一旦放过 `OfficialAnkiReviewerView`，后续不得换成 Progress / 单独 ErrorView。
- 可恢复错误继续底部条；fatal 也叠在 View 上。
- 禁止按 `cardId` 换 Key；禁止失败就 dispose WebView。

验收：同一正式复习会话 `create viewId=` 只出现一次；连续 20 张 `timeout=0`、`superseded=0`。

## 5. 包 2：设备门禁

1. 只改当前 deck 的 `new_per_day` ≥ 100（或等跨日）。写入 artifact，不 wipe。
2. 同一份 internal-release APK 上跑 hash、20 张复用、100 张、RSS、stall。
3. `tool/official_anki_device_rate.py`：Congrats 且 timeout=0 → 成功。

`19` §5 能复算才许更新 `final-decision`。仍写 `P5-C HOLD`。

## 6. 包 3：诊断小完善

- 内部页进入即起 worker，或显示 `opening`，不要 idle `mode=none` 却能点正式复习。
- DST 矩阵 DEFERRED。
- `17` 不得把未复算的 20/100 写成 PASS。

## 7. 不做

```text
P5-C / cutover / 删 Legacy
打开生产默认 flag
改 AnkiReviewRoute
为超时重建 WebView
```

## 8. 顺序

```text
P4P-01  HCPP 探测不再拆 PlatformViewLink
P4P-02  Stage 不换走已创建的 ReviewerView
P4P-03  fatal overlay 不移出 WebView
P4P-04  评分脚本 Congrats = 队列耗尽
P4P-05  内部页 worker 口径
P4P-06  准备 due 后跑 20 + 100
P4P-07  更新 artifact；P5 仍 HOLD
```
