# 设置页“屎山”一次性清理与完整优化计划

> 状态：待执行  
> 计划类型：设置系统、备份恢复、安全、导航、诊断、无障碍的一次性收口重构  
> 编写日期：2026-08-23  
> 适用仓库：Varnamala Plus / Turna Flutter 客户端  
> 核心约束：**必须安排一次连续、长时间、不中断的实施窗口，一口气完成全部阶段、迁移、回归和收尾；不得拆成多个可发布的半成品批次。**

---

## 0. 执行方式：为什么必须一次性长时间做完

本计划不是一组可以随意拆散、分周上线的小优化，而是一条互相咬合的改造链：

```text
设置存储契约
   ↓
备份清单与恢复校验
   ↓
WebDAV 凭据迁移
   ↓
业务操作协调器
   ↓
设置导航与页面生命周期
   ↓
组件、无障碍与性能收口
   ↓
系统健康机制替换
   ↓
全量迁移测试、回归、发布验证
```

其中任何一段单独落地，都会制造危险的中间态：

- 只换备份清单、不同时换恢复器，会出现新备份无法恢复或旧备份被误判成功。
- 只删除 SharedPreferences 中的 WebDAV 密码、不同时完成安全存储迁移，会让已有用户丢失远程备份配置。
- 只拆 SettingsProvider、不同时迁移所有消费者，会出现 UI 显示值和运行时值不一致。
- 只改设置路由、不同时改外部深链和返回行为，会出现隐藏页面被提前 push、返回栈错乱或请求丢失。
- 只放开系统健康页返回、不同时建立新的告警状态机，会让真正的数据完整性风险失去阻断能力。
- 只提取组件、不同时完成 200% 字号和语义测试，只会把现有布局问题封装得更深。

因此后续执行必须遵守以下硬性规则：

1. 使用同一个连续的长任务窗口完成本计划，期间不穿插其他功能开发。
2. 可以做本地 checkpoint commit，方便故障回滚，但不得把任何中间 checkpoint 合并、发布或交付给用户。
3. 从第一处生产代码变更开始，必须一直做到完整 Definition of Done 全绿才算结束。
4. 如果遇到无法在窗口内解决的外部阻塞，必须回退到最近一个内部一致的 checkpoint；不能把半迁移状态留在主分支。
5. 计划执行期间冻结设置键、备份格式、设置页路由、系统健康策略和远程备份功能的其他并行改动。
6. 最终交付是一次完整收口：代码、旧数据迁移、旧备份兼容、测试、文档和发布检查同时完成。

### 0.1 建议实施窗口

这不是“改几个 Widget”的工作量。建议预留一个连续的专项周期，至少覆盖：

- 完整代码审计与基线冻结；
- 所有生产代码改造；
- 旧偏好和旧备份迁移验证；
- 全量单元、Widget、集成、Golden、静态检查；
- Android Release 构建与至少一台中低端真机验证；
- 最后一轮删除兼容临时代码和死代码。

执行者在开始前必须保证有足够上下文、时间和设备条件，不应在“今天先改一半、下次再补”的前提下启动。

---

## 1. 背景与总体判断

当前设置页已经完成了一轮表面重构：

- 使用 `SettingsDestination` 替代了旧整数分类索引；
- 外观与声音、无障碍已经拆成不同一级分类；
- 高级页已经变为跨功能入口；
- Official Anki 内部导入已从正式高级页移到 debug-only 区域；
- 部分 Slider 已改成松手后才提交，避免逐帧写偏好；
- 外链开始使用注册表，不再猜测生产 URL。

这些方向应保留。但当前仍存在四类根本问题：

1. **安全与数据正确性问题**：WebDAV 密码明文保存；本地课程导入提示成功但实际未应用；本地与远程备份清单已经漂移。
2. **状态与副作用问题**：设置值、系统提醒、音频、FSRS、Anki、账户重置跨多个服务执行，没有统一事务、回滚和结构化结果。
3. **导航与生命周期问题**：正式路由、页内伪路由、`AnimatedSwitcher`、`Offstage` 和全局 ChangeNotifier 深链同时存在，注释描述与真实生命周期不一致。
4. **可维护性与体验问题**：主页面和公共组件继续膨胀；大量重复 Slider/Tile；系统健康强制劫持；大字号和语义覆盖不足；测试数量看似较多但 happy path 重复明显。

本计划的目标不是继续“抛光页面”，而是把设置系统从 UI 拼装代码升级为可验证的产品基础设施。

---

## 2. 目标

完成后必须达到以下结果：

1. WebDAV 密码和其他远程凭据只存在于平台安全凭据存储，不进入 SharedPreferences、备份、日志或诊断报告。
2. 本地导出与远程备份共用唯一、带版本的备份数据契约。
3. “导入成功”必须代表数据真的完成校验和落地；课程 payload 不能再被静默忽略。
4. 损坏、过大、跨版本不兼容或越界的备份在写入任何用户状态前被拒绝。
5. 所有跨服务设置操作由应用层协调器执行，能够报告成功、部分失败、回滚和重试建议。
6. 设置首页只负责展示分类；正式分类和二级页面全部有稳定路由与可测试深链。
7. 页面滚动位置和必要的编辑状态有明确恢复策略，不再依赖 `_visited + Offstage` 假装永久挂载。
8. FSRS 优化不阻塞 UI isolate；文本输入不逐字符写磁盘；隐藏页面不继续无意义监听全局状态。
9. 系统健康不再通过“手动扣分”伪装故障恢复，也不因普通错误把用户锁死在页面。
10. 设置页自身在 100%、150%、200% 字号、窄屏、横屏、深色、高对比和屏幕阅读器下可用。
11. 版本号、更新日志、外链和设置元数据均只有一个事实来源。
12. 重复测试被合并，高风险失败路径得到真实覆盖。

---

## 3. 非目标

本次不做以下扩张：

