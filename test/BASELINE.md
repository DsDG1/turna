Generated: 2026-09-08 (主页卡片展开性能 P0+P1)：揭示动画透明度因子经 `TurnaMotion.stagger` 新增 `span` 参数提前收尾（区间 `[start, start+0.6]`），部分不透明期每行每帧 saveLayer 的窗口砍掉后 40%，动画后段行达完全不透明后直接绘制；`_resolveStatusProjection` 加 identity 三元组缓存（section / dueWordIdSet / mistakeEntries 均实例稳定来源，内容变化才换实例），展开手风琴等与投影无关的重建不再重算 O(全部待复习词) 聚合。定向 **23 passed**（course_tree_test 22→23，新增「透明度先于帘式高度收满」断言）；全量 **1735 passed / 12 failed，12 个全为 golden 本机既有差异**（stash 干净 HEAD 复现同样 72.46%/98.02% diff 佐证；基线在册字体切换后 golden 陈旧）。`flutter analyze` No issues found。

Generated: 2026-09-02 (未完成导入挡新导入)：导入页未完成导入显示「系统错误」+「必须先放弃才能导入新卡」；选文件/startStaging 前 fail-closed。定向 **4 passed**：view_helpers 2→3、interrupted_import_card 1、controller unfinished 1。`dart analyze` 改动文件 0 issue。

Generated: 2026-09-02 (v2 10万卡删不掉)：课程管理 `uninstall` 在 UI isolate 同步 `runRetireJob`（先 `listCards` 物化全部所有权行再 op 32），大源确认删除卡住、树还在。改：`beginRetire` 后仅 ≤5000 卡等待引擎段；更大源 detached；引擎删改 `listCardIdsPage` 分批+yield。定向 **4 passed**（retire 分页 1 + begin/full + F4 uninstall）。**真机 PLG110 用户验证通过**。

Generated: 2026-09-02 (v2 K2 中断导入幽灵卡)：live `importPackage` 强杀后课程树无源、collection 占体积。差集回收 `OfficialAnkiV2UnownedCardReclaimer` + committing 放弃/启动空账本再扫。定向 **2 passed**：`official_anki_v2_unowned_card_reclaimer_test`。`dart analyze` 改动文件 No issues found。**真机 PLG110 用户验证通过**。

Generated: 2026-09-02 (Anki 收藏幽灵残留强制清空)：空账本时存储页「强制清空残留」关掉引擎后删 collection/media/checkpoints/backups/无主 staging，有 source 或未完成导入 fail-closed。定向 **15 passed**：ghost_purge_service 3、storage_diagnostics_page_test 10→12。`dart analyze` 改动文件 0 issue。

Generated: 2026-09-02 (存储页 Anki 收藏/媒体勾选删除 + 修复中心)：存储页下钻多选走 `AnkiDeckManager.uninstall`；修复中心展示 `retiring`、隔离可删、人话状态、去掉重复优化按钮。定向 **12 passed**：`storage_diagnostics_page_test` 6→10、`official_anki_repair_center_page_test` 2。`dart analyze` 改动文件 0 issue。

Generated: 2026-09-02 (crash-hunt 终局:导入向导 pop 死循环 = 「闪退」唯一根因,已修复):三轮 profile/debug 真机抓捕链:①冻结现场 `top -H` 证主线程烧 93% 而 VM 服务秒回 → 排除主 isolate 自旋;②冻结中 getVMTimeline(25s 窗口)证 root isolate 每秒 ~100 次 Scavenge = 1.6GB/s 短命分配风暴(堆「平稳」是假象);③debug 模式每秒 getStack 采样当场命中同一循环帧:`maybePop ← _callPopInvoked ← onPopInvokedWithResult ← maybePop`,配合源码钉死:向导页 `PopScope(canPop:false)` 写死永不放行 + `_confirmLeave` 在 Completed 态秒回 true + 回调里重试 `context.router.maybePop()` → 无限微任务乒乓(每轮全树 router 祖先查找+路由机器 = 分配源)。三入口全中:开始学习/完成(直接 maybePop)、返回箭头、取消并清理;「查看牌组」是 push 不触发,与实测吻合。**修复**:`anki_import_screen.dart` 四处离开路径 maybePop→`context.router.pop()`(绕过 canPop 闸门,同 ai_api_config_page 既有修法);新增守卫测试 `anki_import_pop_loop_guard_test.dart`(锁死向导文件内不得出现 `.maybePop(` 调用)。`flutter analyze` 0 issue;定向仅剩 2 预存失败(staging v12 断言/controller importFile 断言)。**真机 PLG110 用户实测通过(「完美完成」)**。附带确认:profile 包日志 `[OfficialAnkiV2] unimplemented` = 设备 .so 旧于 op41/42(契约 1.12),仅影响 v2 配置区写(生产 flag 关,无害),后续换 so 时自然消除。PR1 主线程止血与本 bug 正交,仍然有效;PR2(catalog 迁 drift)按既定计划另行开工。

Generated: 2026-09-01 (crash-hunt PR1 主线程止血):根因=主 isolate 同步 sqlite3 catalog + 纯 Dart 重活→ANR 被杀(bugreport 6 次死亡全为 reason=ANR/Input dispatching timed out 5001ms,主线程 state=R utm 最高 125s、PC 落 dart-code 或 APK 内嵌 .so,无 tombstone;证据 `logs/crash-hunt/`)。五类落码:①投影组树 + 512KB 切分 JSON + 逐课 contentJson 预编码整体 `Isolate.run`(`official_anki_projection_service._buildPlan`,注入 projector 走 inline 保测试 seam;`officialAnkiLessonGroups` 共享分组,store 增 `lessonContentJson` 预编码入参);②`CourseRepository.vocabulary()` ≥64 行后台转换(tags 逐行 jsonDecode 挪后台)、`lessonById` >16KB 与 `lessonsContainingAny` lesson JSON 后台解码(`_toLesson`/`_decodeStringList` 等转 static 零捕获);③apkg SHA-256 哈希整体后台 isolate(`official_anki_source_hasher.dart`);④commit 回执段(replaceNoteIds/noteIdPage 分页/commitIndexBatch/replaceAssociations/receiptCommitted)抽到 `official_anki_commit_receipt.dart`,生产(worker 模式+真 session+零注入)走新 `OfficialAnkiSession.commitReceipt` RPC 在 worker 内执行,顺带消灭每页 2 次 RPC 往返;测试注入走原 inline 路径,序列逐行同源。⑤四页面 build() 内同步 catalog 查询(pending banner/修复中心/deck stats/来源管理)改 state 快照+动作后刷新。`flutter analyze` lib **No issues found**。全量 **1766 passed / 35 failed,逐项定性全为预存、零新增**:基线在册 21(media_resolver ×8 errno123、composition errno32、reviewer_behavior/ui_av、status_map、review_dashboard ×2、review_progress、review_history_dao ×2、lesson_flow、backup_snapshot、round2 golden ×2)+ golden 8(course_tree/dictionary/settings_reminder/srs ×2,基线历次全量为 `--exclude-tags golden` 未含,疑字体切换后 golden 陈旧)+ loading 2(execution_plan/host_ffi 在 HEAD 即引用已删方法/缺 import 编译失败)+ P5F/controller 3(断言 `session.importFile` 计数,该调用链 doc 42 staging-first 后已结构性删除;flow 项 08-30 基线在册)+ staging_manager 1(断言 schema 12,现 13)。定向回归 **38 passed**:commit_live/open_before_import/staging_first_p0/repair_center/v2 全绿。完整日志 `logs/pr1-fulltest.log`。真机 PLG110 大库 ANR 复测 **未跑**;PR1 为降险非根除(小查询仍可撞 busy 锁),PR2(catalog 迁 drift 后台)未开工。

Generated: 2026-09-01 (系统字体切换 host 施工:google_fonts 移除 + 阅读障碍字体下线,docs/system-font-cutover-plan.md):删 `pubspec.yaml` google_fonts 依赖(lock 同步瘦身,`pub get --offline`);整删 `lib/views/app_fonts.dart`(全工程唯一 google_fonts import 面);欢迎页 `center_display.dart` 3 处 `AppFonts.nunito` 内联 `TextStyle`(拉丁字形 Nunito→系统字体,中文/其余界面零变化);`app.dart` 删 Lexend 主题分叉与 `_AccSnapshot.dyslexiaFont`;`AccessibilityProvider`/`AccessibilityCapabilities` 删 dyslexiaFont 字段与 dyslexiaFriendlyTypography(接口/生产/桩三处);删 `SettingsDyslexiaFontTile` 及页面挂载、`LocalStateKeys.dyslexiaFont`、备份清单条目、2 个 l10n 键;存量设备 `settings.dyslexiaFont` pref 成死键不迁移。`rg -i "dyslex|AppFonts|google_fonts" lib test pubspec.yaml pubspec.lock` **归零**。`flutter analyze` 改动文件 0 issue(报告 6 issue 全为预存在,位于未触碰的 anki/schema 测试文件)。定向 **87 passed**:accessibility provider/capabilities、backup_manifest_policy、`test/views/settings/` 全目录、course_ready_guard、wetland_palette_contract。真机 PLG110 发布门禁(欢迎页 CPU ≤5%、ANR 零增长、apkg 导入路径)**未跑**。

Generated: 2026-09-01 (Official 开始学习空树 fallback):冷启动 `catalogOf` 接到 readOnlyCatalog；v1 visibility 不再要求 catalog；已安装 source 空树不弹回内置课。定向 **10 passed**：`course_provider_official_scope_test` 8→10、`official_anki_course_entry_test` 1。

Generated: 2026-09-01 (v1 pending_cleanup / compact invalid_state)：卸载 saga `openProfile` + `cid:1,2,3` 校验、invalid_state 重试；op 39 关库 VACUUM 重开 + 阈值 skip；maintenance 对 invalid_state 标 completed skip；due sync 不 rethrow。定向 **19 passed**：lifecycle_storage（原 13 + uninstall-open + compact-skip 2）+ due_sync_unavailable 2 + course_compact 4。`cargo test compact_collection` 本机缺 `protoc`（`tools/protoc` 未检出）未跑。真机须重建 `libturna_anki.so`。

