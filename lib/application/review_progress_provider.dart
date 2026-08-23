// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/fsrs_engine.dart';
import 'package:turna/core/srs_scheduler.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/l10n/app_strings.dart';

/// Where a card comes from for progress stats.
enum ReviewSourceKind { all, course, grammar, ankiDeck, ankiOfficial }

class ReviewSource {
  final ReviewSourceKind kind;
  final String id;
  final String label;
  final String? importId;
  final bool active;

  const ReviewSource({
    required this.kind,
    required this.id,
    required this.label,
    this.importId,
    this.active = true,
  });

  static const all = ReviewSource(
    kind: ReviewSourceKind.all,
    id: 'all',
    label: '全部',
  );

  static const course = ReviewSource(
    kind: ReviewSourceKind.course,
    id: 'course',
    label: '课程',
  );

  static const grammar = ReviewSource(
    kind: ReviewSourceKind.grammar,
    id: 'grammar',
    label: '语法',
  );

  bool get isAll => kind == ReviewSourceKind.all;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewSource && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(kind, id);
}

enum MaturityBucket { newCards, young, mature, leech }

enum DueFilter { any, overdue, due7, due30 }

enum EventRange { all, d7, d30, d90, d365 }

/// Item-type filter. Grammar is separate from [SrsItemType].
enum ProgressTypeFilter { all, word, expression, grammar }

class ReviewProgressFilter {
  final ReviewSource source;
  final ProgressTypeFilter type;
  final Set<MaturityBucket> maturity;
  final DueFilter due;
  final EventRange eventRange;

  const ReviewProgressFilter({
    this.source = ReviewSource.all,
    this.type = ProgressTypeFilter.all,
    this.maturity = const {},
    this.due = DueFilter.any,
    this.eventRange = EventRange.all,
  });

  ReviewProgressFilter copyWith({
    ReviewSource? source,
    ProgressTypeFilter? type,
    Set<MaturityBucket>? maturity,
    DueFilter? due,
    EventRange? eventRange,
  }) {
    return ReviewProgressFilter(
      source: source ?? this.source,
      type: type ?? this.type,
      maturity: maturity ?? this.maturity,
      due: due ?? this.due,
      eventRange: eventRange ?? this.eventRange,
    );
  }
}

class SourceProgressRow {
  final ReviewSource source;
  final int totalCards;
  final int tracked;
  final int dueToday;
  final int reviews;
  final double meanRetention;
  final double meanMastery;
  final MaturityBreakdown maturity;

  const SourceProgressRow({
    required this.source,
    required this.totalCards,
    required this.tracked,
    required this.dueToday,
    required this.reviews,
    required this.meanRetention,
    required this.meanMastery,
    required this.maturity,
  });
}

class ReviewProgressSnapshot {
  final MemoryCurveSnapshot aggregate;
  final List<SourceProgressRow> bySource;
  final ReviewProgressFilter filter;
  final List<ReviewSource> availableSources;
  final List<ActivityBucketRow> activity;

  const ReviewProgressSnapshot({
    required this.aggregate,
    required this.bySource,
    required this.filter,
    required this.availableSources,
    this.activity = const [],
  });
}

/// Tagged card for filtering (queue origin).
class _TaggedCard {
  final SrsWord word;
  final ReviewSourceKind origin;
  final String? sourceId;

  const _TaggedCard({
    required this.word,
    required this.origin,
    this.sourceId,
  });
}

@lazySingleton
class ReviewProgressProvider {
  ReviewProgressProvider(
    this._reviewDao,
    this._srs,
    this._grammar,
    this._ankiImportDao,
  );

  final ReviewHistoryDao _reviewDao;
  final SrsProvider _srs;
  final GrammarReviewProvider _grammar;
  final AnkiImportDao _ankiImportDao;

  final SrsScheduler _scheduler = FsrsEngine(enableFuzzing: false);

  List<_TaggedCard> _allTagged() {
    final out = <_TaggedCard>[];
    for (final w in _srs.state.values) {
      final origin = switch (w.sourceKind) {
        SrsSourceKind.course => ReviewSourceKind.course,
        SrsSourceKind.grammar => ReviewSourceKind.grammar,
        SrsSourceKind.ankiLegacy => ReviewSourceKind.ankiDeck,
        SrsSourceKind.ankiOfficial => ReviewSourceKind.ankiOfficial,
      };
      out.add(_TaggedCard(word: w, origin: origin, sourceId: w.sourceId));
    }
    for (final w in _grammar.state.values) {
      out.add(_TaggedCard(word: w, origin: ReviewSourceKind.grammar));
    }
    return out;
  }