- 不重新设计 Anki 调度算法本身。
- 不重写整个 App 的路由体系；只完成 Settings 子树和外部 Settings 深链所需改造。
- 不引入云账户体系、付费服务或新的备份服务商。
- 不以设置重构为理由重做所有页面视觉风格。
- 不把系统健康做成远程遥测平台；继续保持本地优先和脱敏。
- 不顺便大规模修改课程、复习、AI 或 Playground 业务，除非它们是设置契约的直接消费者。
- 不把所有 SharedPreferences 一次性迁移到数据库；只为原子恢复、版本化和敏感数据安全建立必要边界。

---

## 4. 必须保持的不变量

整个重构期间必须始终保护以下不变量：

### 4.1 用户数据不变量

- 不删除课程、卡片、复习历史、错题、成就、宝石、装扮或用户资料。
- 账户重置只在用户明确确认后执行，并严格匹配 UI 描述的范围。
- 旧版本地导出和旧版远程备份至少保留一个明确的兼容读取周期。
- 恢复失败不得留下半写入状态。
- 迁移失败不得删除旧 WebDAV 密码；只有安全存储写入并读回验证成功后才能清除明文。

### 4.2 设置一致性不变量

- UI 显示值、持久化值和运行时生效值必须一致。
- 系统提醒调度失败时，不能继续显示为已成功启用。
- FSRS 参数只在两个调度消费者都成功应用后标记为已优化。
- Slider 拖动时允许本地预览，但只在 `onChangeEnd` 提交持久化。
- 一个设置操作只能有一个 owner，不能由 Widget、Provider 和 Service 各写一遍。

### 4.3 安全不变量

- 密码、API Key、认证头不进入普通偏好、日志、异常文案、剪贴板默认内容或备份。
- 导诊报告只包含白名单字段；不能靠事后字符串替换碰运气脱敏。
- 外部 URL 继续限制为允许的 scheme。
- 导入文件必须有大小限制、结构校验和版本检查。

### 4.4 导航不变量

- 每个正式 Settings 页面有唯一 route name。
- 外部调用能够稳定打开指定分类或二级页面。
- 系统返回键、AppBar 返回键和手势返回语义一致。
- debug-only 页面在 release/profile 不注册可达入口。
- 返回设置首页后保留必要滚动位置，但隐藏页面不持续执行昂贵工作。

---

## 5. 目标架构

### 5.1 设置层次

```text
SettingsShell
├── SettingsLandingPage
├── AccountSettingsPage
├── LearningSettingsPage
├── AppearanceSoundSettingsPage
├── AccessibilitySettingsPage
├── DataBackupSettingsPage
├── AdvancedSettingsPage
│   ├── AiConnectionPage
│   ├── StorageDiagnosticsPage
│   ├── SystemHealthPage
│   └── LegacyCompatibilityPage
├── AboutSettingsPage
│   ├── AboutTurnaPage
│   ├── PrivacyDetailsPage
│   ├── ChangelogPage
│   └── LicensesPage
└── DeveloperSettingsPage  // debug-only
```

`SettingsLandingPage` 不再构建任何分类业务内容。每个正式页面按路由创建和销毁；滚动状态交给 PageStorage/Restoration，而不是把访问过的页面永久放进 Offstage。

### 5.2 应用层

```text
Widget
  ↓ invoke
SettingsCommand / Coordinator
  ↓
Typed Settings Repository + Domain Services
  ↓
Prefs / Secure Store / OS Reminder / DB / Files
```

Widget 不再直接组合多个 `getIt<T>()` 调用。跨服务动作必须有单一协调器，例如：

- `UpdateDailyReminderCommand`
- `ResetLearningSettingsCommand`
- `ResetAccountCommand`
- `ApplyFsrsParametersCommand`
- `ImportBackupCommand`
- `ExportBackupCommand`
- `SaveRemoteBackupConnectionCommand`
- `ClearRegenerableCachesCommand`

所有命令返回结构化结果，不使用裸字符串或空 catch：

```dart
sealed class SettingsOperationResult {
  const SettingsOperationResult();
}

final class SettingsOperationSuccess extends SettingsOperationResult {
  const SettingsOperationSuccess({this.restartRequired = false});
  final bool restartRequired;
}

final class SettingsOperationFailure extends SettingsOperationResult {
  const SettingsOperationFailure({
    required this.code,
    required this.userMessage,
    this.retryable = false,
  });
  final String code;
  final String userMessage;
  final bool retryable;
}
```

### 5.3 备份层

本地导出和远程备份共用以下概念：

```text
BackupSchemaVersion
BackupManifestPolicy
BackupSnapshotBuilder
BackupValidator
BackupRestorePlan
BackupRestoreJournal
BackupRestoreCoordinator
```

需要明确区分：

- 用户偏好；
- 学习进度；
- Drift/Anki 数据库；
- 用户导入课程；
- 媒体文件；
- 可再生成缓存；
- 设备本地配置；
- 永不进入备份的凭据和健康事件。

---

## 6. 一次性执行总顺序

下面的阶段顺序是依赖顺序，不是可拆分发布顺序。必须在同一个连续实施窗口内从 Phase 0 做到 Phase 11。

| 阶段 | 内容 | 完成标志 |
| --- | --- | --- |
| Phase 0 | 冻结基线与风险清单 | 当前行为、键、格式、测试基线可复现 |
| Phase 1 | 建立 typed settings 与共享备份契约 | 单一 manifest 和 validator 可用 |
| Phase 2 | WebDAV 凭据安全迁移 | 明文迁移、验证、清理、回退完整 |
| Phase 3 | 本地导出/远程备份/恢复收口 | 课程真实导入，恢复具备预检与回滚 |
| Phase 4 | 设置命令与事务协调器 | Widget 不再编排跨服务副作用 |
| Phase 5 | Settings 正式路由与生命周期 | 删除 `_visited/Offstage` 伪路由 |
| Phase 6 | 性能治理 | FSRS isolate、输入去抖、隐藏页不活跃 |
| Phase 7 | 公共组件拆分与无障碍 | 200% 字号、语义、横屏通过 |
| Phase 8 | 系统健康机制替换 | 无手动扣分，无普通错误强制锁页 |
| Phase 9 | IA、版本、文案和视觉一致性 | 单一事实来源，无重复入口 |
| Phase 10 | 测试体系重整 | 去重并补全失败路径、迁移和契约测试 |
| Phase 11 | 全量验证与死代码清理 | Definition of Done 全绿 |

