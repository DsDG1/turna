import 'dart:convert';
import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart'
    show OfficialAnkiAttemptPhase;
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_card_index.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_rebuilder.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

/// v2 提交链的结果（与 v1 的投影结果形状对齐，供向导汇总）。
class OfficialAnkiV2CommitResult {
  const OfficialAnkiV2CommitResult({
    required this.sourceId,
    required this.attemptId,
    required this.cardCount,
    required this.sectionCount,
    required this.lessonCount,
    this.newNoteCount = 0,
    this.duplicateNoteCount = 0,
    this.partCount = 0,
    this.includeMedia = true,
  });

  final String sourceId;
  final String attemptId;
  final int cardCount;
  final int sectionCount;
  final int lessonCount;
  final int newNoteCount;
  final int duplicateNoteCount;
  final int partCount;
  final bool includeMedia;
}

/// v2 导入链的发布段（step4.md B1+B2）：staging/preview 与 v1 共用
/// （saga.startStaging 只写 sources/attempts 两张账本表），提交段整体
/// 由本服务接管——
///
/// 1. 幂等打开 live 引擎（Step 1 修复语义）→ `importPackage`；
/// 2. **receipt 即刻吸收进 attempt 行**（单条 UPDATE，K2 无 receipt 窗口
///    压到最小）；
/// 3. 卡索引只写 `anki_source_cards`（所有权清单，B5 删除原语的输入）；
/// 4. **映射晋升进配置区**（`turna.import.mapping.<sourceId>`，op 42 单
///    事务）+ attempt 状态推进——两步各自幂等（K10），同值重放 no-op；
/// 5. 牌组→课程放置决策进配置区（`turna.course.placement.<deckId>`）；
/// 6. attempt→completed、source→active（CAS，各自幂等）；
/// 7. 视图重建（B3）——课程树从视图长出来。
///
/// 零写入不变式（守卫测试锁死）：本链对 catalog 其余 13 张表、course.db
/// 全部旧 anki 表零写入。
class OfficialAnkiV2ImportService {
  OfficialAnkiV2ImportService({
    required this.catalog,
    required this.paths,
    required this.course,
    this.engine,
    this.nowMillis,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;
  final CourseDatabase course;
  final OfficialAnkiEngine? engine;
  final int Function()? nowMillis;

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// staging 目录回收（与 v1 finishCommit 同语义，v2 复用）。
  Future<void> finishCommit({
    required String sourceId,
    required String attemptId,
    required bool published,
  }) async {
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final attempt = attempts.find(attemptId);
    final stagingRoot =
        attempt?.stagingPath == null ? null : Directory(attempt!.stagingPath!);
    // A1：先销毁 staging session——worker isolate 仍持有
    // collection.anki2 句柄，留着它既泄漏 isolate，也让 Windows
    // 上的目录删除必败。此前只有 abandon/cancel 路径会 kill。
    // kill 是幂等 no-op，无条件跑（attempt 缺 stagingPath 时同样收）。
    await OfficialAnkiStagingManager(livePaths: paths).kill();
    if (stagingRoot != null) {
      await OfficialAnkiStagingManager.deleteDirectory(stagingRoot);
    }
    if (!published) return;
    attempts.setPhase(
      attemptId: attemptId,
      phase: OfficialAnkiAttemptPhase.completed,
      nowMillis: _now,
    );
    try {
      attempts.transition(
        attemptId: attemptId,
        expectedState:
            attempt?.state ?? OfficialAnkiSourceState.previewReady.wire,
        nextState: OfficialAnkiSourceState.completed.wire,
        nowMillis: _now,
      );
    } catch (suppressed) {
      officialAnkiV2Log('complete attempt: $suppressed', warning: true);
    }
    final sources = OfficialAnkiSourceDao(catalog);
    final source = sources.findById(sourceId);
    if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
      try {
        sources.transitionSource(
          sourceId: sourceId,
          expectedState: source.state,
          nextState: OfficialAnkiSourceState.active.wire,
          nowMillis: _now,
          importedAtMillis: _now,
        );
      } catch (suppressed) {
        officialAnkiV2Log('activate source: $suppressed', warning: true);
      }
    }
  }

  /// v2 发布链主入口。重复提交同值幂等（已 active 的 source 直接按账本
  /// 重建视图并返回）。
  Future<OfficialAnkiV2CommitResult> commit({
    required String sourceId,
    required String packagePath,
    required String displayName,
    Map<int, OfficialAnkiMappingSuggestion> suggestions = const {},
    Set<int> confirmedNotetypes = const {},
    Set<int> skippedNotetypes = const {},
    Set<int> excludedDeckIds = const {},
    bool includeMedia = true,
  }) async {
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);

    final source = sources.findById(sourceId);
    if (source == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'v2_commit_unknown_source',
      );
    }
    // 已完成的 source：幂等重放 = 只重建该 source 的视图（守恒：
    // 不重复导入）。
    if (source.state == OfficialAnkiSourceState.active.wire && source.isV2) {
      final rebuilt = await _rebuild(sourceId: sourceId);
      return OfficialAnkiV2CommitResult(
        sourceId: sourceId,
        attemptId: sourceId,
        cardCount: sources.cardCount(sourceId),
        sectionCount: rebuilt.sectionCount,
        lessonCount: rebuilt.lessonCount,
      );
    }