Generated: 2026-08-31 (doc 41 S7/S8 存储优化 + 修复中心 UI)：存储页一键 `forceCompact` 忽略阈值；独立 `OfficialAnkiRepairCenterPage`（产品面）。定向 **13 passed**：`storage_diagnostics_page_test` 6、`official_storage_optimize_service_test` 1、`official_anki_repair_center_page_test` 2、`official_diagnostics_release_guard_test` 4。`flutter analyze` 改动文件 0 issue。真机 `collection.anki2` 字节回收 **deferred / unverifiable**。全量与 Android 强杀矩阵未跑。commit `0743429e`（A+B 合一次，未按计划拆两个 commit）。

Generated: 2026-08-31 (doc 41 S7 CourseDB VACUUM)：`OfficialAnkiMaintenanceRunner.compactCourseDatabase` 在 Drift 连接上 `wal_checkpoint`+`VACUUM`（阈值或 `forceCompact`）；卸载排队 `compact_course`；repair executor 传入 `CourseDatabase`。定向 `official_anki_course_compact_test`。Android 强杀矩阵仍未跑。

Generated: 2026-08-31 (doc 42 P4 旧路径删除)：生产导入只走 `startStaging` → `commitLive`。删 orchestrator live-first `importFile`/`createBackup`；缺 catalog 不再 facade 直连 live；`restoreBackup` 仅存量 checkpoint；无 checkpoint 未完成导入 quarantine。worker `importFile` 薄转 `importPackage`。inventory `official_anki/staging/`。P0 S-a/S-b/S-c/S-d 须保持绿。

Generated: 2026-08-31 (doc 42 P3 commit + scoped publish)：`projectSource(notetypeIds:)` 修 S-c；`OfficialAnkiImportSaga.commitLive` 确认后写 live Collection 并晋升 mapping；`OfficialAnkiStartupRecovery` 单入口 lease/repair；待完成导入条。P0 S-a/S-b/S-c/S-d **passed**。新增 `official_anki_commit_live_test`。`importFile` 仍保留（P4）。

Generated: 2026-08-31 (doc 42 P2 映射交互)：`OfficialAnkiMappingPage` 保存恒可点、二选一正面、确认/跳过 pop；preview 行「已确认」；`skipOfficialNotetype` 清 `needsMapping`；wizard 确认不写全局 mapping 表。P0 S-d **passed**；S-c 仍红。`OfficialAnkiMappingRoute` 移出 diagnostics guard。定向：mapping_page、preview 已确认、skip/needsMapping、S-a/S-b、S-c 仍失败。

Generated: 2026-08-31 (doc 42 P1 staging 基座)：catalog 11→12（`phase`/`staging_path`）；`OfficialAnkiStagingManager` + 第二 isolate 槽位 + `OfficialAnkiImportSaga.startStaging/cancelActive`；wizard parse/cancel 不写 live Collection。P0 S-a/S-b **passed**；S-c/S-d 仍红（P2/P3）。新增 `official_anki_staging_manager_test` 3。`importFile` 旧路径保留。wizard commit 未改（P3）。定向：staging_first_p0 S-a/S-b、staging_manager、lifecycle schema v12、controller。composition single-flights errno 32 为 Windows 预存。

Generated: 2026-08-31 (doc 42 P0 staging-first 失败门禁)：S-a/S-b `anki_import_staging_first_p0_test`；S-c `official_anki_projection_scope_p0_test`；S-d mapping 页。生产代码未改。P1 后 S-a/S-b 改绿。

Generated: 2026-08-31 (doc 41 Android arm64 `.so` 按 contract 1.11 重建)：`android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so` 23,062,296 bytes，SHA-256 `C2808E58FE5AD28A5BD8B6A7CDFDEC4769785216F7F89F0765FB95283FD55530`（替换 2026-08-25 旧 so `179C2AD0…CBEF6F`）。工具链：rustc 1.97.1、cargo-ndk 4.1.2、NDK 28.2.13676358 r28c、API 24、protoc 31.1。`verify_symbols.sh` pass（ELF AArch64、导出 `turna_anki_abi_version`/`engine_new`/`call`/`buffer_free`、NEEDED `libdl.so`/`libm.so`/`libc.so`、无 glibc）。未跑 `host-test.sh`、未跑 Android 强杀矩阵。生产 NO-GO。

Generated: 2026-08-30 (doc 41 Official Anki 生命周期/存储回收 host 施工)：catalog schema 10→11；contract 1.10→1.11（ops 37–40）；导入 `preview_ready`/`staging`，authority+identity 同事务后 `active`；startup recovery；verified uninstall；source-scoped metadata；fake media GC；bounded checkpoint。定向 lifecycle/recovery/cleanup/contract/reanchor/official-first **passed**。全量 `--exclude-tags golden` **实跑 1742 passed / 21 failed**（log 已存）。21 项逐条：composition errno 32；media_resolver ×8 `question?.png` errno 123；reviewer_behavior `/` vs `\\`；reviewer_ui_av 同；status_map 29 vs ≥30；review_dashboard overdue 0≠1 + dailyActivity Null cast；review_progress activityBuckets Null；review_history_dao ×2 同 Null；lesson_flow false；backup_snapshot errno 32；round2 golden light/dark。`p5f_official_first_flow` 不在失败集。**native `.so` 当时未重建**（已由 2026-08-31 行覆盖）；Android 强杀矩阵未跑。生产 NO-GO。

Generated: 2026-08-30 (Anki 简单清理)：删未读取的 `legacyMirror` / `OfficialAnkiFeatureFlags.diagnostics`；删 `UnifiedAnkiImportOrchestrator.invalidate` 空钩子与恒 false 的 `wroteTurnaSrs`/`noOp`/`turnaSrsWordIds`；NoteStore 注释改为 Legacy 只读残件。architecture guard +1。定向：guard / flags / composition / projection_anchor / import official-first。`flutter analyze` 改动文件 0 issue。composition single-flights errno 32 与 `p5f_official_first_flow_projects_course_and_publishes` 为 Windows 预存失败，本轮零新增。

Generated: 2026-08-30 (Anki 复习界面焕新)：复习大厅对齐练习页着色实体卡（Hero 到期 CTA / 清完态 / 牌组 SoftCard + 浏览/统计外露）；正式复习会话 chrome（准备中、错误空态、显示答案品牌按钮、来源 chip + 重做/搁置/暂停下移）。调度/入口行为不变。定向：`anki_review_hub_test` 0→2、`anki_review_session_official_path_test` 7 保持全绿；`flutter analyze` 改动文件 0 issue。

Generated: 2026-08-29 (doc 37 通用卡片识别器 P1–P5 一次性施工)：契约 1.8→1.9（get_projection_schemas +templateFacts/reqs、sampleLimit 上限 30）；新识别器 lib/application/anki_import/recognition/（词典绑定+notetype 级原型判定+卡级校验+薄 policy）；旧识别器六文件删除（arch guard 断言不复活）；16 案例金标准语料+全量快照；diff harness 双跑 16/16 一致或改进、零新劣化、低置信 0%（报告 archive/artifacts/recognizer-diff-report-2026-08-29.md，harness 用后即删）；预览四件套+映射编辑器新词表（prompt/response/…，旧 JSON 兼容解析）；listenPick/MCQ 交互语义修正+basicPair 卡级升级链。`flutter analyze`：**No issues found**；定向（识别器 32+投影 38+守卫/契约/预设/映射页/预览/正式复习）全绿；全量 `--exclude-tags golden`：**1723 passed / 24 failed**——24 项经干净 worktree 复现全部为预存在（media_resolver ×9、review_dashboard/review_history_dao/review_progress、backup_snapshot、lesson_flow、round2 golden ×2、reviewer_behavior/ui_av、official_first flow、orchestrator errno32、composition single-flights 等，见 doc 37 §10.4）；本轮引入过的 3 项契约 bump 联动失败（render_contract/scheduler_p4 硬编码 minor、contract golden 1.6）当场修复复绿。**Rust 侧（projection.rs/gen_fixtures.rs/契约版本）本机无 cargo 未编译验证**——合并前须 cargo 主机跑 host-test.sh + regen fixtures + 重建 arm64 so（doc 37 D1）。

Generated: 2026-08-29 (ADR 0037 选项 A)：正式到期 cardId 走分页搜索、不受 `getReviewQueue` 100 张上限；第一遍下课 `ENSURE_TODAY_NEW_QUOTA`（contract 1.8 / op 36，`extend_new`）覆盖本课新卡；重做 flush 跳过 `rated:1`，失败在完成摘要可见。定向：due card-ids + lesson_viewmodel anki + quota/redo + scheduler/render contract 1.8。Android 需重建 `libturna_anki.so`（op 35+36）；旧 so 上 fail-closed。

Generated: 2026-08-29 (ADR 0037 第二次修订落地)：练习页/个人页按 `CourseScope` 切开队列（语言课错题/单词/语法，导入 Anki 仅 Anki 复习并藏薄弱单词）；课内 Anki 不写错题本；introduced 改到 Lesson 完成才解锁（导入历史 `reps≥1` 仍直接解锁）；`getReviewQueue` fetchLimit 钳到 1..=100，`QUEUE_EMPTY` 当空集合。定向测试：play_hub + eligibility + due card-ids + course practice + lesson_viewmodel anki unlock + golden 2 刷新。重做课提前复习 flush 未做（无 filtered-deck FFI）。

Generated: 2026-08-25 (doc 34 ANKI-CUTOVER-ONE-SHOT host closure)：CourseDatabase v21 owner authority/transition、CourseScope v1、精确课程目录与卸载、Official fidelity/live Scheduler、Legacy + Official 混合 Review All、六集合 Formal Due、全 Legacy writer fence、生产 W8 migration center/coordinator 与 post-commit forward recovery、source-scoped Browser/Stats、turna-migration-v1 importer、release route guard 均已接入。Legacy 导入 mutation 已从 UI 抽入 application executor；CourseDB identity 同事务提交，同 ID 重导媒体使用 staging + 原子换目录，并以 incoming/committed source hash 跨进程恢复强杀窗口。Native contract v1.6 的 DELETE_CARDS/STATS_FOR_CARDS_BATCH/SCHEDULE_CARDS_AS_NEW 已从当前源码重建进 arm64 APK。`flutter analyze`：**No issues found**；非 Golden 全量：**1852 passed / 0 failed**；golden：**4/4**；native：**68/68**。arm64 APK 56,120,065 bytes，SHA-256 见 `docs/official-anki-migration/archive/artifacts/cutover-once/apk-sha256.txt`。release 真机矩阵与 OHOS 外部事实未做，整体仍 NO-GO，W9 HOLD。