---

## 7. Phase 0：冻结基线与准备回滚点

### 7.1 任务

1. 记录开始实施时的 Git 状态，区分用户已有改动和本计划改动。
2. 列出所有 Settings 相关 preference key、动态 prefix、数据库和文件资产。
3. 保存三类测试 fixture：
   - 当前版本默认用户；
   - 已配置 WebDAV 明文密码的旧用户；
   - 同时包含 progress/course 的旧本地导出文件。
4. 保存一份当前远程备份 fixture 和 manifest。
5. 记录当前设置导航的关键路径和返回行为。
6. 跑一次完整静态检查与设置测试，记录已知 file_picker 平台警告，不把依赖警告误算成本计划回归。
7. 建立本地 checkpoint，确保任何迁移失败都能恢复到实施前状态。

### 7.2 必须产出

- Settings key inventory。
- Backup compatibility fixture 集合。
- WebDAV legacy credential fixture。
- 基线测试记录。
- 明确的“用户已有改动不得覆盖”清单。

### 7.3 禁止事项

- 未完成 fixture 和 key inventory 前不得开始删除旧字段。
- 不得直接修改或清空真实用户数据来测试迁移。
- 不得把当前工作区其他未提交变更纳入清理范围。

---

## 8. Phase 1：建立 typed settings 与唯一备份契约

### 8.1 设置数据分域

把当前大而杂的 `SettingsProvider` 拆成明确领域，建议至少包括：

- `FeedbackSettings`：音效、触觉、TTS 速度。
- `ReminderSettings`：每日提醒开关和时间。
- `LearningStrategySettings`：FSRS retention、优化元数据。
- `LegacyCompatibilitySettings`：Anki 预渲染、捕获延迟、Lite 阈值、禁用 JS。
- `CourseAudioSettings`：按 course scope 的自动朗读和母语 fallback。
- `DisplaySettings`：自动旋转。
- `AccessibilitySettings`：字号、减少动态、高对比、易读字体、感官减负、专注模式。

不要求一定创建七个 ChangeNotifier。重点是数据模型和 owner 分开；UI 可以通过聚合 facade 读取，但写操作必须进入明确 repository/command。

### 8.2 为每个设置声明完整元数据

每个设置必须定义：

- key 或 prefix；
- 数据类型；
- 默认值；
- 合法范围；
- 是否备份；
- 是否跨设备；
- 是否设备本地；
- 是否敏感；
- 是否需要运行时副作用；
- 是否需要重启；
- 旧 key 和迁移策略。

例如：

| 设置 | 范围 | 备份 | 运行时副作用 |
| --- | --- | --- | --- |
| TTS speed | 0.5–2.0 | 是 | 更新 AudioController |
| Reminder hour | 0–23 | 是 | 重排系统通知 |
| Reminder minute | 0–59 | 是 | 重排系统通知 |
| Text scale | 100–200 | 是 | 重建根 MediaQuery |
| WebDAV password | 非空凭据 | 否 | 安全存储 |
| System health event | 内部状态 | 否 | 无跨设备恢复 |

### 8.3 单一备份策略

删除本地 `_progressManifest` 与远程 `exactKeys/includePrefixes` 的重复事实来源，改为同一策略对象。

策略至少要覆盖当前已遗漏的：

- `srsDesiredRetention`；
- FSRS parameters、optimizedAt、reviewCount；
- Anki daily new/review limit；
- Anki daily challenge inclusion；
- Anki legacy compatibility 设置；
- course scope/order；
- `settings.autoReadOnTap.*`；
- `settings.nativeLang.*`；
- AI 非敏感配置；
- 明确排除 API Key、WebDAV password、remote device id、system health event、临时计数和缓存。

### 8.4 统一 schema

定义带版本的备份 envelope：

```json
{
  "meta": {
    "schemaVersion": 2,
    "appId": "...",
    "appVersion": "...",
    "createdAtUtc": "...",
    "contents": ["settings", "progress", "course", "media"]
  },
  "settings": {},
  "progress": {},
  "course": {},
  "integrity": {}
}
```

必须支持：

- v1 旧本地导出的只读兼容解析；
- 当前远程备份格式的只读兼容解析；
- v2 统一写出；
- 未知未来版本拒绝写入，并显示可理解的升级提示。

### 8.5 验收

- 任意一个 setting key 的备份归属只能在一个地方声明。
- 本地和远程备份对同一 prefs snapshot 产生相同的设置集合。
- 动态 prefix 设置能够 round-trip。
- 敏感字段在序列化层即被排除，而不是导出后再字符串清洗。

---

## 9. Phase 2：WebDAV 凭据安全迁移

### 9.1 新模型

把当前 `RemoteBackupConfig` 拆成：

- `RemoteBackupEndpointConfig`：server URL、username、remote root、include media；可以进入普通偏好。
- `RemoteBackupCredential`：password/token；只进入 `SecureCredentialStore`。
- `RemoteBackupResolvedConfig`：运行时临时组合，不序列化、不日志输出。

### 9.2 迁移流程

对已有明文配置执行幂等迁移：

1. 读取旧 `remoteBackupConfig`。
2. 如果旧 JSON 含 password，写入安全存储专用 key。
3. 从安全存储读回并使用常量时间或安全等价方式确认写入成功。
4. 写入不含 password 的新 endpoint config。
5. 写入迁移完成 marker。
6. 再次读取普通偏好，确认不存在 password 字段。
7. 只有以上全部成功，才视为迁移成功。
8. 任一步失败时保留旧配置并记录脱敏迁移状态，下次启动重试。

### 9.3 设置页面行为

- 页面初始化时分别加载 endpoint 和 credential presence，不把真实密码回填为可读取文本。
- 已保存密码显示占位状态，例如“已保存凭据”；用户输入新密码才替换。
- 编辑 URL、用户名或密码后，立即清除旧的连接测试成功状态。
- 改为“保存并测试”或显式“保存”，禁止 controller listener 每字符持久化。
- 保存期间按钮 disabled，并提供明确 loading。
- 页面销毁时清理密码 controller 内容。

