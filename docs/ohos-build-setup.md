# 鸿蒙构建与签名

> 这篇讲**怎么把鸿蒙包构建出来并签上名**。只覆盖伴生版 / Official Anki 档的构建链路；
> 能力边界（三层口径）见 [`AGENTS.md`](../AGENTS.md) §7.1，决策理由见
> [ADR 0047](./decisions/0047-ohos-companion-lite-build.md) 与
> [ADR 0050](./decisions/0050-ohos-official-anki.md)。
>
> **本文不含任何口令。** 口令只在本机两处：密钥库目录与被 git 忽略的
> `ohos/SIGNING.local.md`（见文末「秘密在哪」）。

## 1. 两份 SDK

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

## 5. 验签

```powershell
$java='D:\DevEco Studio\jbr\bin\java.exe'
$jar='D:\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
& $java -jar $jar verify-app -inFile <file.app> -outCertChain chain.cer -outProfile profile.p7b
```

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

- release `.app` 已在真机与 AppGallery 侧**未验证**（只验到 `verify-app` 通过、
  profile 为 `app_gallery` 分发档）。
- debug 包的真机直装在 2026-10-20 之前有真机收据；本轮重签的包**未再上机**。
- Android 侧 `flutter build appbundle` 的 native 符号剥离失败，与本页无关，
  见 `test/BASELINE.md` 对应条目。
