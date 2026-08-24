# Anki 双栈修复计划（按紧急度分批）

## P0 · 发布链路堵洞（cutover 已默认开，这些是线上事故级）
1. **让发版产物包含官方核心**：`tool/build_release.py` 接入 `native/turna_anki_core/build-android/build.sh`（或 CI 产出 `.so` 后由发版脚本消费），并加"flags 默认开 ⇒ APK 内必须存在 `libturna_anki.so`"的断言；短期兜底：运行时探测库缺失时把 official 路由降级并明确上报，而不是 fail-closed 白屏。
2. **补丁正式化**：为 `clear_study_queues`、`encode_iri_paths` 两处脏改各写 `patches/0002/0003-*.patch`，`build.sh` 与 `verify_pin.sh` 应用并校验全部补丁，`build.rs` 增加"子模块工作区必须干净"检查；提交子模块当前状态。
3. **修 CI**：`official_anki-host` job 改为显式安装/引导 protoc，不再依赖被 gitignore 的本地路径。

## P1 · 高危 bug（用户可见的数据/行为错误）
4. FFI 错误码映射补全 31 项（`officialAnkiErrorCodeFromStatus`），并加一个对照 Rust 常量的单测防再漂移。
5. 老栈：修 `searchNotes` 分页（过滤后分页 + 正确窗口）、`_undoQuota` 的 `wasNewCard`、cloze 适配用 `clozeOrd`、`sessionItemId` 加 sourceId、`deleteByImport` 补删三张表。
6. 解密捕获缓存：把 2 秒定时改为内容就绪信号（或至少捕获后校验 + 失败不落缓存 + 不吞异常）。
7. `OfficialAnkiSession._rpc` 加超时；Rust `reclaim_other_open_holders` 增加 busy/liveness 检查（或先在 Dart 侧收敛句柄创建点）。

## P2 · 屎山清理与防回归
8. 删除 `lib/application/anki_official/spike/`（死代码 + 重复 FFI 绑定）；把 `official_anki_internal_page.dart` 的 fixture 直写生产表逻辑移入 dev-only 工具。
9. `unified_anki_import_orchestrator` 的持久化改为单事务批量写入，`catch(_)` 至少记日志并如实上报计数。
10. 卸载 saga 两份实现合并为一个；给 `AnkiDeckManager` 配额、`StudySessionController.undoLast` 相位矩阵、uninstall 表清理补测试。
11. 错误页 l10n：25 个硬编码中文 messageKey 迁入 `AppStrings`，未命中分支显示通用文案。
12. **卫生/法务**：移除 `anki-decryptBack/` 嵌套仓库与 `anki_decrypt_apkg.py` 中的明文密钥（含 git 历史清理评估，历史重写需另行确认）。

每批完成后跑 `flutter test`（当前基线 1628 passed / 4 pre-existing failures，以不新增失败为准），Rust 侧跑 `build-android/host-test.sh`。