### 9.4 安全测试

必须自动扫描以下内容，确认不含测试密码：

- SharedPreferences 所有值；
- 本地导出文件；
- 远程 backup core archive；
- backup manifest；
- 系统健康报告；
- LogCapture；
- 异常和 SnackBar 文案。

### 9.5 验收

- 新安装永不把 WebDAV 密码写进普通偏好。
- 老用户无感迁移，迁移后仍能测试连接和备份。
- 安全存储不可用时显示可恢复错误，不悄悄退回明文存储。
- 重复执行迁移不修改已正确迁移的数据。

---

## 10. Phase 3：本地导出、课程导入和远程恢复收口

### 10.1 导入前预检

导入流程改成：

```text
选择文件
  ↓
大小限制
  ↓
后台 isolate 解析 JSON/校验哈希
  ↓
schema 与 appId 校验
  ↓
字段类型与范围校验
  ↓
生成 RestorePlan 预览
  ↓
用户确认影响范围
  ↓
staging + journal
  ↓
提交
  ↓
重载运行时状态
  ↓
结构化成功报告
```

必须在写入前验证：

- 文件大小上限；
- JSON 根类型；
- appId；
- schemaVersion；
- contents 与实际 payload 一致；
- 所有设置类型和范围；
- course payload 的结构、路径和文件名安全；
- 不允许 `../`、绝对路径或覆盖工作目录之外的位置；
- 可选哈希/长度与实际内容一致。

### 10.2 课程 payload 必须真实落地

当前“发现 course 字段但不应用”的行为必须删除。实施时先明确课程 payload 语义：

- 如果它代表内置课程资产副本，则不应作为用户可恢复课程，应该移除该导出选项。
- 如果它代表用户导入课程，则必须写入课程 staging、校验 schema，走统一课程导入/所有权流程后提交。

最终 UI 只能出现以下真实结果之一：

- 课程已导入并可立即读取；
- 课程已安全 staged，明确说明为何必须重启，以及启动时将执行什么；
- 课程不受支持，导入前阻止并解释；
- 导入失败且没有写入任何课程数据。

禁止继续使用“只检查 Map 是否存在就提示成功”的逻辑。

### 10.3 原子性与回滚

SharedPreferences 本身不是事务数据库，因此需要应用级恢复 journal：

1. 在提交前保存受影响 key 的 before image。
2. 写入 `restore.inProgress` marker 和 restore id。
3. 按领域提交设置、进度、数据库和文件。
4. 任一步失败，按 before image 和 staging 回滚。
5. 全部成功后删除 marker 和临时文件。
6. App 启动时发现未完成 marker，自动执行恢复或回滚，不允许带半状态继续运行。

数据库修改必须使用数据库事务；文件/课程采用 staging directory 后再切换，不直接覆盖正式目录。

### 10.4 恢复后的运行时重载

建立统一 `PostRestoreReloadRegistry`，按确定顺序刷新：

- Settings repositories/providers；
- Theme/Accessibility；
- Language；
- AudioController；
- LocalReminderService；
- Game、Streak、Gems、Cosmetics、Achievements；
- SRS、Grammar、Mistakes；
- Course scope/index；
- AI 非敏感配置。

不再只刷新 AchievementService，然后让其他状态等待重启。

### 10.5 用户反馈

- 非 JSON 扩展要说明“不支持该文件”，不能静默 return。
- 不向用户展示裸异常、文件绝对路径或内部堆栈。
- 错误映射为稳定 error code 和本地化消息。
- 成功结果按 settings/progress/course/media 分项展示。
- 只有确实需要重启时才显示重启提示。

### 10.6 验收

- progress-only、course-only、混合备份都能真实 round-trip。
- 导入中途模拟每一个失败点，最终状态都等于导入前。
- 旧 v1 文件可读取，未知 v3 文件被安全拒绝。
- 超范围字号、TTS 速度、提醒时间不能进入正式状态。
- 导入完成后 UI 与运行时状态一致。

---

## 11. Phase 4：跨服务设置操作事务化

### 11.1 每日提醒

`UpdateDailyReminderCommand` 负责：

1. 验证时间范围和平台支持。
2. 保存旧偏好和旧调度状态。
3. 尝试应用系统提醒。
4. 成功后提交设置状态并通知 UI。
5. 失败则恢复旧状态，并返回用户可理解错误。

如果平台 API 无法提供旧调度快照，至少要保证偏好值只在调度成功后标记为成功，并提供明确重试。

### 11.2 学习默认值重置

`ResetLearningSettingsCommand` 统一重置：

- TTS 速度；
- 每日提醒及 OS 调度；
- FSRS retention；
- Anki 每日新卡/复习上限；
- Anki daily challenge inclusion。

命令必须声明“不重置”的内容，并把该清单直接用于确认文案测试，防止文案和实现漂移。

### 11.3 FSRS 参数

`ApplyFsrsParametersCommand` 必须满足：

- 参数长度和范围先验证；
- SRS 和 Grammar 两个消费者都成功后才写 optimized metadata；
- 任一消费者失败时恢复旧参数；
- 不允许 `catch (_) {}` 后继续标记成功；
- 清除自定义参数走同一事务路径。

### 11.4 账户重置

`ResetAccountCommand` 明确列出 reset scope，并执行：

- before-state/journal；
- 防重复执行锁；
- 有序清理；
- 幂等步骤；
- 失败回滚或进入可恢复 pending 状态；
- 完整结果报告。

UI 必须在执行期间禁用返回、重复点击和其他冲突操作，但要提供进度和失败恢复，不能无限 loading。

### 11.5 简单 Toggle 的统一语义

简单偏好采用一致策略：

- UI optimistic update；
- 立即通知；
- 后台持久化；
- 失败时回滚并显示一次错误；
- 同一个 key 的写入串行化，最后一次用户意图获胜。

所有 Settings Toggle callback 使用 `Future<void>` 或 command result，不再丢弃 Future。

### 11.6 验收

- 每个跨服务操作只有一个协调入口。
- Widget 中不再出现连续多个 `getIt<T>()` 完成业务事务。
- 所有失败都有明确处理，不存在空 catch。
- 重复点击不会启动两个重置、导入、导出或优化任务。