  Future<List<ReviewSource>> listSources() async {
    final history = await _reviewDao.sourceReviewCounts(
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.now(),
    );
    return _listSources(_allTagged(), historicalKeys: history.keys.toSet());
  }

  /// Source list from an already-computed tagged pass. [snapshot] must reuse
  /// its own pass instead of scanning the full states twice (Plan 3 §14.1).
  Future<List<ReviewSource>> _listSources(
    List<_TaggedCard> tagged, {
    Set<String> historicalKeys = const {},
  }) async {
    final sources = <ReviewSource>[ReviewSource.all];
    if (tagged.any((t) => t.origin == ReviewSourceKind.course) ||
        historicalKeys.contains('course')) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.course,
        id: 'course',
        label: AppStrings.reviewProgressSourceCourse,
      ));
    }
    if (tagged.any((t) => t.origin == ReviewSourceKind.grammar) ||
        historicalKeys.contains('grammar')) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.grammar,
        id: 'grammar',
        label: AppStrings.reviewProgressSourceGrammar,
      ));
    }

    final importIdSet = tagged
        .where((t) => t.origin == ReviewSourceKind.ankiDeck)
        .map((t) => t.sourceId!)
        .toSet()
      ..addAll(historicalKeys
          .where((key) => key.startsWith('anki:'))
          .map((key) => key.substring(5)));
    final importIds = importIdSet.toList()..sort();

    final imports = await _ankiImportDao.getAll();
    final nameById = {
      for (final r in imports)
        r.importId: _labelFromPath(r.sourcePath, r.importId),
    };

    for (final id in importIds) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.ankiDeck,
        id: 'anki:$id',
        label: nameById[id] ?? AppStrings.reviewProgressSourceAnki(id),
        importId: id,
        active: nameById.containsKey(id),
      ));
    }
    final officialIdSet = tagged
        .where((t) => t.origin == ReviewSourceKind.ankiOfficial)
        .map((t) => t.sourceId!)
        .toSet()
      ..addAll(historicalKeys
          .where((key) => key.startsWith('official:'))
          .map((key) => key.substring('official:'.length)));
    final officialIds = officialIdSet.toList()..sort();
    for (final id in officialIds) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.ankiOfficial,
        id: 'official:$id',
        label: AppStrings.reviewProgressSourceAnki(id),
        importId: id,
        active: tagged.any((card) =>
            card.origin == ReviewSourceKind.ankiOfficial &&
            card.sourceId == id),
      ));
    }
    return sources;
  }

  String _labelFromPath(String path, String importId) {
    final name = path.split(RegExp(r'[/\\]')).last;
    if (name.isEmpty) return AppStrings.reviewProgressSourceAnki(importId);
    final bare =
        name.replaceAll(RegExp(r'\.(apkg|colpkg)$', caseSensitive: false), '');
    return AppStrings.reviewProgressSourceAnkiNamed(bare);
  }

  @Deprecated('Use InsightsRepository for the insights path')
  Future<ReviewProgressSnapshot> snapshot([
    ReviewProgressFilter filter = const ReviewProgressFilter(),
  ]) async {
    final tagged = _allTagged();
    final now = DateTime.now();

    final filtered = tagged.where((t) => _matchesCard(t, filter, now)).toList();
    final aggregate = _aggregate(filtered, now);

    final rangeStart = _rangeStart(filter.eventRange, now);
    final historyFilter = _historyFilter(filter);
    final retentionRows = await _reviewDao.retentionByIntervalBucket(
      rangeStart,
      now,
      filter: historyFilter,
    );
    final curve = [
      for (final row in retentionRows)
        RetentionPoint(
          intervalBucketDays: row.intervalBucketDays,
          retention: row.total == 0 ? 0 : row.recalled / row.total,
          sampleSize: row.total,
        ),
    ];
    final totalReviews = retentionRows.fold<int>(0, (n, row) => n + row.total);
    final sourceCounts = await _reviewDao.sourceReviewCounts(
      rangeStart,
      now,
      filter: _historyFilter(filter.copyWith(source: ReviewSource.all)),
    );
    final available = await _listSources(
      tagged,
      historicalKeys: sourceCounts.keys.toSet(),
    );
    final heatmapStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 364));
    final activeBuckets = await _reviewDao.activityBuckets(
      heatmapStart,
      now,
      ActivityGranularity.day,
      filter: historyFilter,
    );
    final activity = _fillDailyActivity(activeBuckets, heatmapStart, 365);
    final fullAggregate = MemoryCurveSnapshot(
      currentRetention: aggregate.currentRetention,
      meanMastery: aggregate.meanMastery,
      trackedCards: aggregate.trackedCards,
      totalCards: aggregate.totalCards,
      forecast: aggregate.forecast,
      maturity: aggregate.maturity,
      retentionByInterval: curve,
      totalReviews: totalReviews,
    );

    // Per-source rows: ignore source filter for breakdown, but apply other filters.
    final baseFilter = filter.copyWith(source: ReviewSource.all);
    final forSources =
        tagged.where((t) => _matchesCard(t, baseFilter, now)).toList();
    final bySource = <SourceProgressRow>[];

    void addSource(ReviewSource src, Iterable<_TaggedCard> cards) {
      final list = cards.toList();
      final revCount = sourceCounts[src.id] ?? 0;
      if (list.isEmpty && revCount == 0 && src.kind != ReviewSourceKind.all) {
        return;
      }
      final agg = _aggregate(list, now);
      bySource.add(SourceProgressRow(
        source: src,
        totalCards: agg.totalCards,
        tracked: agg.trackedCards,
        dueToday: agg.forecast.dueToday,
        reviews: revCount,
        meanRetention: agg.currentRetention,
        meanMastery: agg.meanMastery,
        maturity: agg.maturity,
      ));
    }

    for (final src in available.where((s) => !s.isAll)) {
      final cards = forSources.where((t) {
        switch (src.kind) {
          case ReviewSourceKind.course:
            return t.origin == ReviewSourceKind.course;
          case ReviewSourceKind.grammar:
            return t.origin == ReviewSourceKind.grammar;
          case ReviewSourceKind.ankiDeck:
            return t.origin == ReviewSourceKind.ankiDeck &&
                t.sourceId == src.importId;
          case ReviewSourceKind.ankiOfficial:
            return t.origin == ReviewSourceKind.ankiOfficial &&
                t.sourceId == src.importId;
          case ReviewSourceKind.all:
            return true;
        }
      });
      addSource(src, cards);
    }

    return ReviewProgressSnapshot(
      aggregate: fullAggregate,
      bySource: bySource,
      filter: filter,
      availableSources: available,
      activity: activity,
    );
  }

  List<ActivityBucketRow> _fillDailyActivity(
    List<ActivityBucketRow> active,
    DateTime start,
    int days,
  ) {
    final byDay = {for (final row in active) row.bucket: row.reviewedCount};
    return [
      for (var offset = 0; offset < days; offset++)
        ActivityBucketRow(
          bucket: _localDayKey(start.add(Duration(days: offset))),
          reviewedCount:
              byDay[_localDayKey(start.add(Duration(days: offset)))] ?? 0,
        ),
    ];
  }

  String _localDayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  DateTime _rangeStart(EventRange range, DateTime now) {
    switch (range) {
      case EventRange.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
      case EventRange.d7:
        return now.subtract(const Duration(days: 7));
      case EventRange.d30:
        return now.subtract(const Duration(days: 30));
      case EventRange.d90:
        return now.subtract(const Duration(days: 90));
      case EventRange.d365:
        return now.subtract(const Duration(days: 365));
    }
  }

  ReviewHistoryFilter _historyFilter(ReviewProgressFilter filter) {
    SrsSourceKind? sourceKind;
    String? sourceId;
    String? queue;
    String? type;
    switch (filter.source.kind) {
      case ReviewSourceKind.all:
        break;
      case ReviewSourceKind.course:
        sourceKind = SrsSourceKind.course;
        queue = 'srs';
        break;
      case ReviewSourceKind.grammar:
        sourceKind = SrsSourceKind.grammar;
        queue = 'grammar';
        break;
      case ReviewSourceKind.ankiDeck:
        sourceKind = SrsSourceKind.ankiLegacy;
        sourceId = filter.source.importId;
        queue = 'srs';
        break;
      case ReviewSourceKind.ankiOfficial:
        sourceKind = SrsSourceKind.ankiOfficial;
        sourceId = filter.source.importId;
        queue = 'srs';
        break;
    }
    switch (filter.type) {
      case ProgressTypeFilter.all:
        break;
      case ProgressTypeFilter.word:
        type = 'word';
        break;
      case ProgressTypeFilter.expression:
        type = 'expression';
        break;
      case ProgressTypeFilter.grammar:
        queue = 'grammar';
        break;
    }
    return ReviewHistoryFilter(
      sourceKind: sourceKind,
      sourceId: sourceId,
      queue: queue,
      type: type,
    );
  }

  bool _matchesCard(_TaggedCard t, ReviewProgressFilter f, DateTime now) {
    // Source
    switch (f.source.kind) {
      case ReviewSourceKind.all:
        break;
      case ReviewSourceKind.course:
        if (t.origin != ReviewSourceKind.course) return false;
        break;
      case ReviewSourceKind.grammar:
        if (t.origin != ReviewSourceKind.grammar) return false;
        break;
      case ReviewSourceKind.ankiDeck:
        if (t.origin != ReviewSourceKind.ankiDeck ||
            t.sourceId != f.source.importId) {
          return false;
        }
        break;
      case ReviewSourceKind.ankiOfficial:
        if (t.origin != ReviewSourceKind.ankiOfficial ||
            t.sourceId != f.source.importId) {
          return false;
        }
        break;
    }

    // Type
    switch (f.type) {
      case ProgressTypeFilter.all:
        break;
      case ProgressTypeFilter.grammar:
        if (t.origin != ReviewSourceKind.grammar) return false;
        break;
      case ProgressTypeFilter.word:
        if (t.origin == ReviewSourceKind.grammar ||
            t.word.type != SrsItemType.word) {
          return false;
        }
        break;
      case ProgressTypeFilter.expression:
        if (t.origin == ReviewSourceKind.grammar ||
            t.word.type != SrsItemType.expression) {
          return false;
        }
        break;
    }

    // Maturity
    if (f.maturity.isNotEmpty) {
      final bucket = _maturityOf(t.word);
      if (!f.maturity.contains(bucket)) return false;
    }

    // Due
    final diffDays = t.word.dueAt.difference(now).inMinutes / 1440.0;
    switch (f.due) {
      case DueFilter.any:
        break;
      case DueFilter.overdue:
        if (diffDays > 0) return false;
        break;
      case DueFilter.due7:
        if (diffDays > 7) return false;
        break;
      case DueFilter.due30:
        if (diffDays > 30) return false;
        break;
    }

    return true;
  }

  MaturityBucket _maturityOf(SrsWord w) {
    if (w.isLeech) return MaturityBucket.leech;
    if (w.reps == 0) return MaturityBucket.newCards;
    if (w.intervalDays < 21) return MaturityBucket.young;
    return MaturityBucket.mature;
  }

  MemoryCurveSnapshot _aggregate(List<_TaggedCard> cards, DateTime now) {
    var retentionSum = 0.0;
    var masterySum = 0.0;
    var tracked = 0;
    var dueToday = 0, due7 = 0, due30 = 0;
    var newC = 0, young = 0, mature = 0, leech = 0;

    for (final t in cards) {
      final w = t.word;
      if (w.lastReviewedAt != null) {
        retentionSum += _scheduler.retrievability(w, now: now);
        masterySum += _scheduler.masteryScore(w, now: now);
        tracked++;
      }
      final diffDays = w.dueAt.difference(now).inMinutes / 1440.0;
      if (diffDays <= 0) dueToday++;
      if (diffDays <= 7) due7++;
      if (diffDays <= 30) due30++;

      switch (_maturityOf(w)) {
        case MaturityBucket.leech:
          leech++;
          break;
        case MaturityBucket.newCards:
          newC++;
          break;
        case MaturityBucket.young:
          young++;
          break;
        case MaturityBucket.mature:
          mature++;
          break;
      }
    }

    return MemoryCurveSnapshot(
      currentRetention: tracked > 0 ? retentionSum / tracked : 1.0,
      meanMastery: tracked > 0 ? masterySum / tracked : 0.0,
      trackedCards: tracked,
      totalCards: cards.length,
      forecast: Forecast(dueToday: dueToday, due7Days: due7, due30Days: due30),
      maturity: MaturityBreakdown(
        newCards: newC,
        young: young,
        mature: mature,
        leech: leech,
      ),
      retentionByInterval: const [],
      totalReviews: 0,
    );
  }
}