Generated: 2026-08-28 (Play Hub 焕新重构)：练习页主页信息架构重排（今日复习主卡 + 复习队列 2×2 + AI 助手单行 + 练习工具三列），新增长按浮窗交互（`views/play/components/info_popup.dart` 锚定浮窗 + `play_info_panels.dart` 8 个数据面板；短按进入 / 长按看数据，词典与 Playground 不参与）；`play_tiles.dart` 新增 TodayHeroCard / AiAssistantTile / CompactToolTile 并给 SoftCard 系加 onLongPress 管道，FocusTile 退役；清理 11 个无引用 l10n 键（playTodayFocusTitle / playReviewCenterTitle / playToolsTitle / playStartAction / playAiViewAll / playMistakeFocus* / playReviewFocus* / playDailyChallengeFocusCount / playPopupAiModelDefault）。测试 5→8（+3 长按浮窗：错题面板出现+遮罩关闭 / Anki 面板进入按钮走共享会话 / 今日 Hero 队列总览）；play_hub light/dark golden 已刷新通过。附带修复 AI API 配置页 dispose 补存踩 `widget tree was locked`（真机日志证实）：`_flushDraftForDispose` 改 `Future.microtask` 延迟通知，`ai_api_config_page_test` +1 回归（含 provider 监听依赖复现场景；临时还原 bug 验证该测试确实失败）。`flutter analyze`：改动文件 0 issue（存量 4 info 在 official_anki_projection_test）。本机全量 `--exclude-tags golden`：**1684 passed / 21 failed**——21 失败经 `git stash` 摘除本轮改动复跑抽查（official_anki_media_resolver、review_progress_provider 等）仍失败，全部为 Windows 环境性预存在失败（文件名含 `?` 触发 errno 123 等），与本轮无关；本轮直接相关测试（views/play 8 + wetland_palette_contract + formal_review_launcher + playground + ai_focus_mode + ai_api_config 4 + play_hub golden 2）全数通过。

# Test Baseline

Generated: 2026-08-24 (doc 34 C4: collapse Official feature dart-defines to one production Android bundle; drop gray cohort from planner; rename `officialCapable` → `schedulerRuntimeAvailable`. Directed C4 **94 passed**. Full-suite estimate **~1651** (p5d gray sequential test removed, +1 architecture guard).)

Previous: Generated: 2026-08-24 (doc 34 C3+C5: Official-first service extracts saga/preview/publish from import wizard; delete unused dual-policy + user saga; picker `.apkg` only; sample fail-closed. Directed C3/C5 **87 passed**. Full-suite estimate **~1651** = 1649+2 architecture guards.)

Previous: Generated: 2026-08-24 (doc 34 G-C: Official browser Collection search/render + suspend; stats catalog vs proven scheduler counts; formal due drops count-approx. Directed browser/stats/due **21 passed**. Full-suite estimate **~1649**.)

Previous: Generated: 2026-08-24 (doc 34 W5+W6: exact Official formal-due card-key intersection + `OfficialStudyBatchAssembler` / `FormalReviewLauncher.assembleOfficialBatch` / shared-host Official wire; course Official cards → `StudyMode.practice` + marksIntroduced exactly-once, no learn→ledger-fail fallback. Directed tests **36 passed** / analyze 0 issue. Full-suite estimate **~1641** = 1628+13.)

Previous: Generated: 2026-08-24 (清扫无入口小垃圾：删除配对游戏 / 字母描红 / Mala 与 Duolingo 化石图；删 `MatchWordsRoute`/`VowelAndConsonantLearningRoute`、`MatchProvider`/`CharacterProvider`、空 alphabet map、`mala_welcomes` 别名、`flattenLanguage`/`shuffleMap`/`getFormattedTime`、未使用 `sm2Engine` 字段、`tool/split_course.py`。测试 −5：`match_provider_test` 4 + `match_words_test` 1。`flutter analyze` 改动文件 0 error。全量 `flutter test --exclude-tags golden`：**1628 passed / 4 failed**——4 失败（webdav_client delete、ai_api_config_page dispose draft、dark_mode_text_contrast、wetland_palette_contract）与本轮无关。)

Previous: Generated: 2026-08-23 (远程备份与手动远程同步 P1（自建 WebDAV，坚果云同协议后续适配）：新增 `lib/service/remote_backup/` 服务域——①`RemoteBackupConfig`/`RemoteBackupConfigStore`（单 key JSON 持久化，经裸 StreamingSharedPreferences 绕过 printBefore，密码不落日志；`ensureRemoteBackupDeviceId` 每安装稳定设备 id）；②`WebDavClient`（纯 package:http 的 OPTIONS/HEAD/MKCOL/PUT/GET/DELETE/MOVE 封装，Basic Auth、流式上传下载、401→`WebDavAuthException`、不跟随重定向防凭据泄漏，零新增 pubspec 依赖）；③`BackupSnapshotService`（一致性本地快照：prefs 超集清单 exact+include 前缀按 live key 过滤（覆盖 FSRS 调参/无障碍/动态 per-scope TTS/anki 限额等 40+ 键，结构性排除 remoteBackup.*/system.healthEvent/每日计数，`ai.engineConfig` 写入前剥离 apiKey）；course.db 走 drift `VACUUM INTO`；collection.anki2/official_catalog.sqlite/collection.media.db2 走裸 sqlite3 只读连接 + VACUUM INTO 在线快照（absent 记 hasX=false 不产垃圾）；媒体 anki_media/ 与 collection.media/ 复用 `ankiHashFileSha256` 分块哈希产 media_manifest + 去重对象表；archive 4.x `ZipEncoder.add(ArchiveFile.stream)` 流式打 core.zip + SHA256SUMS（仿 p5c 物理备份格式））；④`RemoteBackupStore` 抽象 + `WebDavRemoteBackupStore`（远端布局 `<root>/{manifest.json,backups/<id>/core.zip,media/<sha256>}`，manifest 经 .tmp+MOVE 原子发布，保留 [kRemoteBackupRetention]=5 代，media 对象内容寻址只增不删）；⑤`RemoteBackupService` 编排（backupNow 顺序=媒体→core→manifest（中断无半份最新备份）+ 保留清理 + lastInfo 本地记录；restoreToStaging=下载 core→sha256 校验→流式解包→SHA256SUMS 复核→逐媒体对象下载校验→**最后**写 restore_pending.json 标记（崩溃安全提交点）；busyGuard 钩子）；⑥`RestoreApplier`（挂 `setupLocator()` prefs 就绪后、`_openAndSeedCourseDatabase()` 前——全库唯一文件全闭合点：版本守卫（staged drift/catalog schema 或 user_version 超当前→blocked 保 staging 待升级）、prefs 按类型分发写回（跳过 remoteBackup.*）、库文件 .restore-partial→rename 原子替换并清 -wal/-shm 边车、媒体按 logical 前缀落盘、幂等可重试；OHos（course.db 在系统 RDB 无文件路径）与 Web 排除）；⑦UI `RemoteBackupPage`（@RoutePage + SettingsScaffold：服务器配置三输入+测试连接（按钮 spinner+内联结果行）、媒体开关+立即备份（阶段文案+字节格式化）、从远程恢复（远端 manifest 摘要副标题→SettingsConfirmDialog 破坏性确认→staged 完成提示重启）；设置页 Data 分类新增 tile（OHos 置灰"暂不支持"）；路由注册+build_runner 重生成 routing.gr.dart；隐私文案补远程备份说明。`shared_preferences` 由 dev_dependencies 移入 dependencies（快照需无类型 sp.get）。测试 +44：webdav_client 9（含 `MiniDavServer` 手写 dart:io 回环 DAV 服务器：401/409/405/MOVE Overwrite 语义）+ backup_manifest 6 + config 5 + snapshot 4（VACUUM INTO 产物/user_version=18/apiKey 剥离/absent/去重）+ store 6 + service 6（上传顺序断言/增量跳过/保留清理/busyGuard/staging 标记/篡改 sha 中止）+ applier 4（应用全链路/新版本拒配/坏标记清理/noPending）+ page 4（Fake+noSuchMethod、懒构建 ListView 手动 drag 滚动）。`flutter analyze` 新增文件 0 issue。全量 `flutter test --exclude-tags golden`：**1459 passed / 4 failed**——4 失败（anki_import_official_first、anki_import_screen、dark_mode_text_contrast、wetland_palette_contract）与 2026-08-22 基线记录的预存在失败集完全一致（另 schema_migration_test 全量偶发 flaky、单跑稳定通过，两次全量复跑确认与本轮无关），本轮未引入新失败。)