---

## 12. Phase 5：Settings 正式路由与生命周期

### 12.1 删除当前伪路由状态

从 `SettingsPage` 删除：

- `_destination` 作为正式页面身份；
- `_advancedAnchor` 作为二级页面身份；
- `_visited`；
- `_learningSectionEpoch`；
- `_buildSubPage` 的 Offstage Stack；
- 依赖 AnimatedSwitcher 保存页面 State 的错误注释和逻辑。

允许 landing 页面自身使用小范围动画，但页面身份必须由 router 表示。

### 12.2 正式路由

每个分类和二级页创建 route。至少支持：

- `/settings`
- `/settings/account`
- `/settings/learning`
- `/settings/appearance-sound`
- `/settings/accessibility`
- `/settings/data-backup`
- `/settings/advanced`
- `/settings/advanced/ai`
- `/settings/advanced/storage`
- `/settings/advanced/health`
- `/settings/advanced/legacy`
- `/settings/about`

实际是否暴露 URL 取决于 AutoRoute 配置，但 route identity 必须稳定且可测试。

### 12.3 外部深链

保留统一 `openSettings` API，但实现改为：

1. 先确认 Settings tab 已切换并且 router ready。
2. 再导航到目标 route。
3. 相同请求可重复打开。
4. 页面未挂载时请求不能丢失。
5. DI 未注册不能创建无效 ephemeral controller；应 fail fast 或使用明确 fallback route service。
6. 删除未使用的 `BuildContext` 参数，或真正使用它完成局部 router 导航。

### 12.4 状态恢复

- Landing scroll 使用 `PageStorageKey`。
- 分类页面 scroll 使用稳定 route/page key。
- Slider 未提交拖动值离开页面时丢弃，已提交值从 repository 恢复。
- 表单草稿是否保留要逐页明确；敏感密码草稿不得跨页面长期驻留。
- App 重启后的恢复只恢复安全、稳定的导航状态，不自动重新打开破坏性确认框。

### 12.5 Home AppBar 收口

重新检查零高度 `SettingsAppBar` stub。目标二选一：

- Settings shell 明确拥有 AppBar，Home shell 对该 tab 不再保留伪占位；或
- Home shell 统一拥有 tab AppBar，Settings 子路由通过 route-aware title/back action 接入。

最终不能继续依赖“零高度组件维持数组索引”的隐式布局技巧而没有契约测试。

### 12.6 debug-only 页面

- Developer Settings 在 release/profile 不显示入口。
- 更进一步检查路由注册；如果 release 中无业务需求，应不注册可直接深链的 developer route。
- Official Anki 内部导入只接受测试文件或内部诊断入口，不能与统一生产导入竞争。

### 12.7 验收

- 所有页面返回行为一致。
- 外部深链在冷启动、Settings 未访问、Settings 已访问和重复请求场景都通过。
- 隐藏页面不继续 watch Provider 或执行诊断。
- 页面滚动状态按声明恢复，不依赖永久挂载。

---

## 13. Phase 6：性能治理

### 13.1 FSRS 优化移出 UI isolate

- DAO 读取在主 isolate 完成异步 IO。
- 转换为可序列化、最小化的优化样本。
- 使用 `Isolate.run` 或 `compute` 执行 CPU 计算。
- 支持取消/忽略过期结果。
- 记录读取、转换、优化、应用四段耗时。
- 大历史数据不得因为复制完整复杂对象造成更严重内存尖峰。

### 13.2 移除隐藏页面常驻成本

正式路由完成后，未显示的 Settings 页面不构建、不 watch、不保留 TTS diagnostics 或大列表。

只对确实昂贵且可安全复用的数据做 repository cache，不通过 Widget 永久挂载缓存。

### 13.3 输入与写入

- WebDAV URL/username 使用显式保存或 300–500ms debounce。
- 密码只在提交时进入安全存储。
- 所有 Slider 统一为 drag-local、end-commit。
- Language 设置只通知一次；持久化失败必须被捕获，不能 `unawaited` 后产生未处理异常。
- 同 key 写入串行化或使用 last-write-wins queue。

### 13.4 列表构建

- Landing 项目数量少，可保持普通 ListView。
- 较长的诊断、日志、存储 artifact 页面使用 lazy list/sliver。
- 不在 `SingleChildScrollView + Column` 中一次构建潜在无限增长的数据。

### 13.5 扫描与缓存清理

- Storage scan、cache registry、Anki cache maintenance 由一个 coordinator 统一展示进度和结果。
- 明确每个 cache owner，禁止重复清理或漏清。
- 清理期间防重复点击。
- 部分 cache 清理失败时显示分项结果，不把整体谎报成功。

### 13.6 性能验收

- FSRS 优化期间动画和返回操作保持响应。
- Remote Backup 表单输入不产生逐字符磁盘写入。
- Settings 页面切换无不必要的隐藏页 rebuild。
- Android 中低端设备 Profile 模式记录页面打开、滚动和返回帧时间。

---

## 14. Phase 7：公共组件拆分与无障碍收口

### 14.1 拆分 `settings_common.dart`

建议拆为：

```text
settings/widgets/primitives/
├── settings_card.dart
├── settings_tile.dart
├── settings_section_title.dart
└── settings_divider.dart

settings/widgets/controls/
├── settings_switch_tile.dart
├── settings_slider_tile.dart
├── settings_dropdown.dart
└── settings_form_row.dart

settings/widgets/feedback/
├── settings_info_card.dart
├── settings_status_pill.dart
├── settings_empty_card.dart
└── settings_dialogs.dart

settings/widgets/diagnostics/
├── settings_key_value_tile.dart
└── settings_segmented_bar.dart
```

不要为了文件数量机械拆分；边界以依赖和用途为准。

### 14.2 统一 Slider

提取通用 Slider primitive，覆盖：

- icon；
- title/subtitle；
- 当前值 formatter；
- min/max/divisions；
- persisted value；
- preview callback；
- async commit；
- busy/error；
- Semantics value/increasedValue/decreasedValue。

