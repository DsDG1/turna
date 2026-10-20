# 鸿蒙构建与签名

> 这篇讲**怎么把鸿蒙包构建出来并签上名**。只覆盖伴生版 / Official Anki 档的构建链路；
> 能力边界（三层口径）见 [`status.md`](./status.md) §6，决策理由见
> [ADR 0047](./decisions/0047-ohos-companion-lite-build.md) 与
> [ADR 0050](./decisions/0050-ohos-official-anki.md)。
>
> **本文不含任何口令。** 口令只在本机两处：密钥库目录与被 git 忽略的
> `ohos/SIGNING.local.md`（见文末「秘密在哪」）。

## 1. SDK 与工具链

### 1.1 两份 Flutter SDK

| 用途 | SDK | 本机路径 |
|---|---|---|
| Android / iOS / Web 的 analyze、test、build | **官方** stable | `C:\Users\DsDogs\Desktop\developper\flutter` |
| 一切 `ohos/` 构建与 codegen | **OHOS fork** | `C:\Users\DsDogs\Desktop\developper\flutter_ohos_344` |

fork 路径来自 `ohos/local.properties` 的 `flutter.sdk`。两份 SDK 必须并存，原因见
[`AGENTS.md`](../AGENTS.md) §9.1：`pubspec.yaml` 的 `dependency_overrides` 是**全局无平台条件**的，
所以 `dart run build_runner` 一旦用了官方 `dart`，`.dart_tool/package_config.json` 里的
`flutter` 就指向官方 SDK，于是 `ohos/` 启动即白屏（`Unknown platform. ohos`）。

**切换后的恢复动作**：跑完官方 SDK 的 analyze / test，要用 fork SDK 重新
`pub get` 一次把 `package_config.json` 指回 fork，否则下一次 `ohos/` 构建会踩同一个坑。

```powershell
# 官方 SDK 侧（analyze / test）
& 'C:\Users\DsDogs\Desktop\developper\flutter\bin\flutter.bat' pub get

# fork SDK 侧（codegen / ohos 构建）
& 'C:\Users\DsDogs\Desktop\developper\flutter_ohos_344\bin\flutter.bat' pub get
```

### 1.2 HarmonyOS SDK（DevEco 侧）必须是 Release 档

上面两份是 Flutter SDK；把 ArkTS 编成 hap 的是 **DevEco 自带的 HarmonyOS SDK**。
它的根目录由 `DEVECO_SDK_HOME` 指定；`ohos/local.properties` 的 `hwsdk.dir` 是 fork
从同一处写出来的，构建时以环境变量为准。本机现在装在 `D:\1`（DevEco 根），SDK 在
`D:\1\sdk`。

| 检查 | 位置 | 期望 |
|---|---|---|
| SDK 根 | `$env:DEVECO_SDK_HOME` | 指向存在的 `<DevEco>/sdk`；指到已删目录会让 `flutter doctor` 报 `HarmonyOS Sdk not found` |
| 档位 | `<sdk>/<product>/sdk-pkg.json` 的 `releaseType` | `Release` |
| 组件 | `<sdk>/<product>/openharmony/{ets,js,native,previewer,toolchains}` | 五个都在 |
| 打进包的证据 | hap 内 `module.json` 的 `apiReleaseType` | `Release` |

**AGC 的「您的应用使用了 HarmonyOS beta 版本的 API」只认这一项，代码改不掉。**
`module.json` 的 `apiReleaseType` 跟着打包时用的 SDK 档位走：Beta 档 SDK 打出 `Beta1`，
Release 档打出 `Release`，SDK 里没有把它翻过来的开关，只能换装 Release 档重打。
本机 SDK 版本（`sdk-pkg.json` 的 `version`）随 DevEco 安装包走，查当前值即可，不要
写死在脚本里。

### 1.3 hvigor / ohpm / node

三者都在 DevEco 的 `tools/` 下，需要出现在 `PATH` 上：