Previous: Generated: 2026-08-22 (语言 Playground P0+P1（docs/language-playground-implementation-plan.md §10–§15）：①资格策略——新增 `LanguagePlaygroundEligibility`（scope `''`/非 `anki:` 前缀合格，未来多语言课程须升级 CourseKind）；②入口——`QuickPlayHero` 更名 `PlaygroundHero`（默认图标 sports_esports），Play Hub 顶部 Hero 改文案 Playground/自由组合题型并经 `context.select<CourseProvider>` 监听资格，Anki scope 下 Hero+专属间距（合入同一 Padding）一起消失，点击推 `LanguagePlaygroundRoute`（挂 CourseReadyGuard）而非 MatchWords；③页面二次隔离——新增 `LanguagePlaygroundPage`：initState 缓存 provider 引用（dispose 不查 deactivated 祖先）+ post-frame 资格检查，Anki scope 下 SnackBar 一次 + 等入场转场完成后 `maybePop`，无可返回（深链冷启动）则就地渲染拦截态；骨架含智能开练 Hero（P2 前占位提示）、内容范围 ChoiceChips（recent/当前单元/整个课程/薄弱；recent 在 P1 回退当前单元经 `resolvedScope` 暴露）、8 模式网格按 `PlaygroundAssembler.availableModes` 显示可用题量或不可用原因（Semantics disabled）；④P1 管线——`PlaygroundSessionConfig`/`PlaygroundMode`/`PlaygroundContentScope`/`PlaygroundDifficulty`/`PlaygroundDirection` 模型 + sealed `PlaygroundAssemblyResult`（Ready 带 Lesson/wordIds/metadata，Unavailable 带 reason+替代模式）；`PlaygroundContentSource` 只读 `sections()`（绝不碰 allSections），Section level（Anki/OfficialAnki）+ Interaction 类型（AnkiCard/AnkiHtmlCard）双重过滤，错题快照恢复时二次同过滤，wholeCourse 逐节 ensureSectionLoaded、失败 Section 记 diagnostics 可跳过、全失败返回 sectionLoadFailed；`PlaygroundAssembler` 入口再验资格（ineligibleCourse 显式拒绝）、确定性去重（lessonId+interactionId）、Fisher–Yates 可注入 Random、题量裁剪、wordMatch <4 词对禁用（≥4 返回 wordIds 供 P2 match controller 解析 WordEntry）、`pg-$i` 重打标。routing.gr.dart 经 build_runner 重新生成。⑤代码复审修复——`_fromCurrentUnit` 经 `sectionLoadState` 检测加载失败（失败 Section 保留壳、`currentSection` 非 null，原 `loaded == null` 分支不可达，会把失败误报为 noCourseContent；recent 回退同路径）；薄弱范围接 `MistakeProvider.entries`（此前永远空）；深链拦截态在课程切回语言 scope 后解除并重置退出提示；`failedSectionIds`/`sectionLoadFailed` 文档改为不限 wholeCourse；计划 §6.2 措辞同步为就地拦截+自动解除。测试 +33：eligibility 4 + assembler/source 18（Anki 双过滤×2、错题快照拒 Anki、sections≠allSections、seed 稳定、去重、wordMatch 门槛、失败原因、当前单元加载失败 sectionLoadFailed 等）+ Playground 页 widget 8（深链拦截/深链拦截后切回语言课程解除/进入即退/开着切课程退出/availability/占位提示/范围切换/薄弱范围接错题快照）+ Play Hub 重写 5（重写后全量 5，其中 3 新增、2 沿用：语言显示、Anki 全隐含间距、双向切换、点击进 Playground 页）。`flutter analyze` 改动文件 0 新增 issue。全量 `flutter test --exclude-tags golden`：**1395 passed / 4 failed**（复审修复前；⑤ 新增 3 测在本机无 Flutter SDK 未跑，提交前须全量复跑核数 1398+）——4 失败（anki_import_official_first、anki_import_screen、dark_mode_text_contrast、wetland_palette_contract）经 `git worktree` 干净 HEAD 复跑确认**均为预存在失败**，与本轮无关。play_hub light/dark golden 随 Hero 文案更新刷新并通过；dictionary/settings_reminder/srs_review 6 个 golden 为预存在本机环境 diff（基线生成于 OHos Flutter fork，本轮未触碰其页面、未动其基线）。)

Previous: Generated: 2026-08-22 (首页底栏 hide-on-scroll：`ScrollHidePolicy` 纯函数 + `ScrollHideBar`（AnimatedSlide 1.15 / IgnorePointer），`HomePage` 对 IndexedStack 听 `UserScrollNotification`，切 tab 强制显示，不改 overlayExtent。新增 9 测：policy 6 + bar widget 3。`flutter analyze` 改动文件 0 issue。定向 `flutter test` **14 passed**。全量估计 **1308** = 1299+9。)

