# ADR 0039: WebDAV 凭据迁移至平台安全存储

日期：2026-08-24
状态：已实施（设置页一次性清理计划 Phase 2）

## 背景

旧版将 WebDAV 密码以明文保存在 SharedPreferences 的
`remoteBackup.config` JSON 中（与 AI API key 迁移前同一模式）。备份清单虽然
结构上排除了该 key，但明文凭据落在普通偏好存储中不符合安全不变量。

## 决策

配置模型一分为三：

- `RemoteBackupEndpointConfig`：serverUrl / username / remoteRoot /
  includeMedia —— 可进普通偏好，`toJson` 无 password 字段；
- `RemoteBackupCredential`：密码只存在于 `SecureCredentialStore`
  （Android EncryptedSharedPreferences / iOS Keychain，见
  `lib/service/secure_credential_store.dart`），存储 id
  `remoteBackup.webdavPassword`；
- `RemoteBackupResolvedConfig`：运行时临时组合，不序列化、不日志。

### 迁移（幂等，boot 时执行）

`RemoteBackupConfigStore.migrateLegacyPlaintext()`（locator 启动时调用）：

1. 读取旧 `remoteBackup.config` JSON；无 password 字段 → notNeeded；
2. 安全存储不可用（插件缺失/降级）→ 保留明文原样，返回
   `secureStoreUnavailable`，下次启动重试——绝不删除唯一凭据副本；
3. 写入安全存储后**读回验证**，不一致 → `verifyFailed`，保留明文；
4. 验证通过后重写 endpoint JSON（不含 password），并复核存储文档确实
   不再含 password 字段；
5. 写入完成 marker `remoteBackup.credentialMigrated`。

### 页面行为（remote_backup_page.dart）

- 已保存密码显示"已保存凭据"占位，绝不回填明文；输入新密码才替换；
- 显式"保存并测试"按钮（保存即测试），禁止逐字符持久化；
- 任何编辑立即失效旧的连接测试结果；
- dispose 时先摘除监听再清空密码草稿。

## 后果

- 新安装永不将 WebDAV 密码写入普通偏好（配置测试断言 prefs 无
  `remoteBackup.*` 键、JSON 无 password 字段）；
- `RemoteBackupService` 通过 `loadResolved()` 一次性取用凭据，所有
  网络客户端 `WebDavClient.fromConfig` 消费 resolved 形态；
- 安全存储写入失败以 `RemoteBackupSecureStoreException` 面向用户，
  不回退明文；
- 备份策略（`BackupManifestPolicy`）继续结构性排除 `remoteBackup.*`
  前缀，双保险。

测试：`test/service/remote_backup/remote_backup_config_test.dart`
（迁移成功/幂等/不可用保留明文/读回不一致/无操作），
`test/views/settings/remote_backup_page_test.dart`（占位、显式保存、
编辑失效、保存后备份与恢复）。