迁移：

- TTS speed；
- FSRS retention；
- Account goals；
- Anki daily limits；
- Text scale；
- Capture delay；
- Lite threshold。

### 14.3 统一 Toggle

删除 SettingsProvider 专用、AccessibilityProvider 专用和 generic 三套相似 Tile。保留一个纯展示控制组件，由外层 Selector/Controller 传入 value 和 async callback。

行为要求：

- 整行可点击；
- Switch 和整行合并为一个语义节点；
- disabled 时图标、文字、箭头和开关均有一致视觉；
- busy 时阻止重复操作；
- 不把 `enabled && value` 当作真实值，disabled 仍应正确表达当前状态。

### 14.4 大字号和响应式布局

必须整改：

- About 三列 highlight 在窄屏/大字号下改 Wrap 或单列。
- Brand header 删除固定 81 高度和强制单行 tagline。
- Export bottom sheet 增加 `SafeArea + SingleChildScrollView/DraggableScrollableSheet`。
- Dialog 内容在大字号、横屏和键盘出现时可滚动。
- trailing 过宽时允许换行或移到下一行。
- 状态 Pill、Dropdown、长版本号不能撑破 Row。

### 14.5 无障碍能力

- 文字缩放：100%、150%、200%。
- 减少动态：Settings 路由动画、AnimatedSwitcher、装扮预览遵守。
- 高对比：disabled、warning、success 不只依赖透明度或颜色。
- 易读字体：固定字号组件同步使用主题文本样式。
- 感官减负：设置预览音效和触觉也遵守 quiet feedback。
- 专注模式：不隐藏必要的备份、安全和错误信息。

### 14.6 验收

- 所有设置控制可通过 TalkBack/VoiceOver 理解和操作。
- 200% 字号无 RenderFlex overflow。
- 横屏 Export、Remote Backup、About、Advanced 页面可完整滚动。
- disabled 控件不会表现得像可点击链接。

---

## 15. Phase 8：系统健康机制替换

### 15.1 删除错误机制

必须删除：

- “确定（-40分）”；
- `confirmAndDeductScore` 作为故障处理手段；
- 普通 attention/error 导致强制留在页面；
- 点击确认即把故障标记 resolved；
- 需要反复点击才能离开的交互。

### 15.2 新状态模型

分离以下概念：

- `detected`：检测到问题；
- `acknowledged`：用户已经看过；
- `mitigationEnabled`：是否启用安全模式；
- `checkPassed`：对应自检是否已通过；
- `resolved`：系统证据表明问题已经解除；
- `expired`：长时间未复现且策略允许自动过期。

分数可以继续作为排序或严重度聚合依据，但不能由按钮直接扣除。

### 15.3 告警策略

| 级别 | 行为 |
| --- | --- |
| Info | 仅记录，不打扰用户 |
| Attention | 非阻断 banner/badge，可进入诊断页 |
| Critical recoverable | 强提醒，提供安全模式、重试、自检和导出报告，但允许安全退出 |
| Data-integrity blocking | 只有明确继续操作可能扩大数据损坏时才阻断，并必须提供备份、退出或只读模式 |

### 15.4 解决机制

- 数据库问题：运行 integrity check，通过后 resolved。
- TTS/音频问题：重新诊断，通过后 resolved。
- AI 网络问题：连接测试通过或用户关闭 AI 功能后 resolved/mitigated。
- WebView/Anki 渲染：安全模式或兼容模式应用后标为 mitigated；成功渲染后 resolved。
- 一般重复日志：在时间窗口内不再出现后自动降级，而不是用户手动扣分。

### 15.5 全局导航

- App shell 不再对普通累计 error 自动 push SystemHealthRoute。
- Critical 使用一次性 modal/banner，避免 route push storm。
- 已在健康页时不重复 push。
- 真正 blocking 的数据完整性事件使用专门 guard，不复用通用日志分数。

### 15.6 验收

- 用户不会因普通日志错误被锁在系统健康页。
- “已确认”不会改变底层故障事实。
- 每种问题有可解释的检测、缓解、复检、解决路径。
- 清空日志不会自动变正常；自检通过才改变 resolved。

---

## 16. Phase 9：信息架构、版本、文案和视觉一致性

### 16.1 Destination descriptor

把 destination 的 title、subtitle、icon、group、route 统一到 descriptor/extension，删除主页面中的多组平行 switch。

要求：

- enum identity 与展示顺序分离；
- metadata 编译期穷尽；
- debug-only 条件集中；
- 测试能够遍历所有正式 destination。

### 16.2 About 与 Changelog

当前设置列表已有“更新日志”，About 内部又有更新日志 Tab。二选一：

- About 保留两 Tab，设置列表删除单独 Changelog；或
- About 只保留关于信息，Changelog 保持独立入口。

推荐第一种，减少一级入口数量，同时支持 About 页内跳到更新日志 Tab 的 typed route argument。

### 16.3 版本唯一事实来源

- 所有版本展示使用 `AppBuildInfo`。
- 删除 `0.7.0` 等 fallback。
- PackageInfo 读取失败显示“未知版本”，不能显示看似真实的错误版本。
- ReleaseManifest 只描述内容版本，不充当安装包版本来源。

### 16.4 外链

- 继续使用 ExternalLinkRegistry。
- 正式 URL 未配置时保持 disabled + 原因。
- label 进入统一字符串资源。
- 链接失败提供复制地址，但复制动作也要有成功反馈。
- 测试 configured、unconfigured、invalid scheme、launch false、throw 五种状态。

### 16.5 文案与错误

- 清理散落的硬编码中文和中英实现术语。
- `Strict JSON`、Lite threshold 等兼容设置要用用户可理解说明，同时可在次级说明保留技术名。
- 禁止直接展示 `$e`。
- 所有危险操作明确“会删除什么、不会删除什么、能否恢复”。
- 所有成功文案必须对应真实完成的动作。

### 16.6 Scaffold 与视觉

- 正式 Settings 子页统一 AppBar、背景、边距、返回行为。
- About 可以保留品牌视觉，但导航和系统栏行为必须一致。
- Privacy、Changelog、Transparency 不再各自复制略有不同的 Scaffold 样式。

