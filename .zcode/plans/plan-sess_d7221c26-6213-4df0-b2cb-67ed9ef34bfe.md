## 0.7.1 Changelog 写入计划

基于分支 `spike/official-anki-core-android` 上 2026-08-23 ~ 08-24 的 5 个提交（`8b1e553`、`9e31613`、`7816bd4`、`98d9bf6`、`86f74ba`），为版本 0.7.1 编写 changelog，同时修正 assets/changelog.md 中过时的 0.7 条目，并 bump 版本号。

### 0.7.1 内容（来自近 5 个提交）

**标题**：`0.7.1 — 数据治理、AI 安全与体验打磨 (2026-08-24)`

**Added**
- AI 服务商预设刷新为 DeepSeek / Kimi / Qwen / MiMo，新增深度思考开关（推理字段默认关闭，用户显式开启）
- `CardRecognitionPipeline` 取代 `anki_notetype_ai`：签名版本化、去隐私样本特征、持久化规则与 AI 结果形状校验
- `StorageInventoryService` 只读扫描与存储诊断页，支持分类 / 孤儿检测及可再生缓存清理
- 宝石入账幂等账本（`earnGems`），成就解锁按幂等键入账避免重复发放
- `StreamDeltaCoalescer` 合并 AI 流式响应，降低 UI 重建开销
- `SettingsDestination` 描述符集中管理设置页标题 / 图标等元数据
- `CacheDiagnosticsRegistry` 支持按所有者隔离执行缓存清理并保留各自结果
- 牌组组装 section beta 语义分组（默认关闭，仅影响新导入）
- Accessibility / Language / Settings Provider 新增 reload 方法，备份恢复后无需重启即可刷新状态

**Changed**
- AI API Key 迁移至平台安全存储（Keychain / Keystore），不再写入明文偏好
- AI 讲解 / 提示 / 陪练三个 Provider 收敛到 `AiStreamingSessionBase`，统一流式取消、代际与增量应用
- 移除 AI 磁盘缓存镜像（io / web 实现），仅保留内存 LRU
- 成就连续天数改用真实学习 streak，保护券补签日不计入成就阈值
- `SystemHealthMonitor` 重构为状态机模型，分离 detected / acknowledged / mitigation / checkPassed / resolved
- 存储诊断页面重构为面向用户的"存储与性能"仪表板（使用率环图 + 分类卡片）
- 卸载 / 删除以 `legacy_anki_migrations` 判定归属，清理失败标记 `pending_cleanup` 并启动时自动重试
- 去重权威切换为持久化 inventory，删除导入时同步失效编排器进程内缓存
- 统一版本编号至 0.x 序列，移除 quick_start.md，以 ReleaseManifest 作为版本单一事实来源

**Fixed**
- FSRS 热重载 swallow-all catch 改为 `isRegistered` 守卫
- 移除 ai_api_config_page 多余 `_disposed` 标志，修复生命周期处理

### 改动文件清单

**1. `assets/changelog.md`**（应用内置更新日志）
- 在 `## 0.7` 条目上方新增 `## 0.7.1 — 数据治理、AI 安全与体验打磨 (2026-08-24)`，使用项目符号列出上述内容（精简为用户向描述）
- 修正 `## 0.7` 条目：标题改为 `Anki 官方 Core 整合与课程/复习大一统`，内容替换为 release_manifest.dart 中 0.7 的 14 条 items（官方 rslib FFI 整合、课程复习大一统、worker isolate 导入、deleteNotes、WebDAV 备份、个人页精简、成就重构、路由统一等），使其与 release_manifest 对齐

**2. `lib/application/settings/release_manifest.dart`**（后援 fallback）
- 在 `fallbackReleases` 列表顶部新增 `ChangelogRelease(version: '0.7.1', title: '数据治理、AI 安全与体验打磨', items: [...])`，items 为上述内容的精简版
- `journeySteps` 不新增（0.7.1 是 patch，仍归 0.7 里程碑）

**3. `CHANGELOG.md`**（工程历史，简版节）
- 在简版节顶部（`### [1.3.0]` 之前）新增 `### [0.7.1] - 2026-08-24`，按 Keep a Changelog 格式分 Added / Changed / Fixed 子节

**4. `pubspec.yaml`**
- `version: 0.7.0+1` → `version: 0.7.1+2`

**5. `android/local.properties`**
- `flutter.versionName=0.7.0` → `flutter.versionName=0.7.1`
- `flutter.versionCode=1` → `flutter.versionCode=2`

### 验证
- 确认 `assets/changelog.md` 首项 release id 与 `release_manifest.dart` 的 `latestFallbackReleaseId` 一致（均为 `0.7.1`）
- 确认 `releaseMatchesVersion('0.7.1', '0.7.1+2')` 返回 true
- 确认 assets/changelog.md 0.7 条目与 release_manifest.dart 0.7 条目内容一致