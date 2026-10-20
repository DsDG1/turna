# ADR 0051 — 鸿蒙包名必须与安卓错开（`me.dsdogs.turna.hmos`）

- 状态：**已实施**（2026-10-20）
- 日期：2026-10-20
- 关联：[ADR 0031](./0031-turna-rebrand.md)（OHOS Bundle Name 那一行的目标值已被本 ADR 覆盖）、[ADR 0047](./0047-ohos-companion-lite-build.md) §5 收据表（记载的 `bundleName me.dsdogs.turna` 是当时的观测值，非永久约定）、[ADR 0041](./0041-ohos-product-eol.md)、[ADR 0047](./0047-ohos-companion-lite-build.md)
- 编号说明：0050 之后的下一个可用编号。

## 背景

AppGallery Connect 创建应用的表单对「应用包名」有两条硬校验，第二条是：

> 包名必须唯一，不能与其他应用包名相同。**HarmonyOS 应用包名也不能与 Android 应用包名相同。**

而 [ADR 0031](./0031-turna-rebrand.md) 的品牌统一把三个平台的标识符都设成了 `me.dsdogs.turna`：安卓 `applicationId`（`android/app/build.gradle`）、iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER`（`ios/Runner.xcodeproj/project.pbxproj`、`macos/Runner/Configs/AppInfo.xcconfig`）、Linux `APPLICATION_ID`（`linux/CMakeLists.txt`）、以及鸿蒙 `bundleName`（`ohos/AppScope/app.json5`）。跨平台同名对通用分发渠道是优点，对 AGC 是**阻断项**。

因此「统一标识符」与「AGC 唯一性要求」直接冲突，必须在鸿蒙这一侧让步。

## 决策

`ohos/AppScope/app.json5` 的 `bundleName` 由 `me.dsdogs.turna` 改为 **`me.dsdogs.turna.hmos`**；**其它平台标识符一律不动**。

### 为什么后缀选 `.hmos` 而不是换主段

- 后缀式改动**只影响鸿蒙**。换主段（如 `me.dsdogs.vernamala.hmos`）会让已上架的安卓包与本地 Android 侧配置脱节，且没有任何收益——AGC 只要求「不相同」，不要求「不能有共同前缀」。
- AGC 表单的「仅联运游戏要求包名必须以 `.huawei` / `.HUAWEI` 结尾」与本应用无关（教育类非联运游戏），`hmos` 不与任何保留后缀冲突。
- 长度 21 字符，满足 7–128；四段均为小写字母数字，符合 HarmonyOS 包名字符集。

### 明确不跟着改的东西

仓库里大量 `me.dsdogs.turna/xxx` 形态的字符串**不是包名**，是 MethodChannel 名（如 `lib/application/anki_official/render/official_anki_reviewer_protocol.dart` 的 `channelName`、`lib/service/audio_backend.dart`、`lib/service/speech_backend.dart`、`lib/utils/ohos_file_picker.dart`，以及 ArkTS 侧的 `AudioPlugin.ets`、`TtsPlugin.ets`、`SherpaTtsPlugin.ets`、`FilePickerPlugin.ets`、`AnkiReviewerProtocol.ets`）。它们只在 Dart ↔ ArkTS 两侧成对出现、**不经过系统按包名路由**，改包名不影响它们，也不需要改。[ADR 0048](./0048-ohos-companion-audio-tts.md) §已把「通道名双端一致」立为门禁断言，动这些字面量会连带触发该门禁——是纯粹的假伤。

## 连带后果：调试签名 profile 绑定了旧包名

调试签名不是「有密钥就能签」，而是**华为云签发**的 profile 内写死了 `bundle-name`。改包名后旧 profile 立即失效。实测收据（2026-10-20，`flutter_ohos_344` fork SDK，`flutter build hap --debug`）：

```
> hvigor ERROR: Failed :entry:default@SignHap...
> hvigor ERROR: 00303074 Configuration Error
Error Message: The bundleName in app.json5/hvigorfile.ts does not match
the bundleName in the generated SigningConfigs.
At file: ohos\build-profile.json5
```

**ArkTS 编译本身是 0 ERROR**，失败点只在 `SignHap` 这一步——即问题面精确等于「签名材料的包名绑定」，不是代码问题。

修复走 `devecocli signature generate --product default`（工作目录 `ohos/`），它用已登录的华为账号向云端重新申请一套绑到新包名的 p12 / csr / cer / profile 并回写 `ohos/build-profile.json5`。该命令**原地覆写**同名材料文件（文件名由工程名派生，与包名无关），所以旧包名的 profile 被直接顶掉、不会残留——这一点靠读 p7b 内的 `"bundle-name"` 字段确认，不是推测。

复跑构建：`✓ Built build\ohos\hap\entry-default-signed.hap`（279,246,471 bytes）。解包 `module.json` 核对，实际包名为 `"bundleName":"me.dsdogs.turna.hmos"`。

## 仍未做（不属于本 ADR 的范围）

本 ADR 只解决包名唯一性。上架本身仍缺：

- **release 签名**。当前 `ohos/build-profile.json5` 里是**调试** profile（p7b 内 `"type":"debug"`，且绑定了具体设备 UDID）。AGC 需要 release 证书，需在 AGC 后台走「自动签名」或上传自签证书后由 AGC 签发正式 profile。
- **版本号对齐**。`ohos/AppScope/app.json5` 是 `versionCode 1000000 / versionName 1.0.0`，`pubspec.yaml` 是 `0.9.0+5`，两者不一致。
- **包体**。上面那个 279 MB 是 debug 产物，且 `[ADR 0049](./0049-ohos-turkish-tts-sherpa-feasibility.md)` 已实测 x86_64 那套 sherpa 原生库是无用重量；上架包需要 release 构建 + ABI 收敛。
- **`vendor: "example"`** 是 `flutter create` 模板残留，上架前需换成真实主体。
- 资质、隐私政策 URL、截图等 AGC 表单物料。

## 门禁状态

本 ADR **未新增断言测试**。现有 `test/application/anki_official/ohos_eol_architecture_guard_test.dart` 只断言 `ohos/AppScope/app.json5` 存在，**不断言 `bundleName` 取值**；因此「鸿蒙包名与安卓 `applicationId` 相同」这一类回归目前仍靠自觉。这与 AGENTS.md §8「仅自觉」表同族——补一条断言（读 `app.json5` 与 `android/app/build.gradle`，两者 `bundleName` / `applicationId` 相等即失败）是把它升级为强制的路径，留待后续批次。