Previous: Generated: 2026-08-22 (P5-F 官方先行导入四片施工（docs/official-anki-migration/33）：①顺序翻转——新增 opt-in flag `TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT`+组合门+policy 纯函数，`_executeImport` 官方 saga 前移至 Turna 写入之前（失败零写入、alreadyImported 走 noOp、反向半态守卫日志），抽出 `_importOfficialPackage/_recordOfficialMigration`；③清理面——`uninstallDeck` substring→精确前缀、新增 `AnkiDeckManager.uninstall` 官方分流（软卸载：投影+catalog deleteSource+unification 清理）、`AnkiUnificationDao.deleteByCourseId`、`OfficialAnkiSourceDao.deleteSource`（FK 序）、seeder `_clearCourseTables` 补删投影 index/manifest、投影 store 受控 vocabulary 通道（tag `official:<sourceId>`，projector 产出 term/translation）；②投影替换——向导官方路径重排（`_pickFile→_proceedWithPath` 分流到 saga→schema/deck 预览→`projectSource()`，`OfficialAnkiMappingPage` 内联映射确认、自动确认剩余建议、needsMapping 回预览）、`UnifiedAnkiImportOrchestrator.publishFromProjection`（placement 锚到投影 index 真实 tree id+kind）、`officialAnkiMediaCandidateFile` 媒体解析接通（speakWord/speakListenContent 裸文件名→collection.media 本地播放）、退役 `OfficialAnkiNewImportCutover`；④门禁——`OfficialFirstReanchor` 启动一次性换锚（pref `official_first_reanchor_v1`，无 manifest 的双写存量不动）、parity 双管线 harness+白名单 `test/fixtures/anki_official/parity_allowlist.json`。测试基建：`AnkiImportPage.importerForTest` 解析器注入缝、`OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests`、`OfficialAnkiCompositionRoot.debugEngineOverride`；修复本仓测试潜在地雷——get_it 7.7 `reset()` 为 async，未 await 的 reset+再注册会在首个 await 后被清空（新测试全部 await）。新增 33 测试：official_first flags/policy/reanchor/projection_anchor/parity(3)+cleanup_surfaces(6)+向导 official_first(3 widget)。`flutter analyze` 改动文件 0 新增 issue。`flutter test --exclude-tags golden`：**1299 passed / 0 failed**。）

Previous: Generated: 2026-08-21 (修复 ElevatedButton 按压阴影：Flutter 3.44 `ElevatedButton.styleFrom(elevation:)` 语义改为按状态缩放（pressed = base+6 / hovered+focused = base+2），`elevation: 0` 的按钮按下时海拔跳 6 冒浓阴影。7 处改链 `.copyWith(elevation: WidgetStatePropertyAll<double>(0))` 全状态钉平：light/dark `elevatedButtonTheme`（高对比主题 copyWith 继承）、BinaryRecallBar、UnifiedReviewPage 显示答案、UnifiedReviewCompletion、anki_card_renderer / anki_html_card_renderer `_GradeButton`；Filled/Outlined/Text 的 styleFrom 为 `allOrNull` 平铺语义不受影响，FAB/AppBar 等直接参数不涉及。`binary_recall_bar_test` +2 回归（widget style 与主题级 ElevatedButton 在全部 WidgetState 下 elevation==0）。`flutter analyze` 改动文件 0 issue。`flutter test --exclude-tags golden`：**1266 passed / 0 failed**。)

Previous: Generated: 2026-08-21 (测试套件全量精简与治理：删除官方 Anki 迁移 Phase 0~5 过渡性 Spike/Prep/Playbook/Rollback 临时演练用例、波次灰度用例及冲突的旧架构守卫 9 份文件；合并重复的 Projection 切片；删除 verbose_test、srs_persist_benchmark_test、enum_by_name_test 等极低价值/已淘汰机制测试；删除 iOS/macOS 空模版桩；标记 Golden 视觉测试标签并修复 AiCompanionRepository 表初始化。`flutter test --exclude-tags golden`：**1264 passed / 0 failed**；Python `test/*_test.py`：**19 passed / 0 failed**。)

Previous: Generated: 2026-08-21 (P5–P10 生产路径：Play Hub/统计/`FormalReviewLauncher.open` → `AnkiReviewSessionRoute`+`StudySessionController`；gate 不再 push Official 页；课程提交等 ledger receipt；导入 `begin` 同 hash no-op 跳过 assemble/Official；`StudyProductAnalytics` 接入 unified review。定向测试 **passed**。)

Previous: Generated: 2026-08-21 (P4 生产接线：课程提交 markIntroduced；正式复习 due ∩ introduced；导入 reps/revlog 初始化；到期数拆成已学待复习/未学新卡。`card_introduction_eligibility_test` + assembler/fidelity/lesson/migrator 定向 **passed**。)

Previous: Generated: 2026-08-20 (Anki 课程与复习大一统 P0–P5 切片：CanonicalCardKey / CardPresentation / introduction / StudySessionController；Official practice surface renderer-neutral ACK；kindsFor 一卡一种 presentation；schema v18 统一表。定向 `flutter test` 合同/守卫/DAO/ACK/adapter/projection/schema **passed**。)

Previous: Generated: 2026-08-05 (Turkish content enrichment S1–S8: CEFR outlines → template shells → grounded pool 148 words / 18 expressions / 8 grammar; no placeholders; listening+reading per section; inventory v12; `turkish_enrichment_structure_test` +5; `course_cli_test` +4 structure/lint gates. Directed: flutter enrichment+loader **34 passed**; python course_cli **11 passed**. Full suite estimate **~880**.)


Generated: 2026-08-05 (Turkish content enrichment S1–S8: CEFR outlines → template shells → grounded pool 148 words / 18 expressions / 8 grammar; no placeholders; listening+reading per section; inventory v12; `turkish_enrichment_structure_test` +5; `course_cli_test` +4 structure/lint gates. Directed: flutter enrichment+loader **34 passed**; python course_cli **11 passed**. Full suite estimate **~880**.)

Previous: Generated: 2026-08-05 (宝石装饰兑换第一步：`GemsProvider.spendGems` + `CosmeticProvider` 头像环三款（晨雾/芦苇/湖光）；设置→账户→装扮列表；Profile/账户头像 `AvatarWithRing`；导出 key + 账户重置清装扮。新增 `gems_spend_test` 4 + `cosmetic_provider_test` 6；账户设置 widget 测试补 CosmeticProvider。相关定向测试 **13 passed**。全量预计 **875** = 865+10。)

Previous: Generated: 2026-08-05 (Android 状态栏对齐：`colors.xml` + light/night/v27 styles；`TurnaTheme.systemUiOverlayFor` + 四套 AppBarTheme；`_AppShell` 随主题应用 SystemChrome；launch_background 雾色/深色 scaffold；wetland 契约 +7。`flutter test`：**865 passed / 0 failed**。)

Previous: Generated: 2026-08-05 (湿地鹤 palette polish：ADR 0033 角色边界；`primaryCtaDecoration` 挂 Splash/Check/Continue；`contrastRatio` 闸门；成就区 clay icon；完美 pill 细环；nodeGlow 用 brandReed；withOpacity→withValues；GUI secondary 深色 hover；golden failures gitignore；wetland contract 扩至 ~18 断言；renderer 测试跟进 InkWell CTA。`flutter test`：**858 passed / 0 failed**。)

Previous: Generated: 2026-08-05 (Turna「湿地鹤」ADR 0033 palette: scheme A lock `#1F727E`; delete `peacock*` aliases; clay productization on course-tree complete/perfect, profile XP accent, About brand strip, Play Hub weak-words secondary tint; GUI `BRAND_CLAY`/`BRAND_SAND` + fallbacks; play_hub light/dark goldens refreshed; new `test/views/wetland_palette_contract_test.dart` (+11). Unrelated compile fix: `ReviewRatingBar`/`ReviewEmptyState`/`ReviewCompletionState` AppStrings defaults via initializer list. `flutter analyze`: no errors. `flutter test`: **851 passed / 0 failed**. GUI `tests.test_theme`: 29 OK.)

Previous: Generated: 2026-08-01 (code-review 修复 8 项 Anki/SRS 工作树问题。(1) `anki_deck_assembler`：空 Default(id=1)+有卡子牌组+另一顶层牌组时不再丢弃 Default 致 `COUNT_RECONCILIATION_FAILED`——topLevelDecks 过滤加 `_deckTreeHasCards`（Default 或其任意子牌组有卡则保留为顶层 section，子牌组作为 descendants 被索引）。(2) wordId `-n<noteId>`->`-c<cardId>` 透视无 migration：schema v13->v14 加 `_rekeyLegacyAnkiWordIds`，用 `anki_cards_meta`(import_id,note_id)->word_id 把 `srs_states.word_id` 与 `review_events.card_id` 旧 `-n` 行重键为 `-c`；srs_states PK 冲突（pivot 后重导入）时删旧行而非碰撞。(5) `anki_review_assembler._indexLessonInteractions`：删死的 note-key 索引（`anki-<imp>-n<noteId>` 永不被 card-based 查询读）+ stale「mirror the fallback」注释 + 未用 `importId` 形参/局部。(8) `course_repository.lessonsContainingAny`：needle 加 `-c` ord 分隔符锚定，修 `c45`⊂`c450` 前缀碰撞（互动 id 恒为 `${wordId}-c${ord}` 故 `${wordId}-c` 必命中且不误匹配），doc 注释由 `-n` 改 card-level。(3) `anki_note_dao.upsertCardMetaBatch`：既有卡探针改分块 bound params（避免 5000 元素 literal IN）+ 状态 UPDATE 进同一 `batch`（`b.customStatement` bound params，单事务，null bind 为 NULL）替代 N 次 auto-commit `setCardState`。(4) `searchNotes`：删 per-row `_withState` N+1，改 `_applyStateBatch` 单分块查询（N+1->2）。(6) `anki_import_dao.getAll`：删 `_toRecord` per-row 重查 anki_imports，改单 lifecycle 批查询 + 抽 `_toRecordWithLifecycle`（typed row + 一次 lifecycle）。(7) `setDailyLimits`/`_readLimit`/`setCardState`/`clearBuriedBefore`/`flaggedCards`/`upsertCardMeta`/`_withState` 的 `_sqlLiteral` 字符串插值全改 bound params（`Variable.withString`/`withInt` + `customStatement(sql, args)`），删两处 `_sqlLiteral` 死定义。新测试：`schema_migration_test`「v13->v14 re-keys legacy note-based Anki word ids to card-level」+「v15->v14 downgrade wipes and recreates」（原 `_CourseDatabaseV14` 降级 mock 升 `_CourseDatabaseV15` 因真实 schema 已 v14，新增 `_CourseDatabaseV13`）；`anki_deck_assembler_test`「empty Default deck with card-carrying subdecks is kept (no orphaned cards)」回归。`flutter analyze`：0 error/0 warning on 改动文件（仅预存在 info：doc `<>` 与 `use_super_parameters`）。`flutter test`：800/0 green（+2）。)

Previous: Generated: 2026-07-31 (anki P0 完成度：导入预览可编辑 notetype 映射 + 样例卡预览 + 接入 AnkiNotetypeAI「AI 智能识别」按钮 + 删除 AnkiCardEnhancer 死代码。`lib/views/anki/anki_import_screen.dart` 预览步 notetype 映射卡改 `_NotetypeMappingRow`（`DropdownButtonFormField<NotetypeMappingType>` 9 项下拉覆盖 type，保留推断字段索引；override 经 `mappingOverrides` 端到端生效）+ 每行 `visibility` 预览按钮弹 `_NotetypeSampleDialog`（取该 mid 首张 note，按映射字段索引显示 front/back，`AnkiCardAdapter.stripHtmlPublic` 去标签）；预览页加「AI 智能识别」`OutlinedButton.icon`，`config.isComplete` 守卫，调 `AnkiNotetypeAI().identifyAll`，loading 态 `_isAiIdentifying`，未配置弹 `aiNotConfiguredTitle` 对话框。新增 `_mappingTypeLabel` 顶层函数 + `_PreviewField` widget。`lib/l10n/app_strings.dart` +17 串（ankiAiIdentify/Identifying/NotConfiguredMessage + 9 ankiMappingType* + ankiNotetypePreview/Fields/SampleFront/SampleBack + ankiMappingOverrideHint）。删 `lib/application/anki/anki_card_enhancer.dart`（全仓零调用、零测试、无 DI，仅 design doc §7.2 提及）。新测试 `anki_deck_assembler_test`「mappingOverrides are respected (swapped front/back field indices)」——交换 front/back 字段索引断言 MultipleChoice.prompt 从 'Question 0' 变 'Answer 0'，固化 override 端到端生效。`flutter analyze`：0 error/0 warning on 改动文件（仅 1 info `DropdownButtonFormField.value` deprecated，与既有 `textbook_import_page.dart` 用法一致，受控语义需要 value 故保留）。)

Previous: Generated: 2026-07-31 (anki deep-adaptation 阶段 1: NoteStore + card-level wordId. schema v8->v9 加 `anki_notetypes`/`anki_notes`/`anki_cards_meta` 三表 + `AnkiNoteDao`(CRUD/批次/级联删除)+ `AnkiNotetype.css` 字段。`anki_importer._parseNotetypes` 读 css;`anki_deck_assembler.assemble` 加可选 `AnkiNoteDao?` 写 NoteStore(notetypes 含 templates+css+allowJs、notes 原始 HTML、cards_meta card 级 wordId);`anki_import_screen` 传 noteDao。wordId 全链路 note 级 `n<noteId>` -> card 级 `c<cardId>`(决策 2,clean break,无 migration):`anki_srs_migrator`/`anki_card_adapter` 产出 + `importIdFromWordId`/`_extractImportId` 解析 + `detectNewNotes`/import_screen 碰撞检测改"任一 card 在 SRS 即算已导入" + 删死码 `_extractNoteId`。`anki_deck_manager.uninstallDeck` 加 NoteStore 级联删除 + 构造注入 `_noteDao`。修预存在 `anki_notetype_ai.dart` 漏分号语法错误(WIP bug)。新测试:`anki_note_dao_test`(4)、`schema_migration_test` v6->v9 + v10->v9 降级。修原红的 `anki_srs_migrator_test` revlog(wordId 格式不匹配)+ `anki_review_assembler_test`/`review_progress_provider_test` 改 c 格式。剩 1 个预存在失败:`anki_deck_assembler_test` "Front/Back"(预存在 adapter "embedded A/B/C options" WIP 改动导致,隔离测试证明与 wordId 改动无关)。)

Generated: 2026-07-29 (play_hub 半拟物彩色玻璃 + 轻微悬浮。`lib/views/play/play_hub_screen.dart` 加极光底层 `_AuroraBackground`（3 个 `RadialGradient` 光斑：左上 peacockTeal、右上 peacockCyan、底部中央 leagueAmethyst，浅深色 alpha 自动分支）+ 单层 `BackdropFilter(ImageFilter.blur(sigma 18))` + `RepaintBoundary` 隔离滚动；4 类卡片（_PlayHubCard / _FocusCard / _ReviewCell / _CountBadge）统一走新增私有 `_GlassCard` 容器，组合 4 层：基座（白霜/深色玻璃底 + 1px 描边 + 分层阴影）+ `ClipRRect` 圆角 + accent 着色渐变 + 顶部白色高光条。`PageController` 提升为 `_PlayHubScreenState` 的 `late final`，消除每次 build 重建；`PlayHubScreen` 由 `StatelessWidget` 改 `StatefulWidget`。`lib/views/theme.dart` 新增 6 个静态 helper：`glassSurface` / `glassHighlight` / `glassBorder` / `glassAccentFill` / `glassShadow` / `glassBadgeFill`，全部基于 `_isDark(context)` 自动切深浅。重新生成 `play_hub_light.png` / `play_hub_dark.png` 两个 golden 基线。无新增/删除测试。)

Previous: 2026-07-17 (tool-gui workshop2：主课程编辑器功能课向导 + 可视化蓝图 + 批量/快捷键 + 课程总览。P1 预设库 `backend/lesson_presets.py`（FUNCTIONAL_PRESETS：听力三阶段/阅读三类题/综合测验/认识新词三步/巩固练习 + `build_preset_lesson`/`apply_preset_to_lesson`）+ `clone_lesson_with_fresh_ids` + `CourseAdapter.duplicate_lesson` + 新命令 `DuplicateLessonCommand`/`BulkDelete/Duplicate/Move/ApplyPreset`；课程树 `ExtendedSelection` + `keyPressEvent`（Ctrl+D 复制 · Delete 删除 · F2 重命名 · Ctrl+↑/↓ 同级移动）+ 批量菜单（复制/移动/套用预设/删除）。P3 `widgets/lesson_blueprint.py`（LessonBlueprint 卡片流蓝图，只读预览 + 命令化就地编辑），`DetailPanel` 加「蓝图/高级编辑」切换，功能课型默认蓝图。P2 `dialogs/functional_lesson_wizard.py`（3 步向导：选类型+预设 -> 配置 -> 蓝图预览，`NewLessonDialog` 加「向导创建」入口 + 单元右键「功能课向导…」）。P4 `widgets/course_overview.py`（CourseOverviewWindow 非模态总览，Section/Unit/Lesson 芯片 + 课型 badge + 统计，点击定位）。P5 批量套用预设/批量移动。新增测试 `test_lesson_presets` 13、`test_commands_bulk` 12、`test_lesson_blueprint` 12、`test_functional_lesson_wizard` 6、`test_course_overview` 4、`test_course_tree` 增键盘+批量 7。)

Previous: 2026-07-16 (Flutter app i18n + 分层 Settings。Task 1：把 lib/ 内中文 UI 文案与 AI prompt 脚手架全部改英文（AI 回复仍按 source language；ai_prompt_builder/ai_course_service 加 "reply in source language" 指令保输出语言）。改 `interactionTypeLabel`、`ai_genre` 的 label/description/`templateLabels` 与 `genrePromptBlock`、`ai_resource_consistency` 校验信息、`ai_course_service` 异常信息与 prompt、`ai_hint_provider` 讲解 prompt。UI 文案：play_hub/ai_hint_chat/new_lesson/ai_hint_sheet/mistake_review/review_components/srs_review/grammar_review/mistake_review_assembler。Task 2：`SettingsPage` 由单页改 StatefulWidget + 页内状态导航（`_category`：null=分类列表，0..4=Account/Learning/Audio & Display/Data/About 子页），复用现有 tile 与 bottom sheet；`SettingsAppBar` 降为零高度 stub，避免双层 AppBar；不走 AutoRoute，"去设置" TabRouter 切 tab 行为不变。同步更新 `ai_genre_test`/`ai_prompt_builder_test`/`ai_hint_provider_test`/`play_hub_screen_test` 的中文断言，重新生成 play_hub light/dark golden。）

Previous: 2026-07-15 (tool-gui guiplan2 阶段 P3：结构化预览 + JSON 智能编辑 + diff。新增 `src/widgets/json_editor.py`（JsonEditor：QSyntaxHighlighter 高亮 + Ctrl+Shift+F 格式化 + 错误行红标跳转 + set_json/to_json）。`ResultPreviewWidget` 加 QTreeWidget 结构树（Section→Unit→Lesson→subLesson/stage/listeningPhase→item，点节点发 `node_activated(id)` → dialog 跳 JSON 行；`_on_validate` 后用 `error_mapper.parse_path` 把 error 标红到对应 unit/lesson 节点 + humanize_problem tooltip）。wish 模式加同款 `wish_json_edit`，`_current_json()` 改为按模式读编辑器（修 B1/C4，`_generated` 仅作恢复快照），`_on_reset` 按模式重置。新增 `src/widgets/diff_view.py`（SectionDiffView：`full_section_diff` 增删改三色树，"查看 diff" 按钮在编辑模式可见）。新增 `full_section_diff` 纯函数（复用 `_section_unit_ids` 等，added/removed/changed by json.dumps fingerprint）。`LessonPreviewDialog`/`_PreviewCard` 加可选 `vocab_override`，"试做" 按钮用生成 section 的 words 构造 override，未导入也能查译文。新增 `test_json_editor.py` 5 + `test_diff_view.py` 4 + `test_ai_generator_dialog.py` B1 回归 3。)

Previous: tool-gui guiplan2 阶段 P5：排版归一 + 主题统一。拆出 `src/dialogs/ai/` 包：`worker.py`（AiRequestWorker/_AttachmentRecord）、`chat_view.py`（ChatView + 纯渲染函数，无 PySide6 可单测）、`prompt_template_bar.py`（单一共享模板选择器，修 B8——`_build_template_selector` 原两次调用覆盖 combo/cards/genre_switch，改为单实例 + `_update_mode_ui` reparent）、`chat_expand_window.py`（真子窗口，几何存 QSettings，第二 ChatView 共享 _messages，替代 resize/hide-chrome hack）。修 wish 模式 `_current_spec` topic 取值（原读 normal-only 孤儿 topic_edit，改按模式取 last user message）。`theme.py` 加 `ai_*` palette 键 + `current_palette()`/`ai_color()`，dialog 内联 hex 全部走 `_pal()` 查询。许愿一屏化：3 段 QSplitter（chat / 折叠结果摘要 / 输入），结果默认折叠为「✓ 已生成 · N 单元 · M 课时 · K 词」，解释就绪自动展开。可访问性：Enter 发送 checkbox（默认 ON）、Tab 顺序、附件 × tooltip + Delete 提示。附带修复 P2 残留回归：`test_ai_generator_dialog.py` 三个普通模式用例的 patch 目标 `generate_from_chat` → `request_course_with_retry`。新增 `test_ai_chat_view.py` 11。全量 GUI 套件 offscreen 本机可跑。

Previous: tool-gui guiplan2 阶段 P2：校验自愈 + 局部重生成。修 C3（普通模式接通 `request_course_with_retry`，校验错自动回灌一轮）/C5（编辑模式 lesson/unit 级走局部重生成 `regenerate_lesson_in_section`/`regenerate_unit_in_section`，只重发该子树）/B5（retry validator 适配 Problem dict，`_coerce_problem_messages` 取 .message、过滤 warning）/B3（`structural_diff` + 删除确认弹框）/B4（`_auto_fix_resources` stub 译文回退 `[待补]` + `needs-review` tag）。新增 `Settings.ai_retry_max`（0-5，默认 1）+ `current_settings()` helper。新增 16 个后端测试）

Previous: tool-gui guiplan2 阶段 P1：AI 流式生成 + 真正可中断取消 + token/成本可见。新增 `ai_stream.py`（SSE 解析）/`ai_usage.py`（token 估算+价目表）；`request_chat` 增加 stream/on_chunk/usage_callback 参数，所有生成路径透传；`AiRequestWorker` 新增 chunk_ready/usage_ready 信号并自动注入回调；dialog 修复 B2（wish 解释阶段 worker 接线）/B6（流式取消行读取前轮询）/B7（_request_start 每轮重置、完成清 None，duration 安全 helper）；新增 usage_label 用量行；阶段文案语义化（生成中流式/校验中/解释中）。修 C1/C2

Previous: tool-gui Phase 1+2+3+4：稳定层加固 + 教师视图覆盖全部 6 种模板 + AI 改写与易用性提升 + 稳定性加固。Phase 1：backend/api.py 隔离 CLI 内部函数、CourseAdapter 原子保存/备份/回滚、CSV None 容错、全局异常处理与日志。Phase 2：SubLessonFlowWidget 模板感知视图、intro/practice/review 一键生成助手、lesson_content 统一生成函数与测试。Phase 3：教师视图接入 AI 一键生成/改写/扩展题目；新增撤销/重做、sub-lesson 拖拽排序、实时预览。Phase 4：修复 widget 生命周期隐患、listening/reading/mastery 教师视图全面走 undo stack、wizard/AI 导入资源可撤销、AI API 配置持久化、异常不再静默吞掉

## Results
- `flutter test`: **798 passed / 0 failed** - anki deep-adaptation 阶段 1-6 + P0
  (NoteStore + card-level wordId + fidelity HTML pipeline + WebView shell +
  AnkiRenderPolicy + review-session fidelity rendering + Lite mode + weak-word /
  daily-challenge glue + dark CSS + 智能去解密 pre-render cache + editable
  notetype mapping + AnkiNotetypeAI wiring + AnkiCardEnhancer dead-code removal)
  + 智能 TTS 自动语言检测 (LanguageDetector + per-course auto-read toggle +
  native-language fallback; Anki 卡片首次接入 TTS).
  The 2 historically env-sensitive tests (`anki_review_fidelity_test` calls
  `getApplicationDocumentsDirectory` via `StreamingSharedPreferences` with no
  path_provider mock; one `anki_note_dao_test` case flakes on concurrent
  `ensureSqliteLibForTestHost`) **passed in this run** but may still flake in
  other environments. P0 added 1 regression test (`mappingOverrides are
  respected`). 智能 TTS 轮新增 `language_detector_test` (29) +
  `settings_per_course_test` (7)，0 新失败。
- `flutter analyze`: 0 new warnings/errors on changed files
  (`lib/views/play/play_hub_screen.dart`, `lib/views/theme.dart`); pre-existing
  info-level lint in unrelated test files is untouched
- Python:
  - `python3 -m unittest discover -s test -p "*_cli_test.py"` — 7 passed
  - `tool/gui` suite (from repo root: `python3 -m unittest discover -s tool/gui/tests -p "test_*.py"`) — **804 passed** (workshop2：功能课向导+蓝图+总览+批量/快捷键；新增 test_lesson_presets/test_commands_bulk/test_lesson_blueprint/test_functional_lesson_wizard/test_course_overview + test_course_tree 键盘与批量用例)。全量 GUI 套件 offscreen 本机可跑（~39s）。
- `tool/course_cli.py --course-dir assets/courses/turkish validate` passes

## This round (2026-07-31, AI 导师 4 项改动)
1. **Prompt 中性化** (`lib/application/ai/ai_hint_provider.dart`): `_buildSystemPrompt` 与
   4 个深度讲解 genre 的 systemPrompt 由「a ${language} X tutor」改为通用「language-learning
   tutor; the learner is practicing ${language}」，目标语言仅作上下文而非身份，不再限于土耳其语；
   按用户选择保留「Reply in Chinese throughout / in plain Chinese」(匹配当前中文界面)。
2. **卡片化 UI 统一** (新 `lib/views/ai/components/ai_sheet_widgets.dart`): 抽出 `AiGroupCard` /
   `AiSurfaceCard` / `aiSheetInputDecoration` / `aiSheetPrimaryButtonStyle` /
   `aiSheetSecondaryButtonStyle`(提取自 `AiApiConfigSheet` 的 `_groupCard`/`_fieldDecoration`
   设计语言)。应用到 `ai_hint_sheet.dart` / `ai_depth_tutor_sheet.dart` / `ai_hint_chat_page.dart`
   (正文/加载/错误入卡片 + 双钮统一 + 输入栏 + `IconButton.filled` 发送钮)。
3. **AI key 持久化** (`ai_engine_config.dart` + `_holder.dart` + `locator.dart` + `main.dart`):
   `AiEngineConfig` 加 `toJson`/`fromJson`; `LocalStateKeys.aiEngineConfig` JSON 键;
   `AiEngineConfigHolder.loadPersisted()` (启动 postFrame 调用) + `updateConfig` 写回 (经 raw
   `StreamingSharedPreferences` 绕过 `printBefore` 避免密钥入日志; `getIt.isRegistered` 守卫使
   测试环境降级为纯内存)。`settingsAiApiConfigNotSaved` 文案与 sheet header 图标 (lock -> save) 同步。
4. **DeepSeek 默认 `deepseek-v4-flash`** (`ai_provider_preset.dart`): defaultModel
   `deepseek-v4-pro`->`deepseek-v4-flash`, supportedModels 置顶 flash; `settingsModelHint` 同步;
   `ai_engine_config_test.dart` 3 处断言更新。Python GUI (`tool/gui`) 不在范围内。

## This round (2026-08-01, 智能 TTS 自动语言检测 + Anki 卡片朗读 + 每课程自动朗读开关)
1. **LanguageDetector** (新 `lib/core/language_detector.dart`，纯逻辑): 按脚本检测返回
   BCP-47 基础码——Han->zh / Kana->ja / Hangul->ko / Cyrillic->ru / Arabic->ar /
   Thai->th / Devanagari->hi / Greek->el / Hebrew->he；含土耳其特有字符
   (ğ ı ş İ，注意 ç ö ü 不算因法德共用)->target；纯 Latin->per-course native 回退。
   `inferOptionLanguage`/`detectOption` 用 prompt 方向推断 MCQ 选项语言（解决 "merhaba"
   这类无变音符土耳其词的歧义）；`detectCardPair` 用 Anki 正反面之一的土耳其信号推断
   另一面。新 `lib/core/html_stripper.dart` (Anki HTML 卡片朗读前去标签) +
   `lib/application/smart_speech.dart` (`currentSpeechLanguages`/`detectSpeakLanguage`/
   `autoReadOnTapForActiveCourse`，getIt + 失败回退 tr/en，测试零依赖)。
2. **AudioController** (`lib/application/audio_controller.dart`): `speak`/`speakWithResult`/
   `_speakWithSystemTts`/`_ensureSystemTtsReady` 加可选 `{String? languageCode}`——
   null 用 target（保持原行为，`audio_controller_tts_engine_test` 的 `speak('Merhaba')`
   ->tr 断言不变）；非 null 用该语言，`resolveLanguageCode` 返回 null 时回退 target。
   不新增公共方法（`FakeAudioController implements AudioController` 只需加参数）。
3. **每课程设置** (`settings_provider.dart` + `locator.dart` `LocalStateKeys`):
   `autoReadOnTapFor(scope)` (默认 true) / `nativeLanguageCodeFor(scope)` (默认 'en')，
   key 编码 courseScope（'' -> 'builtin'），仿 `AnkiDeckManager._deckDoneKey` 模式。
4. **接线**: MCQ 选项 tap（`multiple_choice_renderer.dart`，受 toggle 控制按推断语言朗读）；
   Anki 翻牌（`anki_card_renderer.dart` plain + `anki_html_card_renderer.dart` HTML，
   卡片出现读正面、翻开读背面（受 toggle 控制）+ 每面手动 `record_voice_over` 朗读钮）；
   词典自由文本（`dictionary_page.dart` -> `detectSpeakLanguage`）。已知目标语调用点
   (vocab term / 听力 transcript / ShowWord / SRS term) 走 `speak` (target) 不变。
5. **UI**: `course_management_page.dart` 每课程行加齿轮 -> 底部 sheet（自动朗读 Switch +
   翻译/母语语言 Dropdown 14 项）。`app_strings.dart` +6 串。
6. 测试: `language_detector_test` (29) + `settings_per_course_test` (7)；6 个 AudioController
   fake 加 `{String? languageCode}` 参数。`flutter analyze` 0 error。全量 794/0。

## This round (2026-08-01, code-review batch 1: 5 correctness/perf fixes)
Addressed 5 of the 9 code-review findings on the Anki/FSRS working tree. Batch 1
of 2; the two import-perf fixes and the undo-race fix follow in batch 2 (with
tests).
1. **searchNotes LIKE escaping** (`lib/data/anki_note_dao.dart`): the pattern
   backslash-escaped `%`/`_` but drift 2.21's `like()` emits no `ESCAPE` clause,
   so the escaping was inert and literal-`%` searches returned nothing. Added a
   small `_LikeWithEscape extends Expression<bool>` that emits
   `col LIKE ? ESCAPE '\'` with the pattern bound as a SQL variable (no
   injection); also escapes the backslash itself. New regression test
   "searchNotes treats % and _ in the query as literals, not wildcards".
2. **hasScheduling always true** (`anki_deck_assembler.dart`): dropped the
   `|| collectionCreationTime != 0` disjunct (col.crt is non-zero for every
   real collection, so the flag was always true). Now reflects whether any card
   actually has scheduling.
3. **Media-tag video/source misrouting** (`anki_card_adapter.dart`): a
   `<source>` inside `<video>` was classified as audio when an unrelated
   `<audio>` appeared earlier in the field. Replaced the fragile
   `contains('<audio')` with a nearest-container comparison
   (`lastIndexOf('<audio')` vs `lastIndexOf('<video')`).
4. **schedulerVersion dead data** (`anki_models.dart` + `anki_importer.dart`):
   `col.ver` is the DB schema version, not the scheduler version, and the field
   had no consumers. Dropped it (`anki_models.freezed.dart` regenerated via
   build_runner).
5. **Prerendered-face fire-and-forget** (`anki_html_card_renderer.dart`):
   `upsertPrerenderedFace` was called with no await, swallowing DB errors. Made
   the `onCaptured` callback async with a try/catch + `debugPrint`. (The
   non-atomic upsert race in the DAO is deferred to batch 2.)
`flutter analyze`: 0 errors on changed files (144 pre-existing info/warning
lints untouched). Suite 794 -> 795.

## This round (2026-08-01, code-review batch 2: perf + concurrency fixes)
Addressed the remaining 4 code-review findings (the two import-perf fixes, the
undo race, and the atomic prerendered upsert). All with regression tests. No
generated code touched this round (no `@freezed`/`@JsonSerializable` changes).
1. **copyMedia out of the import transaction** (`anki_import_screen.dart`):
   `AnkiAudioResolver().copyMedia` (file I/O for every audio/image) ran inside
   `database.transaction`, holding the SQLite write lock across the whole copy
   and blocking every other DB write in the app. Moved it before the
   transaction opens (copyMedia is best-effort; a catastrophic failure throws
   before the txn opens, so rollback semantics are unchanged). New
   `ankiCopyingMedia` l10n string for the progress message.
2. **N+1 cardMetaByWordId in assembleBatchAsync** (`anki_review_assembler.dart`
   + `anki_note_dao.dart`): the deck-subtree filter looped
   `cardMetaByWordId(word.wordId)` per due candidate before `_sliceDueBatch`
   capped the batch at 20 - a 500-due-card import issued 500 sequential reads
   every time a review session opened. Added `wordIdsForDecks` (one batched
   query, chunked to stay under SQLite's variable limit) + in-memory set
   membership. Regression test `wordIdsForDecks returns word ids for cards in
   the given decks only`.
3. **undoReview vs in-flight reviewItem race** (`srs_queue_provider.dart`):
   the UI enables Undo as soon as a grade is submitted (before reviewItem
   writes); an undo fired during the fail-path `countFailsOnLocalDay` await
   was overwritten when reviewItem resumed. Added a `_gradesInFlight` set -
   `reviewItem` marks the id in-flight (try/finally), `undoReview` returns
   false while it is (the caller leaves the undo entry and retries once the
   grade completes). Body extracted to `_doReviewItem`. Regression test uses a
   `Completer`-controlled fake `ReviewHistoryDao` to assert undo is refused
   mid-grade and succeeds after.
4. **Atomic upsertPrerenderedFace** (`anki_note_dao.dart`): the read-then-write
   (`Value(front ?? existing?.frontHtml)`) let concurrent front/back captures
   clobber each other (frontHtml written as null). Switched to `Value.absent()`
   for the uncaptured face so `insertOnConflictUpdate` is a single atomic
   statement that only sets the captured face. Regression test asserts the
   other face survives in both capture orders.
`flutter analyze`: 0 errors on changed files. Suite 795 -> 798.

## Notes
- 2026-07-28 Anki smart organization + SRS SQLite (memory-curve round):
  - **SRS state prefs→SQLite (schema v6→v7 part 1)**: new `SrsStates` table
    (wordId PK, queue, dueAt, intervalDays, ease, reps, lapses, isLeech, type,
    lastReviewedAt). `SrsStateDao` (lazySingleton) load/upsert/upsertBatch/delete/
    deleteByPrefix/clearQueue. `SrsQueueProvider` rewritten to a synchronous
    in-memory cache hydrated from SQLite via `ensureLoaded()` + write-through
    persist, preserving all sync consumers (`state`, `dueCount`, `getDueWords`).
    Self-migration in `ensureLoaded()` parses the old prefs blob once, backfills
    the DB, sets `srs.migratedToSqlite.$queueId` flag, then never reads prefs again.
    `SrsWord` gained `lastReviewedAt` (powers forgetting curve without a DB join).
  - **Review history + accuracy fix (schema v7 part 2)**: new `ReviewEvents`
    table (autoincrement, cardId, queue, reviewedAt, quality, prev/next
    intervalDays, prev/nextEase, reps, lapses, type) with `@TableIndex` on
    cardId + reviewedAt. `ReviewHistoryDao` (lazySingleton) insertEvent/
    insertBatch/eventsForCard/recentEvents/allEvents/count/deleteByCardPrefix.
    `reviewItem` now writes a `ReviewEventRecord`. Lazy GetIt resolution
    (`GetIt.instance<ReviewHistoryDao>()` + `@visibleForTesting` setter) avoids
    re-churning ~25 test call sites. Fixed SRS review screen accuracy bug:
    `_grantSessionRewards` now passes real correct/incorrect counts instead of
    `correctCount: reviewedCount, incorrectCount: 0`.
  - **Memory curve model + visualization**: `MemoryCurveProvider.snapshot()`
    computes currentRetention (mean R=exp(-Δt/S) over reviewed cards), forecast
    (dueToday/7Days/30Days), maturity (new/young/mature/leech), and an empirical
    retention-by-interval curve (recall rate bucketed by prevIntervalDays into
    [1,4,7,14,21,30,60,90,180]). `learning_stats.dart` gained a `_MemoryCurveCard`
    (fl_chart LineChart + forecast mini-stats + maturity chips). MemoryCurveProvider
    is optional in the widget tree (try/catch on `context.read`).
  - **Anki smart organization**: `AnkiOrganizationResolver` extracts unit/lesson
    keys from notetype field names (unit/chapter/section/单元/章;
    lesson/topic/subunit/课/节) then tags (unit::/unit:/chapter::/chapter:/
    单元::/单元:; lesson::/lesson:/课::/课:); field takes priority, HTML stripped.
    `anki_deck_assembler.assemble(smartGrouping:)` groups cards into Units→Lessons
    by those keys (deck name fallback); multi-chunk (>20) lessons named
    `"$lessonKey #N"`. Zero-metadata path is byte-identical to the old chunking.
    Import screen shows an organization preview + smart-grouping switch.
  - **Anki revlog parse + migrate**: `AnkiRevlogEntry` model; `_parseRevlog`
    (paginated, table-missing-safe, best-effort) added to `AnkiImporter`.
    `AnkiSrsMigrator.migrate()` now takes `revlog` + optional `ReviewHistoryDao`
    and backfills `ReviewEventRecord`s (revlog ease 1→1/2→3/3→4/4→5).
  - New tests: srs_state_dao (8), review_history_dao (9),
    memory_curve_provider (5), anki_organization_resolver (10); updated
    srs_provider / grammar_review / srs_review_flow / anki_srs_migrator /
    anki_deck_assembler / sm2 / schema_migration / provider_identity / golden /
    learning_stats. Suite went 484 → 528 all pass.
- 2026-07-28 Test-suite repair (pre-existing failures, independent of the
  5-fix code-review round): widget tests that pump `MaterialApp` forgot to
  add `localizationsDelegates`/`supportedLocales` after the 07-16 i18n round,
  so every l10n widget threw `Null check operator` and rendered an error
  widget. Added delegates to `renderer_test_helper`, `course_tree_test`,
  `content_update_dialog_test`, `dark_mode_text_contrast_test`,
  `learning_stats_*_test`, `lesson_dialogs_test`, and the `play_hub` +
  `dictionary` golden tests. Other fixes: deleted obsolete `widget_test`
  (`MyApp`) and `course_database_pos_test` (`WordEntry.pos` was removed);
  added `getAnkiActivityCounts` to `FakeStudyStatsProvider`; updated
  `lesson_dialogs_test` for localized celebration titles / `CONTINUE` /
  `2m 5s`; dropped the stale `_$` freezed-impl assertion in
  `renderer_lookup_test`; fixed `schema_migration_test` (v1-v4 now create a
  pre-v6 `sections` table without `level` so the v6 `addColumn` is meaningful;
  the downgrade test uses a hypothetical v7); regenerated the 8 golden
  baselines on the OHos Flutter 3.35 fork. Suite went 418 pass / 63 fail ->
  484 all pass.
- 2026-07-20 Settings refactor — neurodiversity accessibility + hierarchy + About:
  - New `AccessibilityProvider` (`lib/application/accessibility_provider.dart`) with 5
    persisted flags: textScale (100–200%), reducedMotion, highContrast,
    sensoryReduce, focusMode. Keys added to `LocalStateKeys`.
  - `lib/views/app.dart` rewired: single `_AppShell` watches ThemeProvider +
    AccessibilityProvider, picks light/dark/high-contrast theme variants, and
    injects a root `MediaQuery` override (textScaler + disableAnimations/
    accessibleNavigation when reducedMotion).
  - `lib/views/theme.dart` added `highContrastLightTheme` / `highContrastDarkTheme`
    getters (copyWith of the base themes: pure black/white surfaces, stronger borders,
    max-contrast text).
  - `AudioController` gained an `AccessibilityProvider` dependency; `_playSound` and
    `_triggerHaptic` early-return when `quietFeedback` (sensoryReduce) is on.
  - Settings hierarchy expanded 5 → 7 categories: Account / Learning (trimmed to
    language+TTS+reminder) / Audio & Haptics (sound+haptic+TTS engine) / Accessibility
    (6 tiles + theme selector) / AI Tools (API config + design chat + textbook
    import) / Data / About. New tiles in
    `lib/views/settings/widgets/settings_accessibility_section.dart`.
  - About page gained Privacy & local-first section, Version & changelog card
    (expandable, hard-coded milestones + PackageInfo), and a "View releases" link;
    credits now note the local-first fork; copyright footer uses `© <year> Turna`.
  - Focus mode gates the `MalaWelcomes` rotating image timer (splash screen).
  - Test wiring: 7 test files that subclass `AudioController` updated to pass the new
    `AccessibilityProvider` positional arg and register it in `getIt`/setUp. New
    `test/application/accessibility_provider_test.dart` (6 tests). `injection.config.dart`
    regenerated via build_runner. 445 → 451.
- `tool/gui` Phase 4 稳定性加固（方案 A）：
  - 修复 widget 生命周期：`DetailPanel.clear_content()` 与
    `TeacherTemplateWidget._clear_content()` 缓存 `widget = child.widget()`，
    避免 `setParent(None)` 后二次调用返回 `None` 导致的崩溃。
  - 撤销栈覆盖补齐：`ListeningTeacherWidget` / `ReadingTeacherWidget` /
    `MasteryTeacherWidget` 中的题目 add/delete/move/change-type/AI-rewrite 全部
    走 `AddItemCommand` / `DeleteItemCommand` / `MoveItemCommand` /
    `ReplaceItemCommand`；听力阶段 add/delete/rename/move 使用新增的
    `AddListeningPhaseCommand` / `DeleteListeningPhaseCommand` /
    `MoveListeningPhaseCommand` / `RenameListeningPhaseCommand`。
  - Wizard 与 AI 导入纳入 undo：`AppendLessonCommand` 让向导建课可撤销；
    `ImportAiSectionCommand` / `AiEditSectionCommand` / `AiEditUnitCommand` /
    `AiEditLessonCommand` 把 `merge_section_resources()` 收进 redo，undo 时
    精确回滚本次新增的词/表达/语法资源。
  - AI API 配置持久化：`MainWindow` 启动时从 `QSettings` 加载，关闭 AI 对话框
    后写回；配置对象在内存中原地更新，保证教师视图共享同一份设置。
  - 异常不再静默吞掉：`CourseAdapter.notify_resources_changed()` 和
    `DetailPanel._on_resources_changed()` 用 `logging.exception` 记录错误，
    保留容错但保留诊断信息。
- `tool/gui` Phase 3 创造性 + 易用性提升：
  - AI 改写助手接入教师视图：`SubLessonFlowWidget` 顶部「🤖 AI 改写本课」可基于
    教师指令改写整门 lesson；Listening/Reading/Mastery 模板编辑器顶部共用
    「🤖 AI 改写」；每道题目卡片右上角「🤖」支持单题改写/扩展。AI 输出保留
    id/template 并通过 `api.validate_lesson` / `lesson_content.normalize_item`
    校验，结果以 `AiEditLessonCommand` / `ReplaceItemCommand` 压入统一撤销栈。
  - 撤销/Redo 补全：新增 `Add/Delete/Rename/Move` 命令覆盖 sub-lesson、stage、
    item，以及 `ReplaceItemCommand`，教师视图所有增删改移动均走 `QUndoStack`。
  - 拖拽排序：`LinearFlowWidget` 安装 `_DragDropFilter`，支持拖拽 sub-lesson
    header 重新排序（sub-lesson → sub-lesson），通过 `_handle_drop` 计算目标
    索引并压入 `MoveSubLessonCommand`。
  - 实时预览：`SubLessonFlowWidget` 增加「👁 实时预览」开关，折叠显示当前 lesson
    所有题目的 `_PreviewCard`，内容变更时自动刷新。
- `tool/gui` Phase 2 教师视图覆盖全部 6 种 canonical 模板：intro/practice/review 不再混用
  通用 LinearFlowWidget，改由 `SubLessonFlowWidget` 显示模板标签并支持一键生成助手
  （intro：从词库生成认识课；practice：选择词汇+题型组合批量生成练习；review：从词库
  生成复习）。listening/reading/mastery 保持原有专用编辑器。生成逻辑统一迁移到
  `tool/gui/src/backend/lesson_content.py` 并新增单元测试。
- App 内 AI 课程功能已与 Python GUI 端（`tool/gui/src/backend/ai_generator.py` +
  `ai_genre.py`）对齐：完整模板/题型/资源 schema prompt、genre 标签批量、
  资源自洽校验与 autoFix、`validateSection` + 1 次自愈重试、许愿模式（独立聊天页
  `AiWishChatPage` 多轮对齐 + 滑动确认条「Swipe to finalize」生成 + 通俗解释）。
  入口已从 Learn 右下 FAB 迁到 `StatAppBar` 右上 `auto_awesome` 图标直进聊天页（后已移除，现入口为 设置 > AI 工具 / 练习 Hub），
  课程参数移到页面 AppBar 齿轮按钮的底部弹层；普通模式/编辑模式与可编辑 JSON 已移除
  （`AiCourseGeneratorPage` 删除）；API 配置移到 Settings 页 AI 区块。不含编辑模式。
- 资源持久化：AI 生成的顶层 `words` / `expressions` / `grammarPoints` 现随 section
  一并写入 `CourseDatabase` 的 `vocabulary` / `expressions` / `grammarPoints` 表
  （`insertOnConflictUpdate`，已存在 id 跳过），与 DatabaseSeeder 合并语义一致。
- 模块化重构：`lib/application/ai/` 子目录承载 `AiApiConfig` / `AiCourseSpec` /
  `ai_genre` / `ai_prompt_builder` / `ai_resource_consistency` /
  `ai_course_service` / `ai_course_provider` / `ai_wish_provider`。原
  `lib/application/ai_course_*.dart` 已删除。
- 新增 24 个核心逻辑单测：`test/application/ai/`（genre 解析、prompt 构建、资源自洽/
  autoFix、parseCompletion + retry Mock HTTP）。
- 许愿模式本轮不支持附件（图片/PDF/Word），仅纯文本多轮对齐。
- Turkish course (`assets/courses/turkish/`) now ships **8 sections** with the
  CEFR progression A1/A1/A1/A2/B1/B1/B2/B2, wired with inter-section
  prerequisites. Section 1 ships a real **intro greetings lesson** (`s1-l2`,
  template `intro`, 3 subLessons: meet words / choose / practice) backed by
  8 vocab words + 2 expressions. Sections 2–8 are metadata-only placeholders
  (1 unit / 1 legacy MCQ lesson each, no vocab refs); full content authoring
  is a future round.
- Grammar points intentionally empty (`grammar_points.json`); this keeps a
  legitimately-empty table for the seeder-idempotent "empty table ≠ reseed"
  regression path.
- `seeder_idempotent_test.dart` asserts vocab + expressions are non-empty
  (real content) while grammar is empty; `course_cli_test.py` asserts the
  vocab CSV has a header + data rows (e.g. `w-merhaba`).
- Piper Swahili TTS + `sherpa_onnx` removed; TTS is system/Google `'tr'` only.

## Previous baselines
- 错题复习 + 二按钮复习 + SM-2 调优 = 411 (all pass); AI align with GUI = 409 (404 non-golden pass; 8 golden env-diff); MiniMax migration = 385; Pre-pivot = 373; Phase 24 = 372; Phase 23 = 358; Phase 22 = 350; Phase 21 = 342.