    final attempt = attempts.unfinishedBySource(sourceId);
    if (attempt == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'commit_without_preview',
      );
    }

    var resolved = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolved == null) {
      await OfficialAnkiCompositionRoot.requireImporter();
      resolved = OfficialAnkiCompositionRoot.engine;
    }
    if (resolved == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
      );
    }

    // 链路标记先行：此后任何一段强杀，重启 census 都按 v2 续跑。
    sources.markChainV2(sourceId: sourceId, nowMillis: _now);

    attempts.setPhase(
      attemptId: attempt.attemptId,
      phase: OfficialAnkiAttemptPhase.committing,
      nowMillis: _now,
    );

    officialAnkiV2Log('commit window open: $sourceId');
    OfficialAnkiImportLog imported;
    try {
      // 幂等打开（Step 1 语义）：冷启动直奔向导时 live 引擎可能未开。
      await resolved.openProfile(paths);
      imported = await _importLive(
        resolved: resolved,
        attempts: attempts,
        sourceId: sourceId,
        packagePath: packagePath,
        includeMedia: includeMedia,
      );
      // K2：receipt 与 import 返回之间只有这一条 UPDATE，杀点即回滚到
      // importing 状态、staging 目录仍在（finishCommit 未执行）。
      attempts.absorbReceipt(
        attemptId: attempt.attemptId,
        noteIds: imported.associatedNoteIds,
        nowMillis: _now,
        scopeJson: jsonEncode({'displayName': displayName}),
      );
    } catch (error) {
      attempts.setPhase(
        attemptId: attempt.attemptId,
        phase: OfficialAnkiAttemptPhase.quarantined,
        nowMillis: _now,
      );
      // commit 失败后 staging 目录保留给重启恢复，但 session 已无用——
      // 立刻销毁 isolate，别等下次导入或重启才回收。
      await OfficialAnkiStagingManager(livePaths: paths).kill();
      officialAnkiV2Log('commit failed: $error', warning: true);
      rethrow;
    }

    // 卡索引：只写 anki_source_cards（B2 五表之一）。ADR 0044 R1.5：整段
    // （receipt 读取 + 每 200 卡一页的引擎读 + 每卡一行同步 sqlite 写）
    // 下沉 worker isolate，与 v1 commitReceipt 同款；测试注入引擎 / 假
    // session 走 inline 同序列（强杀恢复阶段两路完全一致）。
    final session = OfficialAnkiCompositionRoot.session;
    int indexedCards;
    if (engine == null &&
        OfficialAnkiCompositionRoot.debugEngineOverride == null &&
        session is OfficialAnkiSession &&
        OfficialAnkiCompositionRoot.executionMode ==
            OfficialAnkiExecutionMode.worker) {
      indexedCards = await session.v2CardIndex(
        attemptId: attempt.attemptId,
        sourceId: sourceId,
      );
    } else {
      indexedCards = await officialAnkiV2RunCardIndex(
        sources: sources,
        attempts: attempts,
        engine: resolved,
        attemptId: attempt.attemptId,
        sourceId: sourceId,
      );
    }

    // 晋升第一步：映射决策进配置区（op 42 单事务，K10）。
    final decisions = OfficialAnkiV2DecisionStore(resolved);
    final suggestionsJson = _encodeSuggestions(suggestions);
    await decisions.writeImportMapping(
      sourceId: sourceId,
      decision: OfficialAnkiV2MappingDecision(
        notetypeIdsConfirmed: {...confirmedNotetypes},
        notetypeIdsSkipped: {...skippedNotetypes},
        excludedDeckIds: {...excludedDeckIds},
        suggestionsJson: suggestionsJson,
      ),
    );
    // 晋升第二步：attempt 状态推进（receiptCommitted）。两步各自幂等。
    attempts.setPhase(
      attemptId: attempt.attemptId,
      phase: OfficialAnkiAttemptPhase.receiptCommitted,
      nowMillis: _now,
    );

    // 牌组→课程放置决策：顶层牌组的默认派生写进配置区（视图重建的输入
    // 之一；同值重放幂等，用户在向导里的覆盖将来直接覆写同键）。
    await _writeDerivedPlacements(resolved);

    await finishCommit(
      sourceId: sourceId,
      attemptId: attempt.attemptId,
      published: true,
    );
    officialAnkiV2Log(
      'commit window closed: $sourceId '
      '(${imported.cardCount} cards, $indexedCards indexed)',
    );

    if (excludedDeckIds.isNotEmpty) {
      await _suspendDecks(resolved, sources, sourceId, excludedDeckIds);
    }
    final rebuilt = await _rebuild(sourceId: sourceId);
    final partCount = await OfficialAnkiV2ViewStore(course).splitSectionCount();
    // 与 v1 publish 同语义的调度锁（P1）：未被课程引入的卡挂起，课时
    // 完成解锁。读面 = 视图行 + 引入账本（anki_card_introduction_states，
    // 保留表）；写只经引擎（suspend），course.db 零写入。fail-open：
    // 失败不阻塞导入，下次重跑可收敛（v1 LockReconciler 同策略）。
    await _reconcileSchedulerLock(resolved, sourceId);
    return OfficialAnkiV2CommitResult(
      sourceId: sourceId,
      attemptId: attempt.attemptId,
      cardCount: indexedCards,
      sectionCount: rebuilt.sectionCount,
      lessonCount: rebuilt.lessonCount,
      newNoteCount: imported.newNoteIds.length,
      duplicateNoteCount: imported.duplicateNoteIds.length,
      partCount: partCount,
      includeMedia: includeMedia,
    );
  }

  /// Promote the staging collection when its file is still on disk.
  /// Any promote failure re-imports the original package.
  Future<OfficialAnkiImportLog> _importLive({
    required OfficialAnkiEngine resolved,
    required OfficialAnkiImportAttemptDao attempts,
    required String sourceId,
    required String packagePath,
    required bool includeMedia,
  }) async {
    final attempt = attempts.unfinishedBySource(sourceId);
    final stagingPath = attempt?.stagingPath;
    final collection =
        stagingPath == null ? null : File('$stagingPath/collection.anki2');
    if (collection != null && collection.existsSync()) {
      try {
        return await resolved.promoteStagingCollection(
          collectionPath: collection.path,
          mediaFolder: '$stagingPath/collection.media',
          withScheduling: true,
          withMedia: includeMedia,
        );
      } catch (error) {
        officialAnkiV2Log('promote failed, reimporting package: $error',
            warning: true);
      }
    }
    return resolved.importPackage(
      packagePath: packagePath,
      withScheduling: true,
      withMedia: includeMedia,
    );
  }

  Future<void> _suspendDecks(
    OfficialAnkiEngine resolved,
    OfficialAnkiSourceDao sources,
    String sourceId,
    Set<int> deckIds,
  ) async {
    final cardIds = [
      for (final card in sources.listCards(sourceId))
        if (deckIds.contains(card.deckId)) card.cardId,
    ]..sort();
    for (var start = 0; start < cardIds.length; start += _suspendBatch) {
      final end = start + _suspendBatch;
      await resolved.buryOrSuspendCards(
        action: OfficialBuryOrSuspendAction.suspend,
        cardIds: cardIds.sublist(
          start,
          end > cardIds.length ? cardIds.length : end,
        ),
      );
    }
  }

  /// 100 = 桥的 bury/suspend 单批上限（LockReconciler 同款）。
  static const _suspendBatch = 100;

  Future<void> _reconcileSchedulerLock(
    OfficialAnkiEngine resolved,
    String sourceId,
  ) async {
    try {
      final cardIds =
          await OfficialAnkiV2ViewStore(course).cardIdsForSource(sourceId);
      if (cardIds.isEmpty) return;
      final introduced = await AnkiUnificationDao(course)
          .introducedCardIdsForSource(sourceId: sourceId);
      final toSuspend = [
        for (final cardId in cardIds)
          if (!introduced.contains(cardId)) cardId,
      ]..sort();
      for (var start = 0; start < toSuspend.length; start += _suspendBatch) {
        // B2：sublist O(k)，skip/take 每趟从头扫 O(start+k)。
        final end = start + _suspendBatch;
        await resolved.buryOrSuspendCards(
          action: OfficialBuryOrSuspendAction.suspend,
          cardIds: toSuspend.sublist(
            start,
            end > toSuspend.length ? toSuspend.length : end,
          ),
        );
      }
    } catch (error) {
      officialAnkiV2Log('scheduler lock reconcile: $error', warning: true);
    }
  }

  /// [sourceId] 非空时只重建该 source 的行（D2：commit 只可能改变它，
  /// 成本 O(变更) 而非 O(全部 source)）；空则全量重建。
  Future<OfficialAnkiV2ViewRebuildResult> _rebuild({String? sourceId}) async {
    final resolved = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolved == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
        debugDetails: 'v2_view_rebuild_requires_engine',
      );
    }
    final rebuilder = OfficialAnkiV2ViewRebuilder(
      engine: resolved,
      catalog: catalog,
      course: course,
      profileId: paths.profileId,
      nowMillis: nowMillis,
    );
    if (sourceId != null) {
      return rebuilder.rebuildSource(sourceId);
    }
    return rebuilder.rebuild();
  }

  static String _encodeSuggestions(
    Map<int, OfficialAnkiMappingSuggestion> suggestions,
  ) {
    return jsonEncode({
      for (final entry in suggestions.entries)
        '${entry.key}': entry.value.toJson(),
    });
  }

  /// 顶层平牌组（无 '::' 子级）的默认放置决策落配置区。多级牌组不写
  /// ——路径派生本身确定（section=首段/lesson=末段），配置区只存会改变
  /// 派生结果的决策（D2：用户放置决策），避免派生键反过来压制派生。
  Future<void> _writeDerivedPlacements(OfficialAnkiEngine resolved) async {
    try {
      final tree = await resolved.listDeckTree();
      final hasChildren = <String>{};
      for (final node in tree) {
        if (node.name.contains('::')) {
          hasChildren.add(node.name.split('::').first);
        }
      }
      final decisions = OfficialAnkiV2DecisionStore(resolved);
      final flatTopDecks = [
        for (final node in tree)
          if (node.name.split('::').length == 1 && // 只给顶层牌组落默认键
              !hasChildren.contains(node.name)) // 多级树走路径派生
            node,
      ];
      // C8：一次批量读全部候选键，替代逐 deckId 的读 RPC。
      final existing = await decisions
          .readDeckPlacements({for (final d in flatTopDecks) d.deckId});
      for (final node in flatTopDecks) {
        if (existing.containsKey(node.deckId)) continue; // 用户/历史决策优先
        await decisions.writeDeckPlacement(
          deckId: node.deckId,
          decision: OfficialAnkiV2PlacementDecision(
            deckPath: node.name,
            sectionKey: node.name,
            unitKey: node.name,
            lessonKey: node.name,
          ),
        );
      }
    } catch (error) {
      // 放置决策可派生：写失败只记录，视图按默认派生照样能建。
      officialAnkiV2Log('placement decisions: $error', warning: true);
    }
  }
}
