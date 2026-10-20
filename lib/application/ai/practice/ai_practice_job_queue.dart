// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/ai_recent_task_log.dart';
import 'package:turna/application/ai/practice/ai_practice_generator.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/ai/practice/ai_practice_source_context.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/domain/repositories/i_ai_practice_repository.dart';

/// App-level owner of AI course generation jobs and the "我的练习" library.
///
/// The queue lives above the router (registered in `providers.dart`), so a job
/// keeps running while the learner visits other tabs. It is **not** an OS
/// background service: if the process dies, [restoreOnStartup] rewrites the
/// in-flight version to [AiPracticeStatus.interrupted] and the UI offers a
/// retry.
///
/// One job runs at a time; the phased generator itself fills lessons
/// sequentially. That keeps API bursts predictable on limited quotas.
///
/// Storage is two tables (ADR 0054): a course owns identity/favourite/expiry,
/// and each generation attempt is appended as a version. In memory the queue
/// keeps the composed [AiCourse] (with its versions) so the UI never has to
/// join.
@lazySingleton
class AiPracticeJobQueue extends ChangeNotifier {
  AiPracticeJobQueue(
    this._repository,
    this._generator,
    this._sourceContext,
    this._configHolder,
    this._languageProvider,
  );

  final IAiPracticeRepository _repository;
  final AiPracticeGenerator _generator;
  final AiPracticeSourceContextBuilder _sourceContext;
  final AiEngineConfigHolder _configHolder;
  final LanguageProvider _languageProvider;

  final List<AiCourse> _items = <AiCourse>[];
  final Map<String, AiCancelToken> _tokens = <String, AiCancelToken>{};

  /// Serializes row writes. Progress callbacks are fire-and-forget; without a
  /// chain a late `running` write could land after the terminal `ready` write
  /// and resurrect the job in the DB.
  Future<void> _persistTail = Future<void>.value();

  /// Ids deleted while a generation/adjust call was in flight. `_replace` must
  /// not resurrect the row when the late result lands.
  final Set<String> _deletedIds = <String>{};
  bool _loaded = false;
  bool _loading = false;
  bool _pumping = false;

  List<AiCourse> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  bool get hasActiveJob => _items.any((item) => item.status.isBusy);
  int get readyCount => _items.where((item) => item.isPlayable).length;

  /// Favourited courses — permanent, shown first everywhere.
  List<AiCourse> get favorites => _sorted(_items.where((item) => item.pinned));

  /// Playable drafts that are not favourited, soonest deadline first.
  List<AiCourse> get drafts {
    final list =
        _items.where((item) => !item.pinned && item.isPlayable).toList()
          ..sort((a, b) {
            final left = a.expiresAt;
            final right = b.expiresAt;
            if (left == null && right == null) {
              return b.updatedAt.compareTo(a.updatedAt);
            }
            if (left == null) return 1;
            if (right == null) return -1;
            return left.compareTo(right);
          });
    return List<AiCourse>.unmodifiable(list);
  }

  /// Unfinished / broken jobs (never playable content).
  List<AiCourse> get tasks => _sorted(_items.where((item) => !item.isPlayable));

  /// Drafts expiring within two days — the "即将过期" strip in the Hub.
  List<AiCourse> expiringSoon({DateTime? now}) {
    final at = now ?? DateTime.now();
    return drafts
        .where((item) => !item.pinned && item.isExpiringSoon(at))
        .toList(growable: false);
  }

  /// The job currently running (or the newest queued one when idle).
  AiCourse? get activeJob {
    final running = _items
        .where((item) => item.status == AiPracticeStatus.running)
        .toList();
    if (running.isNotEmpty) return running.first;
    final queued =
        _items.where((item) => item.status == AiPracticeStatus.queued).toList();
    return queued.isEmpty ? null : queued.last;
  }

  /// Hub preview: favourites first, then whatever is about to expire. Jobs are
  /// deliberately excluded — they have their own banner + a dedicated section,
  /// and mixing them into "我的练习" made failed jobs look like content.
  List<AiCourse> hubPreview({int limit = 3, DateTime? now}) {
    final at = now ?? DateTime.now();
    final picked = <AiCourse>[];
    final seen = <String>{};
    for (final course in [...favorites, ...expiringSoon(now: at)]) {
      if (seen.add(course.id)) picked.add(course);
      if (picked.length >= limit) break;
    }
    if (picked.length < limit) {
      for (final course in drafts) {
        if (seen.add(course.id)) picked.add(course);
        if (picked.length >= limit) break;
      }
    }
    return List<AiCourse>.unmodifiable(picked);
  }