---

## 17. Phase 10：测试体系重整

### 17.1 删除重复测试

合并目前重复的：

- `settings_provider_test.dart` 中的 per-course 测试；
- `settings_per_course_test.dart`；
- `settings_reminder_test.dart` 与 provider test 的重叠部分。

按职责重组为：

- repository/codec 单元测试；
- command/coordinator 事务测试；
- backup schema/round-trip 测试；
- migration 测试；
- 页面 Widget/语义测试；
- 路由与深链测试；
- Golden/响应式测试。

### 17.2 必须新增的单元测试

1. 所有设置默认值和范围 normalization。
2. 旧 key 到新 typed settings 的幂等迁移。
3. WebDAV 明文到 secure store 的成功、失败、重试和重复迁移。
4. 本地/远程共用 manifest 的等价性。
5. 敏感字段永不序列化。
6. v1 → v2 backup migration。
7. 未知未来 schema 拒绝。
8. 超范围、错误类型、缺字段、超大文件拒绝。
9. 恢复各步骤失败后的完整回滚。
10. Reminder schedule 失败时设置状态一致。
11. FSRS 第二消费者失败时不标记成功。
12. Account reset 防重复与中途失败恢复。
13. System health acknowledge/mitigate/resolve 状态分离。

### 17.3 必须新增的 Widget 测试

1. 每个正式 Settings route 可直接打开。
2. 外部 deep-link 冷/热状态和重复请求。
3. 系统返回、AppBar 返回、手势返回一致。
4. 页面滚动恢复。
5. Toggle 整行点击、busy、失败回滚。
6. Disabled action 的视觉和 Semantics。
7. Import preview 与实际 result 一致。
8. Remote Backup 编辑后测试结果失效。
9. 账户重置期间重复点击无效。
10. System health 普通告警可以退出。

### 17.4 无障碍与 Golden 矩阵

至少覆盖：

| 页面 | Light/Dark | 100% | 150% | 200% | 窄屏 | 横屏 | Semantics |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Landing | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Learning | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Accessibility | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Data/Backup | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Remote Backup | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Advanced | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| About | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| System Health | 是 | 是 | 是 | 是 | 是 | 是 | 是 |

不要求每个组合都生成 Golden，但每个高风险布局至少有一种自动 overflow 检查和语义断言。

### 17.5 集成测试

- 真实文件导出 → 清空测试状态 → 导入 → 状态等价。
- 包含课程的导出导入。
- 旧格式 fixture 恢复。
- WebDAV 使用 fake server 完成保存凭据、测试连接、备份、恢复 staging。
- 恢复后主题、字号、语言、提醒、SRS、装扮等运行时同步。
- 模拟 App 在 restore journal 中途退出，再启动恢复。

---

## 18. Phase 11：全量验证与死代码清理

### 18.1 删除项

完成迁移后检查并删除：

- 本地独立 `_progressManifest`；
- Remote Backup 重复 exact key 清单；
- `RemoteBackupConfig.password` JSON 字段；
- Remote Backup controller 的逐字符 `_commit`；
- Settings `_visited`、Offstage 子页和 epoch 强制重建；
- ephemeral SettingsNavController fallback；
- `Future(() => FsrsLiteOptimizer...)`；
- System Health 手动扣分 API 和文案；
- Settings hardcoded version fallback；
- 重复 Changelog 入口；
- 重复 Toggle/Slider 实现；
- 空 catch；
- 裸异常 SnackBar；
- 无引用的旧测试 helper、旧 route 和过期注释。

### 18.2 静态与自动化验证

至少执行：

```bash
dart format <本计划涉及的 Dart 文件>
flutter analyze
flutter test --exclude-tags golden --reporter compact
flutter test --tags golden --reporter compact
flutter build apk --release
```

如项目 Golden 标签策略不同，按仓库实际命令调整，但不得跳过 Golden 验证。

### 18.3 真机检查

Android 中低端设备至少检查：

- Settings 首开；
- 连续进入/返回所有分类；
- 200% 字号；
- 横屏和自动旋转；
- FSRS 优化期间滚动和返回；
- 导出大数据；
- 导入旧备份和新备份；
- WebDAV 输入、保存、测试和备份；
- 系统健康 attention/critical 行为；
- TalkBack 读取 Toggle、Slider、disabled item。

桌面端至少验证功能不回退和无明显布局溢出。

### 18.4 文档更新

- 更新设置架构说明。
- 更新备份 schema 与兼容策略。
- 记录 WebDAV 凭据迁移 ADR。
- 记录系统健康状态机 ADR。
- 更新发布说明，明确备份格式升级但兼容旧格式。
- 删除现有计划中已经不再成立的描述，例如“Offstage 永久保留页面”。

---

## 19. 文件级改造地图

以下是预期重点文件，不要求机械照搬命名，但职责必须实现：

### 19.1 需要重构

- `lib/views/settings/settings_page.dart`
  - 缩减为 Settings shell/landing。
  - 删除业务操作、导入导出 sheet、伪路由状态。
- `lib/application/settings_provider.dart`
  - 拆除跨领域业务和 service locator。
  - 保留兼容 facade 时必须标记退场路径。
- `lib/views/settings/widgets/settings_common.dart`
  - 按 primitives/controls/feedback/diagnostics 拆分。
- `lib/views/settings/widgets/settings_learning_section.dart`
  - Slider 复用、FSRS isolate、command 化。
- `lib/views/settings/widgets/settings_account_section.dart`
  - 账户重置 command 化。
- `lib/views/settings/widgets/settings_advanced_section.dart`
  - Legacy route 化，AI tunables typed 化。
- `lib/views/settings/remote_backup_page.dart`
  - secure credential、显式保存、状态失效、错误映射。
- `lib/views/settings/system_health_page.dart`
  - 删除扣分和强制锁页交互。
- `lib/views/settings/about_turna_page.dart`
  - 响应式、大字号、Changelog IA 收口。
- `lib/application/settings/settings_destination.dart`
  - descriptor/route mapping，删除 ephemeral request 风险。
