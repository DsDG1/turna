// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki/anki_review_assembler.dart';
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
enum ReviewSourceKind { all, course, grammar, ankiDeck }

class ReviewSource {
  final ReviewSourceKind kind;
  final String id;
  final String label;
  final String? importId;

  const ReviewSource({
    required this.kind,
    required this.id,
    required this.label,
    this.importId,
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

enum EventRange { all, d7, d30, d90 }

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

  const ReviewProgressSnapshot({
    required this.aggregate,
    required this.bySource,
    required this.filter,
    required this.availableSources,
  });
}

/// Tagged card for filtering (queue origin).
class _TaggedCard {
  final SrsWord word;
  final ReviewSourceKind origin; // course | grammar | ankiDeck
  final String? importId;

  const _TaggedCard({
    required this.word,
    required this.origin,
    this.importId,
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

  static const List<int> intervalBuckets = MemoryCurveProvider.intervalBuckets;

  /// Extract Anki importId from `anki-<importId>-c…` (card-level wordId,
  /// decision 2). The `<cardId>` segment is always last, so `lastIndexOf('-c')`
  /// finds the importId / cardId separator.
  static String? importIdFromWordId(String wordId) {
    if (!wordId.startsWith(AnkiReviewAssembler.ankiPrefix)) return null;
    final cIdx = wordId.lastIndexOf('-c');
    if (cIdx > 5) return wordId.substring(5, cIdx);
    return null;
  }

  List<_TaggedCard> _allTagged() {
    final out = <_TaggedCard>[];
    for (final w in _srs.state.values) {
      final importId = importIdFromWordId(w.wordId);
      if (importId != null) {
        out.add(_TaggedCard(
          word: w,
          origin: ReviewSourceKind.ankiDeck,
          importId: importId,
        ));
      } else {
        out.add(_TaggedCard(word: w, origin: ReviewSourceKind.course));
      }
    }
    for (final w in _grammar.state.values) {
      out.add(_TaggedCard(word: w, origin: ReviewSourceKind.grammar));
    }
    return out;
  }

  Future<List<ReviewSource>> listSources() async {
    final tagged = _allTagged();
    final sources = <ReviewSource>[ReviewSource.all];
    if (tagged.any((t) => t.origin == ReviewSourceKind.course)) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.course,
        id: 'course',
        label: AppStrings.reviewProgressSourceCourse,
      ));
    }
    if (tagged.any((t) => t.origin == ReviewSourceKind.grammar)) {
      sources.add(ReviewSource(
        kind: ReviewSourceKind.grammar,
        id: 'grammar',
        label: AppStrings.reviewProgressSourceGrammar,
      ));
    }

    final importIds = tagged
        .where((t) => t.origin == ReviewSourceKind.ankiDeck)
        .map((t) => t.importId!)
        .toSet()
        .toList()
      ..sort();

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
      ));
    }
    return sources;
  }

  String _labelFromPath(String path, String importId) {
    final name = path.split(RegExp(r'[/\\]')).last;
    if (name.isEmpty) return AppStrings.reviewProgressSourceAnki(importId);
    final bare = name.replaceAll(RegExp(r'\.(apkg|colpkg)$', caseSensitive: false), '');
    return AppStrings.reviewProgressSourceAnkiNamed(bare);
  }

  Future<ReviewProgressSnapshot> snapshot([
    ReviewProgressFilter filter = const ReviewProgressFilter(),
  ]) async {
    final tagged = _allTagged();
    final available = await listSources();
    final now = DateTime.now();

    final filtered = tagged.where((t) => _matchesCard(t, filter, now)).toList();
    final aggregate = _aggregate(filtered, now);

    // Events for curve: only cards in filtered set + time range.
    final cardIds = filtered.map((t) => t.word.wordId).toSet();
    final events = await _reviewDao.allEvents();
    final rangeStart = _rangeStart(filter.eventRange, now);
    final filteredEvents = events.where((e) {
      if (!cardIds.contains(e.cardId)) return false;
      if (rangeStart != null && e.reviewedAt.isBefore(rangeStart)) return false;
      return true;
    }).toList();

    final curve = _curveFromEvents(filteredEvents);
    final fullAggregate = MemoryCurveSnapshot(
      currentRetention: aggregate.currentRetention,
      meanMastery: aggregate.meanMastery,
      trackedCards: aggregate.trackedCards,
      totalCards: aggregate.totalCards,
      forecast: aggregate.forecast,
      maturity: aggregate.maturity,
      retentionByInterval: curve,
      totalReviews: filteredEvents.length,
    );

    // Per-source rows: ignore source filter for breakdown, but apply other filters.
    final baseFilter = filter.copyWith(source: ReviewSource.all);
    final forSources = tagged.where((t) => _matchesCard(t, baseFilter, now)).toList();
    final bySource = <SourceProgressRow>[];

    void addSource(ReviewSource src, Iterable<_TaggedCard> cards) {
      final list = cards.toList();
      if (list.isEmpty && src.kind != ReviewSourceKind.all) return;
      final agg = _aggregate(list, now);
      final ids = list.map((t) => t.word.wordId).toSet();
      final revCount = events.where((e) {
        if (!ids.contains(e.cardId)) return false;
        if (rangeStart != null && e.reviewedAt.isBefore(rangeStart)) {
          return false;
        }
        return true;
      }).length;
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
                t.importId == src.importId;
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
    );
  }

  DateTime? _rangeStart(EventRange range, DateTime now) {
    switch (range) {
      case EventRange.all:
        return null;
      case EventRange.d7:
        return now.subtract(const Duration(days: 7));
      case EventRange.d30:
        return now.subtract(const Duration(days: 30));
      case EventRange.d90:
        return now.subtract(const Duration(days: 90));
    }
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
            t.importId != f.source.importId) {
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

  List<RetentionPoint> _curveFromEvents(List<ReviewEventRecord> events) {
    final bucketRecalled = <int, int>{};
    final bucketTotal = <int, int>{};
    for (final e in events) {
      final b = _bucketFor(e.prevIntervalDays);
      bucketTotal[b] = (bucketTotal[b] ?? 0) + 1;
      if (e.recalled) bucketRecalled[b] = (bucketRecalled[b] ?? 0) + 1;
    }
    final curve = <RetentionPoint>[];
    for (final b in intervalBuckets) {
      final total = bucketTotal[b] ?? 0;
      if (total == 0) continue;
      curve.add(RetentionPoint(
        intervalBucketDays: b,
        retention: (bucketRecalled[b] ?? 0) / total,
        sampleSize: total,
      ));
    }
    return curve;
  }

  int _bucketFor(int intervalDays) {
    for (final b in intervalBuckets) {
      if (intervalDays <= b) return b;
    }
    return intervalBuckets.last;
  }
}
