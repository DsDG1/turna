# Anki 可维护性债务收口验收凭据

> 状态：host 验收通过（2026-08-25）
> 适用范围：Due、formal-review error、Review All、import wizard
> 相关文档：[总入口](README.md)

## 验收结论

四个子系统的实现和 host 回归均已完成：

- Due 使用单一生产写入口和完整 snapshot 原子提交；
- 不可渲染卡形成结构化、可见、可重试的错误闭环；
- Review All 只使用真实来源的顺序模型；
- 导入页由 controller 与 flow 持有业务状态和编排。

本收据证明本轮可维护性债务已收口，不证明 Official Anki 迁移完成，也不替代 release candidate 的 native、APK 或真机证据。

## 基线与执行方式

施工在同一集成工作树按原 Wave 0 → 4 完成，每个子系统先用定向测试锁定目标行为，落地后转绿，再进行全量回归。

执行前记录了：

- 主工程与 native submodule revision/status；
- `git status --short`；
- Flutter analyze；
- Anki 定向测试与非 Golden 全量测试基线；
- 文档 34 的 release APK/设备结果边界。

干净基线曾有两个既存环境性失败：OHOS ABI guard 和 5K 分页批处理。收口后的最终全量回归中两者均未复现，最终为零失败。本轮没有修改数据库 schema 或用户卡片数据。

## 交付核对

### Due 状态

- [x] 一次完整 refresh 只 commit、notify 和增加 generation 一次；
- [x] Router 只收集并返回 due 数据；
- [x] Browser/Ledger mutation 使用 CAS，不手工写静态 map；
- [x] introduction/retire 在持久化成功后进入同一 source snapshot；
- [x] getter 不再动态旁路 IntroductionStore；
- [x] Play Hub build 不写 due；
- [x] snapshot 集合对外不可变；
- [x] stale 结果在生产刷新链路被拒绝；
- [x] 静态 due facade 删除并由架构守卫防止复活。

### 正式复习错误

- [x] loader 不再吞掉 render failure；
- [x] queue 非空且零成功时返回并显示 Blocked；
- [x] current card 被阻断时评分锁定；
- [x] retry 不创建重复 session 或重复评分；
- [x] failure 不触发 answer、bury 或 suspend；
- [x] Review All 汇总失败来源并支持重试；
- [x] audit 不记录卡片正文、HTML、typed answer 或媒体路径。

### Review All

- [x] production 中不存在 synthetic `official-all` 来源；
- [x] `OfficialReviewAllPlan` 和 batch 对应字段删除；
- [x] 每个来源独立启动 live scheduler session；
- [x] mixed Legacy + Official 按冻结顺序推进；
- [x] loader 拒绝空 sourceId；
- [x] 每张 Official card key 保留真实 sourceId；
- [x] 一个来源失败不污染其他来源 ledger；
- [x] 完成页区分成功和失败来源。

### 导入向导

- [x] sealed wizard state 覆盖 selecting、parsing、previewing、committing、completed 和 failed；
- [x] Legacy/Official preview 使用互斥 variant；
- [x] pick-time plan 在预览和 commit 间冻结；
- [x] repeated commit 保持 single-flight；
- [x] operation generation 丢弃 stale callback；
- [x] cancel、reset、dispose 和失败路径遵守资源清理语义；
- [x] 页面不直接依赖 DAO、engine、importer 或 projection；
- [x] 完成、立即学习和查看牌组的导航语义保持不变；
- [x] 页面、controller 和 step widgets 满足规模门禁。

## 必跑命令

```bash
flutter analyze

flutter test \
  test/application/anki/anki_unification_architecture_guard_test.dart \
  test/application/anki_official/official_formal_due_repository_test.dart \
  test/application/anki_official/official_formal_due_atomic_update_test.dart \
  test/application/anki_official/official_formal_review_unrenderable_test.dart \
  test/application/anki_official/official_live_formal_review_test.dart \
  test/application/anki_official/official_review_all_coordinator_test.dart \
  test/application/anki_official/official_formal_review_fidelity_test.dart \
  test/views/anki/anki_import_screen_test.dart \
  test/views/anki/anki_import_official_first_test.dart \
  --reporter compact

flutter test --exclude-tags golden --reporter compact
flutter test --tags golden --reporter compact
git diff --check
```

如果这些改动进入文档 34 的 release candidate，还必须额外执行其指定的 native、arm64 APK 和真机矩阵。

## 最终结果

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 0 issue |
| 必跑定向清单（含 controller 测试） | 63/63 通过 |
| 全量非 Golden | 2165/2165 通过 |
| Golden | 10/10 通过 |
| `git diff --check` | 通过 |
| 架构守卫 | due facade / view 写 due / synthetic source / 空 sourceId / 导入页规模与依赖门禁均生效 |

## 场景矩阵

### Due

- 六集合公式、known/unknown 和 fail-closed；
- 单来源与多来源隔离；
- refresh 的单次通知和 generation；
- refresh 与 bury/suspend、introduction/retire 竞争；
- stale refresh 丢弃，失败 refresh 保留旧 snapshot；
- Home、Hub、Profile、Review 和 Stats 同代读取；
- snapshot 外部不可变。

### Formal review

- rich/plain/MathJax/typed answer fidelity；
- current render 全失败、部分失败和重试成功；
- live queue answer 后出现不可渲染 current；
- retry 保持 cardId 与 queue epoch；
- failure 不写调度状态；
- source A 失败不影响 source B；
- failure summary 不泄露内容。

### Review All

- 多个 Official 来源顺序执行；
- Legacy 与 Official 混合执行；
- 来源列表冻结及真实 sourceId；
- catalog 缺失时使用 due snapshot fallback；
- NoDue 自动推进，Blocked 等待明确选择；
- 完成与失败统计准确；
- production 中没有 synthetic aggregate source。

### Import wizard

- picker cancel、非法扩展名和 sample；
- Legacy parse/preview/AI mapping/commit/cancel；
- Official preview/mapping/skip/project/publish；
- feature flag fail-closed 且零 Legacy 写；
- collision 策略保持；
- repeated commit、stale callback 和 preview abandon cleanup；
- completion course order 与导航语义；
- 放大文字和窄屏视觉回归。

## 性能与资源边界

已经由自动化测试固化“一次 due refresh 最多一次 repository notify”。以下耗时或资源项目需要在 release candidate 的真机/大样本环境采样，不能从 host 单元测试推断：

- 100/5K 卡 import preview 与 commit 时间；
- Review All 来源切换耗时；
- render failure retry 耗时；
- session 前后 Dart heap/RSS 趋势。

实现仍须遵守：同一时刻只保留一个 Review All 来源 session；failure 不缓存完整 HTML；导入完成/取消后释放 collection、schema samples 和临时 media directory；UI build 不执行 O(cards) 状态写入。

## 发布与已知边界

- 本轮没有合入文档 34 的 release candidate，因而 34 的设备门禁在本收据中不适用；
- host 测试不能替代 native、APK 和真机证据；
- W9 Legacy 物理删除继续 HOLD；
- production `planFor` 链路没有 `allowLegacyOnly`，但这不足以授权删除 Legacy 数据结构和恢复能力；
- 后续架构债务见[总入口](README.md#后续债务)，必须分别立项。