| 工具 | 位置 | 本机版本 |
|---|---|---|
| hvigor | `<DevEco>/tools/hvigor/bin/hvigorw.bat` | 6.26.8 |
| ohpm | `<DevEco>/tools/ohpm/bin/ohpm.bat` | 26.0.0.630 |
| node | `<DevEco>/tools/node` | v24.14.1 |

缺哪个，fork 的 `flutter doctor -v` 就单独报哪个（`Hvigorw is missing` /
`Ohpm is missing`），不会笼统地说 SDK 有问题。

## 2. 构建命令

```powershell
# debug 签名包（可真机直装）
& '<fork>\bin\flutter.bat' build hap --debug

# release 分发包（AppGallery 上传用 .app）
& '<fork>\bin\flutter.bat' build app --release

# release 独立 hap
& '<fork>\bin\flutter.bat' build hap --release
```

产物落位：

| 产物 | 路径 |
|---|---|
| 签名 hap | `build/ohos/hap/entry-default-signed.hap`（另有一份在 `ohos/entry/build/default/outputs/default/`） |
| 签名 app | `build/ohos/app/ohos-default-signed.app` |
| 归档副本 | `dist/turna-v<版本>-ohos-release.hap` / `dist/turna-v<版本>-ohos-release.app` |

`.app` 里的内层 hap 是**未签名**的，签名块在 `.app` 层——验签要验 `.app` 本身，
验内层 hap 会得到 "No Hap Signing Block before ZIP Central Directory"。

### 构建前必须清两个缓存目录

本机工具链有批量删除保护，不清就会在 `FlutterTask` / `CompileArkTS` 阶段被打断，
报 `Error Code: 00308018` + `SAFE_DELETE_BULK_CONFIRM_REQUIRED`。**这不是 ArkTS 错误**，
两个目录都是纯构建产物：

```powershell
rm -- "ohos/entry/src/main/resources/rawfile/flutter_assets" `
       "ohos/entry/build/default/cache/default/default@CompileArkTS"
```

### 改了什么要重新 codegen

`@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` / drift 改动后，
用 **fork SDK** 跑 `make gen`，再跑 `build hap`。顺序反了会把官方框架编进去。

### hvigor 6 对 `ohos/hvigor/hvigor-config.json5` 的要求

DevEco 自带的是 hvigor 6.x，拿旧工程的配置会直接死在解析阶段，且错误不提“配置”：

| 症状 | 真因 | 处置 |
|---|---|---|
| `00305010` + `TypeError Cannot read properties of undefined (reading 'filter')` | 配置缺 `execution` / `logging` / `debugging` / `nodeOptions` 四段 | 按 DevEco 模板补齐，四段可以为空对象 |
| `00303027` + `The modelVersion in hvigor-config.json5 is X, and ... in oh-package.json5 is Y` | 两处 `modelVersion` 不一致 | 两处写成同一个值（本项目 `5.1.0`） |

模板在 DevEco 安装目录的插件里（`plugins/codegenie-plugin/previewProject/hvigor/`），
照抄结构即可，不要照抄它的 `modelVersion`——那个要跟 `oh-package.json5` 对齐。

### 插件清单与 `ProcessRouterMap`

`flutter-hvigor-plugin` 把插件依赖以**空版本**注入 hap 的依赖表，真实路径走 `overrides`。
如果 `.flutter-plugins-dependencies` 里 `plugins.ohos` 整段缺失（用**官方** SDK 跑过
`pub get` 就会这样），依赖表就只剩空版本项，hvigor 的 `ProcessRouterMap` 在
`declareInputs` 上抛 `ENOENT: no such file or directory, stat ''`（`Error Code: 00308018`），
构建在 ArkTS 编译之前就结束。

处置顺序：

1. 把 fork 的 `bin` 放到 `PATH` 最前，跑 `<fork>/bin/flutter.bat pub get`；
2. 确认 `.flutter-plugins-dependencies` 的 `plugins.ohos` 是 5 条（本机插件数，变了就按实际）；
3. 构建时加 `--no-pub`，避免构建过程又跑一次 `pub get`；
4. hvigor 6.26.8 起这条不再复现；仍停在旧 hvigor 时先升级 DevEco，改项目文件绕不过去。

## 3. 签名材料：五条硬规则

签名材料放在 `~/.ohos/config/`，由 `ohos/build-profile.json5` 的
`app.signingConfigs[].material` 指向。

### 3.1 三件套必须同一代

`storeFile`（密钥库）、`certpath`（证书链）、`profile`（profile）**必须来自同一次
签名材料的生成**。`hap-sign-tool` 会校验私钥与证书链叶证书是否配对，不同代就报：

```
ERROR: 11111002 Certificates error
  > Please check whether the keyAlias is correct