  /// Most recently updated rows, newest first. Kept for callers that want a
  /// raw recency list (the Hub uses [hubPreview]).
  List<AiCourse> recent({int limit = 3}) {
    final sorted = _sorted(_items);
    return sorted.take(limit).toList(growable: false);
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final rows = await _repository.list();
      _items
        ..clear()
        ..addAll(rows);
      _loaded = true;
      notifyListeners();
    } catch (e) {
      logger.w('AiPracticeJobQueue.load failed: $e');
    } finally {
      _loading = false;
    }
  }

  /// Force a re-read (pull-to-refresh / after external changes).
  Future<void> reload() async {
    _loaded = false;
    await ensureLoaded();
  }

  /// Startup hook: mark dead jobs, sweep expired drafts, then load. Safe to
  /// call once after the course DB is ready.
  Future<void> restoreOnStartup() async {
    try {
      await _repository.markInterruptedOnStartup();
      await _repository.pruneExpired(now: DateTime.now());
    } catch (e) {
      logger.w('AiPracticeJobQueue.restore failed: $e');
    }
    _loaded = false;
    await ensureLoaded();
    // A previously interrupted job is not retried automatically: the learner
    // decides when to spend tokens again.
  }

  /// Delete every expired draft. Runs on startup and whenever the library page
  /// opens, so a long-lived session still honours the 7-day promise.
  Future<int> sweepExpired({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final expired = _items
        .where((item) => !item.pinned && item.isExpired(at))
        .map((item) => item.id)
        .toList();
    // Trust the DB sweep as the source of truth (covers rows not in memory).
    int removed;
    try {
      removed = await _repository.pruneExpired(now: at);
    } catch (e) {
      logger.w('AiPracticeJobQueue.sweep failed: $e');
      return 0;
    }
    if (removed > 0) {
      _items.removeWhere((item) => !item.pinned && item.isExpired(at));
      notifyListeners();
    }
    // Already-expired rows discovered in memory but not counted by the DB (a
    // clock change between the two reads) still need dropping from the list.
    if (removed == 0 && expired.isNotEmpty) {
      _items.removeWhere((item) => expired.contains(item.id));
      notifyListeners();
    }
    return removed;
  }

  Future<AiCourse> startPractice({
    required AiPracticeSource source,
    required String level,
    bool explanationRequested = false,
  }) async {
    final sourceContext = await _sourceContext.build(source);
    final now = DateTime.now();
    final id = _newId(now);
    final title = switch (source) {
      AiPracticeSource.mistakes => '错题专项 · ${_stamp(now)}',
      AiPracticeSource.weakWords => '弱词专项 · ${_stamp(now)}',
      AiPracticeSource.difficult => '难懂点专项 · ${_stamp(now)}',
      AiPracticeSource.custom => '练习 · ${_stamp(now)}',
    };
    final request = AiPracticeRequest(
      id: id,
      title: title,
      source: source,
      languageCode: _languageProvider.selectedLanguageCode,
      sourceContext: sourceContext,
      explanationRequested: explanationRequested,
      spec: AiCourseSpec(
        language: _languageProvider.displayName,
        sourceLanguage: 'Chinese',
        topic: title,
        level: level,
        unitCount: 1,
        lessonsPerUnit: 1,
        template: 'review',
        designBrief: 'Short remediation drill. Cover every item in the learner '
            'evidence; keep prompts short and use plausible distractors.',
        groundedMode: true,
        maxGroundedResources: 120,
      ),
    );
    return _enqueue(request);
  }

  Future<AiCourse> startCustomCourse({
    required String topic,
    required String level,
    required int unitCount,
    required int lessonsPerUnit,
    required String template,
    String designBrief = '',
    bool grounded = true,
    bool explanationRequested = false,
  }) async {
    final now = DateTime.now();
    final id = _newId(now);
    final title =
        topic.trim().isEmpty ? '自定义课程 · ${_stamp(now)}' : topic.trim();
    final request = AiPracticeRequest(
      id: id,
      title: title,
      source: AiPracticeSource.custom,
      languageCode: _languageProvider.selectedLanguageCode,
      explanationRequested: explanationRequested,
      spec: AiCourseSpec(
        language: _languageProvider.displayName,
        sourceLanguage: 'Chinese',
        topic: title,
        level: level,
        unitCount: unitCount,
        lessonsPerUnit: lessonsPerUnit,
        template: template,
        designBrief: designBrief.trim(),
        groundedMode: grounded,
        maxGroundedResources: 200,
      ),
    );
    return _enqueue(request);
  }

  Future<AiCourse> _enqueue(AiPracticeRequest request) async {
    _deletedIds.remove(request.id);
    final now = DateTime.now();
    final versionId = _versionId(request.id, now, 0);
    final total = request.spec.unitCount * request.spec.lessonsPerUnit;
    final course = AiCourse(
      id: request.id,
      languageCode: request.languageCode,
      title: request.title,
      source: request.source,
      level: request.spec.level,
      topic: request.spec.topic,
      expiresAt: now.add(kAiCourseDraftTtl),
      createdAt: now,
      updatedAt: now,
      versions: [
        AiCourseVersion(
          id: versionId,
          courseId: request.id,
          status: AiPracticeStatus.queued,
          requestJson: jsonEncode(request.toJson()),
          progressTotal: total,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await _repository.upsertCourse(course);
    await _repository.upsertVersion(course.versions.first);
    _items
      ..removeWhere((item) => item.id == course.id)
      ..add(course);
    notifyListeners();
    unawaited(_pump());
    return course;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = _oldestQueued();
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _pumping = false;
      notifyListeners();
    }
  }

  AiCourse? _oldestQueued() {
    final queued = _items
        .where((item) => item.status == AiPracticeStatus.queued)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queued.isEmpty ? null : queued.first;
  }

  Future<void> _run(AiCourse queued) async {
    final request = _requestOf(queued);
    if (request == null) {
      await _replaceVersion(queued.copyWith(
        versions: _replaceHead(
          queued,
          queued.latestVersion!.copyWith(
            status: AiPracticeStatus.failed,
            errorMessage: '生成参数已损坏，请删除后重新生成。',
            updatedAt: DateTime.now(),
          ),
        ),
        updatedAt: DateTime.now(),
      ));
      return;
    }
    final config = _configHolder.config;
    if (!config.isComplete) {
      await _replaceVersion(queued.copyWith(
        versions: _replaceHead(
          queued,
          queued.latestVersion!.copyWith(
            status: AiPracticeStatus.failed,
            errorMessage: '未配置 AI 引擎，请先在智能练习顶部配置。',
            updatedAt: DateTime.now(),
          ),
        ),
        updatedAt: DateTime.now(),
      ));
      return;
    }

    var head = queued.latestVersion!.copyWith(
      status: AiPracticeStatus.running,
      progressDone: 0,
      progressTotal: request.spec.unitCount * request.spec.lessonsPerUnit,
      errorMessage: null,
      updatedAt: DateTime.now(),
    );
    await _replaceVersion(queued.copyWith(
      versions: _replaceHead(queued, head),
      updatedAt: DateTime.now(),
    ));

    final token = AiCancelToken();
    _tokens[queued.id] = token;
    try {
      final result = await _generator.generate(
        config: config,
        request: request,
        cancelToken: token,
        onProgress: (progress) {
          head = head.copyWith(
            progressDone: progress.done,
            progressTotal: progress.total > 0
                ? progress.total
                : request.spec.unitCount * request.spec.lessonsPerUnit,
            updatedAt: DateTime.now(),
          );
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final last = _lastProgressWriteMs[queued.id];
          final due = last == null ||
              nowMs - last >= _progressWriteInterval.inMilliseconds;
          if (due) _lastProgressWriteMs[queued.id] = nowMs;
          // In-memory state and listeners always move; only the DB write is
          // coalesced (see [_progressWriteInterval]).
          unawaited(_replaceVersion(
            queued.copyWith(versions: _replaceHead(queued, head)),
            persist: due,
          ));
        },
      );
      await _replaceVersion(queued.copyWith(
        versions: _replaceHead(
          queued,
          head.copyWith(
            status: AiPracticeStatus.ready,
            sectionJson: jsonEncode(result.section),
            qualityJson: result.qualityJson,
            explanation: result.explanation,
            progressDone: head.progressTotal,
            progressTotal: head.progressTotal,
            errorMessage: null,
            updatedAt: DateTime.now(),
          ),
        ),
        updatedAt: DateTime.now(),
      ));
      _recordRecent(queued.title);
    } on AiCancelled {
      await _failHead(queued, head, '已取消生成。');
    } on AiPracticeGenerationException catch (e) {
      logger.w('practice job ${queued.id} failed: $e');
      await _failHead(queued, head, e.message);
    } catch (e) {
      logger.w('practice job ${queued.id} failed: $e');
      await _failHead(queued, head, AiErrorMapper.map(e).message);
    } finally {
      _tokens.remove(queued.id);
      _lastProgressWriteMs.remove(queued.id);
    }
  }

  Future<void> _failHead(
      AiCourse course, AiCourseVersion head, String message) {
    return _replaceVersion(course.copyWith(
      versions: _replaceHead(
        course,
        head.copyWith(
          status: AiPracticeStatus.failed,
          errorMessage: message,
          updatedAt: DateTime.now(),
        ),
      ),
      updatedAt: DateTime.now(),
    ));
  }

  /// Apply a free-form instruction to a ready course (whole-section adjust).
  ///
  /// Edits the playable version in place: the new section only overwrites the
  /// stored one after the call succeeds, so a failed or cancelled adjustment
  /// leaves the learner with exactly the content they had before.
  Future<void> adjust(String id, String instruction) async {
    final course = byId(id);
    final current = course?.playableVersion;
    if (course == null || current == null) return;
    if (instruction.trim().isEmpty) return;
    if (hasActiveJob) {
      throw const AiPracticeGenerationException('已有生成任务在进行，请稍后再调整。');
    }
    final request = _requestOf(course);
    if (request == null) {
      throw const AiPracticeGenerationException('生成参数已损坏，请删除后重新生成。');
    }
    final config = _configHolder.config;
    if (!config.isComplete) {
      throw const AiPracticeGenerationException('未配置 AI 引擎。');
    }
    final Map<String, dynamic> parsedCurrent;
    try {
      parsedCurrent = jsonDecode(current.sectionJson!) as Map<String, dynamic>;
    } catch (e) {
      throw AiPracticeGenerationException('练习 JSON 已损坏，无法调整。', [e.toString()]);
    }

    final token = AiCancelToken();
    _tokens[id] = token;
    var running = course.copyWith(
      versions: _replaceHead(
        course,
        current.copyWith(
          status: AiPracticeStatus.running,
          progressDone: 0,
          progressTotal: 1,
          errorMessage: null,
          updatedAt: DateTime.now(),
        ),
      ),
      updatedAt: DateTime.now(),
    );
    await _replaceVersion(running);
    try {
      final parsed = await _generator.adjust(
        config: config,
        request: request,
        current: parsedCurrent,
        instruction: instruction,
        cancelToken: token,
      );
      final head =
          running.versions.firstWhere((version) => version.id == current.id);
      running = running.copyWith(
        versions: _replaceHead(
          running,
          head.copyWith(
            status: AiPracticeStatus.ready,
            sectionJson: jsonEncode(parsed),
            progressDone: 1,
            progressTotal: 1,
            errorMessage: null,
            updatedAt: DateTime.now(),
          ),
        ),
        updatedAt: DateTime.now(),
      );
      await _replaceVersion(running);
    } on AiCancelled {
      await _restoreAfterAdjustFailure(running, current, '已取消调整，原练习仍可继续使用。');
    } on AiPracticeGenerationException catch (e) {
      logger.w('practice adjust $id failed: $e');
      await _restoreAfterAdjustFailure(running, current, e.message);
    } catch (e) {
      logger.w('practice adjust $id failed: $e');
      await _restoreAfterAdjustFailure(
        running,
        current,
        AiErrorMapper.map(e).message,
      );
    } finally {
      _tokens.remove(id);
    }
  }

  /// Put the version back to `ready` with the untouched section plus an error
  /// note the card can show.
  Future<void> _restoreAfterAdjustFailure(
    AiCourse course,
    AiCourseVersion before,
    String? message,
  ) {
    return _replaceVersion(course.copyWith(
      versions: _replaceHead(
        course,
        before.copyWith(
          status: AiPracticeStatus.ready,
          errorMessage: message,
          updatedAt: DateTime.now(),
        ),
      ),
      updatedAt: DateTime.now(),
    ));
  }

  /// Re-run generation. A fresh version is appended instead of resetting the
  /// old one, so the previous content stays available if the retry fails.
  Future<void> retry(String id) async {
    _deletedIds.remove(id);
    final course = _firstWhereOrNull(_items, id);
    if (course == null) return;
    if (course.status == AiPracticeStatus.running) return;
    final request = _requestOf(course);
    if (request == null) {
      await _replaceVersion(course.copyWith(
        versions: _replaceHead(
          course,
          course.latestVersion!.copyWith(
            status: AiPracticeStatus.failed,
            errorMessage: '生成参数已损坏，请删除后重新生成。',
            updatedAt: DateTime.now(),
          ),
        ),
        updatedAt: DateTime.now(),
      ));
      return;
    }
    final now = DateTime.now();
    final fresh = AiCourseVersion(
      id: _versionId(course.id, now, course.versions.length),
      courseId: course.id,
      status: AiPracticeStatus.queued,
      requestJson: jsonEncode(request.toJson()),
      progressTotal: request.spec.unitCount * request.spec.lessonsPerUnit,
      createdAt: now,
      updatedAt: now,
    );
    await _replaceVersion(
      course.copyWith(
        versions: [fresh, ...course.versions],
        updatedAt: now,
      ),
    );
    unawaited(_pump());
  }

  Future<void> cancel(String id) async {
    final token = _tokens[id];
    token?.cancel();
    final course = _firstWhereOrNull(_items, id);
    if (course != null && course.status == AiPracticeStatus.queued) {
      await _failHead(course, course.latestVersion!, '已取消生成。');
    }
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    for (final id in idList) {
      _deletedIds.add(id);
      _tokens[id]?.cancel();
      _tokens.remove(id);
      _lastProgressWriteMs.remove(id);
    }
    await _repository.deleteMany(idList);
    _items.removeWhere((item) => idList.contains(item.id));
    notifyListeners();
  }

  /// Favourite / un-favourite. Favouriting clears the deadline (permanent);
  /// un-favouriting starts a fresh 7-day window instead of expiring instantly.
  Future<void> setPinned(Iterable<String> ids, {required bool pinned}) async {
    final idList = ids.toList();
    if (idList.isEmpty) return;
    final now = DateTime.now();
    await _repository.setPinned(idList, pinned: pinned, now: now);
    for (var i = 0; i < _items.length; i++) {
      if (idList.contains(_items[i].id)) {
        _items[i] = _items[i].copyWith(
          pinned: pinned,
          expiresAt: pinned ? null : now.add(kAiCourseDraftTtl),
          clearExpiry: pinned,
          updatedAt: now,
        );
      }
    }
    notifyListeners();
  }

  AiCourse? byId(String id) => _firstWhereOrNull(_items, id);

  /// Minimum gap between two *progress* writes for the same job. Progress
  /// ticks once per lesson, so a 12-lesson section used to mean 12 sequential
  /// upserts. Nothing needs them to resume — the terminal write does — so the
  /// intermediate ones are coalesced and the in-memory row plus listeners are
  /// still updated on every tick.
  static const Duration _progressWriteInterval = Duration(milliseconds: 400);

  /// job id -> timestamp (ms) of the last progress write that reached the DB.
  final Map<String, int> _lastProgressWriteMs = <String, int>{};

  /// Replace a course in memory and persist it together with its head version.
  Future<void> _replaceVersion(AiCourse course, {bool persist = true}) async {
    if (_deletedIds.contains(course.id)) return;
    final index = _items.indexWhere((item) => item.id == course.id);
    if (index >= 0) {
      _items[index] = course;
    } else {
      _items.add(course);
    }
    notifyListeners();
    if (!persist) return;
    _persistTail = _persistTail.catchError((Object _) {}).then((_) async {
      try {
        final head = course.latestVersion;
        if (head != null) await _repository.upsertVersion(head);
        await _repository.upsertCourse(course);
      } catch (e) {
        logger.w('AiPracticeJobQueue.persist failed: $e');
      }
    });
    await _persistTail;
  }

  /// Head version replaced by [next] (same id), everything else untouched.
  static List<AiCourseVersion> _replaceHead(
      AiCourse course, AiCourseVersion next) {
    final versions = [
      for (final version in course.versions)
        if (version.id == next.id) next else version,
    ];
    if (!versions.any((version) => version.id == next.id)) {
      return [next, ...course.versions];
    }
    return versions;
  }

  AiPracticeRequest? _requestOf(AiCourse course) {
    try {
      final decoded = jsonDecode(course.requestJson);
      if (decoded is! Map<String, dynamic>) return null;
      return AiPracticeRequest.fromJson(decoded);
    } catch (e) {
      logger.w('AiPracticeJobQueue.request decode failed: $e');
      return null;
    }
  }

  void _recordRecent(String title) {
    recordAiRecentTask(
      kind: AiTaskKind.courseGenerate,
      summary: title,
    );
  }

  static List<AiCourse> _sorted(Iterable<AiCourse> source) {
    final list = source.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<AiCourse>.unmodifiable(list);
  }

  static AiCourse? _firstWhereOrNull(Iterable<AiCourse> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _newId(DateTime now) =>
      'ai-practice-${now.millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  String _versionId(String courseId, DateTime now, int index) =>
      '$courseId-v${now.millisecondsSinceEpoch}-$index';

  String _stamp(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
}