- `lib/service/export_service.dart`
  - 改为共享 backup pipeline，不再独立维护 manifest。
- `lib/service/remote_backup/backup_snapshot_service.dart`
  - 消费共享 schema/policy。
- `lib/service/remote_backup/remote_backup_config.dart`
  - 从普通配置移除 password。
- `lib/application/system_health_monitor.dart`
  - 新告警状态机与真实 resolve 策略。

### 19.2 建议新增

- `lib/application/settings/models/`
- `lib/application/settings/settings_repository.dart`
- `lib/application/settings/settings_write_queue.dart`
- `lib/application/settings/commands/`
- `lib/application/backup/backup_schema.dart`
- `lib/application/backup/backup_manifest_policy.dart`
- `lib/application/backup/backup_validator.dart`
- `lib/application/backup/backup_restore_plan.dart`
- `lib/application/backup/backup_restore_journal.dart`
- `lib/application/backup/backup_restore_coordinator.dart`
- `lib/application/restore/post_restore_reload_registry.dart`
- `lib/application/diagnostics/system_health_policy.dart`
- 独立 Settings route pages 和拆分后的 Widget primitives。

### 19.3 需要重新生成或更新

- AutoRoute 生成文件。
- DI 生成文件。
- Golden 图片。
- 备份 fixture。
- 相关测试基线文档。

---

## 20. 风险与回滚策略

| 风险 | 防护 |
| --- | --- |
| WebDAV 迁移失败导致凭据丢失 | 安全存储读回验证成功后才删明文；迁移幂等 |
| 新备份格式破坏旧文件 | v1 只读兼容 parser + fixture 测试 |
| 恢复中途失败造成半状态 | restore journal + before image + DB transaction + staging |
| Provider 拆分导致运行时不同步 | PostRestoreReloadRegistry + consumer inventory |
| 路由重构导致 deep-link 丢失 | 冷/热/重复请求集成测试 |
| FSRS isolate 数据不可发送 | 提前构建最小可序列化 DTO，并保留同步测试实现 |
| 大字号改造引入视觉回退 | Golden + overflow test + 真机 TalkBack |
| 系统健康放宽后漏掉真正危险事件 | 独立 data-integrity blocking policy，不依赖日志累计分 |
| 一次性改动范围大 | 内部 checkpoint、阶段级测试，但不发布中间态 |

### 20.1 回滚原则

- 代码回滚不能删除已经安全迁移的凭据；新旧读取逻辑要允许一个兼容期。
- 已写出的 v2 备份应保持可解析文档，即使 App 回滚到旧版无法读取，也必须给出版本不兼容提示，不能误导为损坏文件。
- restore journal 必须可由当前版本安全恢复；不得依赖只存在于临时开发代码中的内存状态。
- 如果最终验证失败，应整体回到实施前稳定 checkpoint，不得挑选性保留半套路由或半套 schema。

---

## 21. Definition of Done

只有以下条件全部满足，才允许宣布本次一次性清理完成：

### 安全

- [ ] WebDAV 密码不再出现在 SharedPreferences。
- [ ] API Key/WebDAV password 不出现在本地或远程备份。
- [ ] 旧明文凭据迁移成功、可重试、幂等。
- [ ] 日志和诊断报告通过敏感字段自动化扫描。

### 备份与恢复

- [ ] 本地与远程使用唯一 manifest policy。
- [ ] v1 旧备份兼容读取。
- [ ] course-only、progress-only、mixed round-trip 通过。
- [ ] 课程导入真实落地，不再虚假提示成功。
- [ ] 非法、超范围、超大和未知 schema 文件在写入前被拒绝。
- [ ] 任意步骤失败后状态与导入前一致。
- [ ] 恢复后所有运行时 Provider/Service 已同步。

### 设置行为

- [ ] Reminder 偏好与系统调度一致。
- [ ] FSRS 两个消费者成功后才标记成功。
- [ ] Account/Learning reset 防重复并支持失败恢复。
- [ ] 所有 async Toggle 失败可见、可回滚。
- [ ] 不存在业务层空 catch。

### 导航与生命周期

- [ ] 正式分类全部 route 化。
- [ ] 删除 `_visited + Offstage` 伪保活。
- [ ] deep-link 冷/热/重复请求通过。
- [ ] 返回行为和滚动恢复通过。
- [ ] release/profile 无 developer 可达入口。

### 性能

- [ ] FSRS 优化运行在后台 isolate。
- [ ] WebDAV 输入不逐字符写持久化。
- [ ] 隐藏 Settings 页面不持续 watch/build。
- [ ] 中低端 Android Profile 验证无明显新增卡顿。

### 无障碍与 UI

- [ ] 200% 字号无 overflow。
- [ ] 横屏页面可完整访问。
- [ ] Toggle 整行可点击且语义合并。
- [ ] disabled/busy/error 状态可感知。
- [ ] About、Export、Remote Backup、System Health 通过响应式检查。
- [ ] 版本、更新日志和外链只有一个事实来源。

### 系统健康

- [ ] 删除手动扣分交互。
- [ ] 普通错误不再强制锁页。
- [ ] acknowledged、mitigated、resolved 明确分离。
- [ ] 真正数据完整性风险仍有独立安全阻断和恢复路径。

### 工程质量

- [ ] 重复 Settings 测试已合并。
- [ ] 新增迁移、失败、回滚、契约和无障碍测试。
- [ ] `flutter analyze` 通过。
- [ ] 非 Golden 全量测试通过。
- [ ] Golden 测试通过并人工检查。
- [ ] Android Release 构建成功。
- [ ] 无死代码、旧 manifest、旧密码字段、过期注释和虚假成功文案。

---

## 22. 最终交付说明

本计划必须作为一个完整专项一次性执行。阶段可以用于控制实施顺序和建立内部 checkpoint，但不能被解释为“先交付 Phase 1，过几天再做 Phase 2”。

最终允许合并的状态只有一个：

> 安全迁移完成、备份恢复契约统一、课程导入真实生效、设置副作用一致、正式路由完成、性能与无障碍通过、系统健康机制替换、全量测试和 Release 构建全部成功。

除此之外的任何状态都属于不允许发布的中间态。