```

**工具给的提示是误导性的**——见 3.2。

实测矩阵（`sign-app` 直接调用，2×2×2）：

| keystore | cert | profile | 结果 |
|---|---|---|---|
| debug | debug | debug | ✅ |
| debug | debug | release | ✅ |
| debug | release | 任意 | ❌ 11111002 |
| release | debug | 任意 | ❌ 11111002 |
| release | release | 任意 | ✅ |

结论：**keystore 与 cert 必须同代，profile 两代都能用**（工具不交叉校验 profile）。

### 3.2 别名大小写：配置写 `debugKey` 是对的

`hap-sign-tool.jar generate-keypair` **自己把别名小写化**——传 `-keyAlias debugKey`
落盘后库内条目是 `debugkey`；传 `debugkey` 结果相同。`sign-app` 查别名时同样做小写归一：

- `-keyAlias debugKey` 对 `debugkey` 条目 → **签成功**，与传 `debugkey` 的产物逐字节一致；
- 传真错别名（如 `totallyBogusAlias`）→ 失败，报 "ensure keyAlias is exist"。

所以「配置写 `debugKey`、库里是 `debugkey`」是工具的既定约定，**不是配置写错**。
另外 `keytool -list -alias` 也会小写化，**不能用它去论证「别名查不到」**。

### 3.3 密码必须是加密 blob

`storePassword` / `keyPassword` 只能是 DevEco 的**加密 blob**，明文必挂：

- 短于 32 个 hex 字符 → `00303116`（"length ... less than 32"）；
- 够长 → 被当 blob 硬解 → `00303242`（"Invalid initialization vector"）。

那个 32 是 **hex 字符串长度**，所以「把明文补长」这条路走不通。

blob 结构（逆向 `hvigor-ohos-plugin/src/utils/decipher-util.js` 得出）：

```
hex( BE32(明文长度 + 16) || IV(12 字节) || AES-128-GCM 密文 || GCM tag(16 字节) )
```

密钥派生只依赖 `~/.ohos/config/material/`（`fd/{0,1,2}/`、`ac/`、`ce/` 三个目录），
**这份 material 是机器本地的、不在仓库里**。因此仓库里那段 debug blob 就算被看到，
没有本机 material 也解不开——这是它可以入库的前提。

### 3.4 product 必须引用 signingConfig

`app.products[].signingConfig` 要写 `'default'`（与 `signingConfigs[].name` 对应）。
漏了它，`SignUtil.getSigningConfig()` 返回 undefined，`executeSign()` 直接返回，
hvigor 只出 `entry-default-unsigned.hap`，fork 随后在
`getSignedFile(throwOnMissing: true)` 上失败。**只定义 `signingConfigs` 不写引用等于没写。**

### 3.5 debug profile 与 release profile 不是一回事

| | debug | release |
|---|---|---|
| `type` | `debug` | `release` |
| 分发类型 | — | `app_gallery` |
| app-identifier | `6918745411724992158` | `6917619511459549572` |
| `device-ids` | **含**（两台测试机 UDID） | **不含** |

真机直装必须用 debug profile：release profile 没有 `device-ids`，装到测试机会被
profile 拒。release profile 是给 AppGallery 分发用的。

## 4. 排错速查

| 症状 | 真因 | 处置 |
|---|---|---|
| `ERROR: 11111002 Certificates error` | keystore 与 cert 不同代 | 三件套取同一代（§3.1） |
| `00303116` / `00303242` | 密码是明文 | 加密成 blob（§3.3） |
| `entry-default-unsigned.hap` 有、signed 没有 | `products[].signingConfig` 没引用 | 补引用（§3.4） |
| `00308018` + `SAFE_DELETE_BULK_CONFIRM_REQUIRED` | 工具链批量删保护 | 先删两个缓存目录（§2） |
| 启动白屏 + `Unknown platform. ohos` | codegen 用了官方 SDK | 用 fork SDK 重跑 `pub get` + codegen |
| `...the tool couldn't find it: entry-default-signed.hap` | 同 3.4 | 同 3.4 |
| `HarmonyOS Sdk not found` | `DEVECO_SDK_HOME` 指向不存在的目录 | 指回现装 DevEco 的 `sdk`（§1.2） |
| `Hvigorw is missing` / `Ohpm is missing` | DevEco `tools/` 不在 `PATH` | 补 `hvigor/bin`、`ohpm/bin`、`node`（§1.3） |
| AGC：「使用了 HarmonyOS beta 版本的 API」 | 用了 Beta 档 SDK | 换 Release 档 SDK 重打（§1.2） |
| `00305010` + `reading 'filter'` | `hvigor-config.json5` 缺四段 | 按模板补齐（§2） |
| `00303027` + `modelVersion ... 5.0.0 ... 5.1.0` | 两处版本不一致 | 对齐成同一个值（§2） |
| `ENOENT: ... stat ''`（`ProcessRouterMap`） | 插件清单缺 `ohos` 段 / hvigor 太旧 | fork `pub get` + `--no-pub`；hvigor 6.26.8 起不复现（§2） |

