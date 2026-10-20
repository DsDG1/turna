# ADR 0055 — AI 凭据在鸿蒙上真正落盘：vendored 插件 + 持久性实测

> 日期：2026-10-21 ｜ 状态：已接受（实现随同批提交）
>
> 关联：[ADR 0039](./0039-webdav-secure-credential-migration.md)（WebDAV 密码走同一套
> `SecureCredentialStore`）、[ADR 0047](./0047-ohos-companion-lite-build.md) §7.1
> （`dependency_overrides` 无平台条件带来的失败类）。

## 现象

鸿蒙上配置的 AI API key 在关闭应用后消失，重启后 AI 功能显示「未配置」，无任何报错。
同一份代码在 Android 上正常。

## 根因（两条，缺一不可）

1. **没有鸿蒙平台实现。** `pubspec.yaml` 的 `dependency_overrides` 只覆盖了
   shared_preferences / path_provider / url_launcher / package_info_plus / share_plus，
   `flutter_secure_storage` 用的是 pub.dev 官方包，其 `flutter.plugin.platforms` 里没有
   `ohos`，`GeneratedPluginRegistrant.ets` 因此也不会注册任何鸿蒙原生实现。
2. **官方 Dart 层在鸿蒙上必然抛异常。** 9.2.4 的 `_selectOptions` 按
   `Platform.isLinux/isIOS/isAndroid/isWindows/isMacOS` 分支选参数，鸿蒙这些判断**全为
   false**，直接落到 `throw UnsupportedError(UNSUPPORTED_PLATFORM)`。也就是说，即便原生
   插件注册成功，Dart 侧也走不到方法通道。这一条与 AGENTS.md §7.1 记录的
   「鸿蒙上 `Platform.is*` 全为 false」是同一个坑。

结果：`SecureCredentialStore.write` 每次都进 catch，`_pluginHealthy=false`，key 只留在
内存 Map 里，进程结束即失。UI 侧更糟——`isPersistent` 在新进程里初始为 `null`（即
`true`），于是 `keyStorageKind` 被标成 `secure`，界面宣称「已保存」，实际什么都没存。

## 决策

### 1. vendored `flutter_secure_storage`，只加一条 ohos 分支

`third_party/flutter/flutter_secure_storage` 是 pub.dev 9.2.4 的拷贝，**唯一改动**是
`_selectOptions` 里新增 `Platform.operatingSystem == 'ohos'` 分支，返回空 map。用字符串
比较而非 `Platform.isOhos`：后者只存在于 OHOS fork SDK，官方 SDK 下是编译错误，而
`dependency_overrides` 无平台条件（ADR 0047 §7.1 同一个失败类）。

空 map 是**有依据**的取舍，不是偷懒：鸿蒙原生侧
（`flutter_secure_storage_ohos` 的 ArkTS 实现）只解析 `sharedPreferencesName` /
`preferencesKeyPrefix` / `resetOnError` 三个键，其余全部取默认值（RSA 加密密钥 +
AES 加密数据），所以空 map 就是文档化的形状。也**不**引入 `OhosOptions` 之类的
`Ohos*` 标识符（AGENTS.md §7.1 禁令）。

### 2. 原生实现作为直接依赖引入

`flutter_secure_storage_ohos`（gitcode `openharmony-sig/fluttertpc_flutter_secure_storage`
tag `9.2.4-ohos-1.0.0`，path `flutter_secure_storage_ohos`）挂在 `dependencies` 下。它是
**直接依赖**而不是 `dependency_overrides` 条目：override 只能替换已存在的约束，不能新增
依赖，而 app-facing 包无法为它声明 `default_package`（那要求对方是自己的依赖）。
它只声明 `ohos` 平台，安卓/iOS/桌面构建不受影响；通道名与
`MethodChannelFlutterSecureStorage` 一致（`plugins.it_nomads.com/flutter_secure_storage`），
所以 Dart 侧不需要任何适配代码。

### 3. 持久性必须实测，不许猜

`ICredentialStore.isPersistent` 是同步 getter，在新进程里只能猜；猜 `true` 正是这次
「看起来存了、其实没存」的直接来源。新增可选接口 `IPersistentCredentialProbe`：

- `SecureCredentialStore.probePersistence()` 写一个哨兵键、读回、删除，据此**latch**
  `_pluginHealthy`；会话内首次 `write` 也做一次读回校验（接受但丢值的原生实现会被识破）。
- `AiEngineConfigHolder._refreshKeyStorageKind()` 优先用探针结论，`loadPersisted` 的
  每条返回路径都**在读取之后**再定 `keyStorageKind`。
- 配置页新增正向状态行：`secure` + 有 key 时明说「已加密保存在本机，重启后仍然有效」。

不实现探针的测试替身不受影响（接口是可选的），生产侧只有 `SecureCredentialStore` 一个实现。

## 备选与否决

- **prefs + 自建 AES**（原方案 B）：能活过重启，但要自己管盐与轮换，安全性弱于系统
  密钥库，且隐私文案与备份脱敏要同步改。既然鸿蒙侧有现成的 HUKS 系实现，不走这条。
- **自写 ArkTS 插件**：工作量最大且无额外收益。
- **直接把整包（含 app-facing）换成 fork 版**：fork 的 app-facing 包与 pub 9.2.4
  **逐字节相同**，同样会在鸿蒙上抛 `UnsupportedError`；它的可用形态是「import
  `package:flutter_secure_storage_ohos/...`」，那会把全平台的 app-facing 都换成 fork 的
  副本，收益与风险都不划算。

## 影响与边界

- 鸿蒙上 key 真正落盘（加密偏好），重启后无需重输；安卓/iOS 行为不变（vendored 代码除
  该分支外与 pub 9.2.4 一致）。
- `third_party/flutter/flutter_secure_storage` 需要跟随上游升级手工同步；升级 pubspec 中
  的 `flutter_secure_storage` 约束时**必须**同步该目录，否则 override 会把版本钉死。
- 探针每次冷启动多 3 次方法通道调用（写/读/删一个哨兵键），只在 `loadPersisted` 里发生。
- 备份口径不变：AI 凭据不进备份包（远程备份只覆盖明确的键白名单）。