## 5. 验签

```powershell
$java='<DevEco>\jbr\bin\java.exe'
$jar='<DevEco>\sdk\<product>\openharmony\toolchains\lib\hap-sign-tool.jar'
& $java -jar $jar verify-app -inFile <file.app> -outCertChain chain.cer -outProfile profile.p7b
```

成功时最后两行是 `verify: Verify success` 与 `verify-app success`，中间会打
`profile type is: release|debug`——**这一行就是“签的是哪一档”的直接证据**，比对着证书
指纹猜更快。hap 也能直接验（`.app` 的内层 hap 不行，见 §2）。

看 `chain.cer` 的叶证书指纹即可确认签的是哪一代：debug 叶证书与 release 叶证书
指纹不同（取值见 `ohos/SIGNING.local.md`）。也可以直接按 DER 逐字节比对产物内
是否含目标叶证书——`.app` 的签名块在文件尾。

## 6. 秘密在哪

| 内容 | 位置 | 是否入库 |
|---|---|---|
| 密钥库 / 证书 / profile | `~/.ohos/config/` | 否（仓库外） |
| **明文口令**、blob 布局、逆向过程 | `ohos/SIGNING.local.md` | **否**（`.gitignore` 已忽略） |
| release 档配置（含加密 blob） | `ohos/build-profile.json5.release` | **否**（`.gitignore` 已忽略） |
| debug 档配置（含加密 blob） | `ohos/build-profile.json5` | 是（blob 需本机 material 才解得开） |

切档：`ohos/build-profile.json5` 是**当前生效档**；`ohos/build-profile.json5.release`
是 parked 的 release 档。打包 release 时把后者覆盖到前者，打完再换回来。

**红线**：release 密钥库的口令、任何形式的明文口令、以及 `~/.ohos/config/material/`
的内容，都不得进入仓库、提交、CI 日志或对话记录。

## 7. 未验证 / 已知边界

- release `.app` 与独立 release hap 都能用 Release 档 SDK 打出来，`verify-app` 通过、
  `profile type is: release`、`module.json` 的 `apiReleaseType` 为 `Release`；
  但**都未真机安装**（release profile 无 `device-ids`，装不上测试机），也未经
  AppGallery 侧复核。
- debug 包的真机直装有收据；最近一次重签的包未再上机。
- Android 侧 `flutter build appbundle` 的 native 符号剥离失败，与本页无关，
  见 `test/BASELINE.md` 对应条目。
