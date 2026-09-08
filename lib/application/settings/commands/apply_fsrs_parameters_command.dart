// Dart imports:
import 'dart:convert';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/fsrs_optimizer.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Wall-clock timings for the four optimization stages, surfaced so
/// regressions (e.g. a DAO read blowing up) are observable in debug logs.
class FsrsOptimizeTimings {
  const FsrsOptimizeTimings({
    required this.readMs,
    required this.optimizeMs,
    required this.applyMs,
  });

  final int readMs;
  final int optimizeMs;
  final int applyMs;
}

/// Outcome of a full local FSRS optimization run.
sealed class FsrsOptimizeOutcome {
  const FsrsOptimizeOutcome();
}

final class FsrsOptimizeNeedMoreReviews extends FsrsOptimizeOutcome {
  const FsrsOptimizeNeedMoreReviews();
}

final class FsrsOptimizeRejected extends FsrsOptimizeOutcome {
  const FsrsOptimizeRejected({required this.reason});

  final String reason;
}

final class FsrsOptimizeAccepted extends FsrsOptimizeOutcome {
  const FsrsOptimizeAccepted({required this.timings});

  final FsrsOptimizeTimings timings;
}

final class FsrsOptimizeFailed extends FsrsOptimizeOutcome {
  const FsrsOptimizeFailed({
    required this.code,
    required this.userMessage,
    this.retryable = false,
  });

  final String code;
  final String userMessage;
  final bool retryable;
}

/// Applies FSRS weight changes transactionally across BOTH scheduler
/// consumers (SRS + grammar review): parameters are validated, the previous
/// weights are captured, both consumers are updated, and only when every
/// step succeeds is the "optimized" metadata (timestamp + review count)
/// written. Any failure restores the previous weights — the empty-catch +
/// unconditional-metadata pattern this replaces could mark a failed fit as
/// successful.
///
/// [optimizeInBackground] runs the CPU-heavy gradient fit on a background
/// isolate ([Isolate.run]) so 40 epochs over the full review history never
/// occupy the UI thread; the DAO read stays on the main isolate because it
/// is async I/O.
class ApplyFsrsParametersCommand {
  const ApplyFsrsParametersCommand();

  static const int expectedParameterCount = 21;

  /// Full pipeline: read history → isolate fit → validate → apply.
  Future<FsrsOptimizeOutcome> optimizeInBackground() async {
    final readWatch = Stopwatch()..start();
    final List<ReviewEventRecord> events;
    try {
      final languageCode = getIt.isRegistered<SrsProvider>()
          ? getIt<SrsProvider>().languageFilter
          : null;
      events = await getIt<ReviewHistoryDao>().allEvents(
        languageCode: languageCode,
      );
    } on Object catch (error) {
      return FsrsOptimizeFailed(
        code: 'fsrs.readFailed',
        userMessage: '读取复习历史失败，无法优化。${_brief(error)}',
        retryable: true,
      );
    }
    readWatch.stop();

    final optimizeWatch = Stopwatch()..start();
    FsrsOptimizeResult result;
    try {
      result = await Isolate.run(() {
        return FsrsLiteOptimizer().optimize(events);
      });
    } on Object catch (error) {
      return FsrsOptimizeFailed(
        code: 'fsrs.optimizeFailed',
        userMessage: '优化计算失败。${_brief(error)}',
        retryable: true,
      );
    }
    optimizeWatch.stop();

    if (result.message == 'need_more_reviews') {
      return const FsrsOptimizeNeedMoreReviews();
    }
    if (!result.accepted) {
      return FsrsOptimizeRejected(reason: result.message);
    }

    final applyWatch = Stopwatch()..start();
    final applied =
        await _apply(result.parameters, reviewCount: result.reviewCount);
    applyWatch.stop();
    if (applied is SettingsOperationFailure) {
      return FsrsOptimizeFailed(
        code: applied.code,
        userMessage: applied.userMessage,
        retryable: applied.retryable,
      );
    }
    if (kDebugMode) {
      debugPrint('FSRS optimize: read=${readWatch.elapsedMilliseconds}ms '
          'fit=${optimizeWatch.elapsedMilliseconds}ms '
          'apply=${applyWatch.elapsedMilliseconds}ms '
          '(${result.reviewCount} reviews / ${result.cardCount} cards)');
    }
    return FsrsOptimizeAccepted(
      timings: FsrsOptimizeTimings(
        readMs: readWatch.elapsedMilliseconds,
        optimizeMs: optimizeWatch.elapsedMilliseconds,
        applyMs: applyWatch.elapsedMilliseconds,
      ),
    );
  }

  /// Validates and applies explicit [parameters] (or null to clear custom
  /// weights — clearing goes through the same transactional path).
  Future<SettingsOperationResult> execute(
    List<double>? parameters, {
    required int reviewCount,
  }) =>
      _apply(parameters, reviewCount: reviewCount);

  Future<SettingsOperationResult> _apply(
    List<double>? parameters, {
    required int reviewCount,
  }) async {
    if (parameters != null) {
      if (parameters.length != expectedParameterCount) {
        return SettingsOperationFailure(
          code: 'fsrs.invalidLength',
          userMessage: '参数数量不正确（${parameters.length}/'
              '$expectedParameterCount），已取消。',
        );
      }
      final outOfRange = parameters.any((value) => !value.isFinite);
      if (outOfRange) {
        return const SettingsOperationFailure(
          code: 'fsrs.invalidValue',
          userMessage: '参数包含无效数值，已取消。',
        );
      }
    }

    final srs = getIt<SrsProvider>();
    final grammar = getIt<GrammarReviewProvider>();
    final settings = getIt<SettingsProvider>();

    // Before-image: the stored weights (empty string = package defaults).
    final previousWeights = srs.appPrefs.preferences
        .getString(LocalStateKeys.srsFsrsParameters, defaultValue: '')
        .getValue();

    try {
      await srs.setFsrsParameters(parameters);
      await grammar.setFsrsParameters(parameters);
    } on Object catch (error) {
      // Restore both consumers to the stored before-image.
      try {
        final restored =
            previousWeights.isEmpty ? null : _decodeWeights(previousWeights);
        await srs.setFsrsParameters(restored);
        await grammar.setFsrsParameters(restored);
      } catch (_) {
        // Restoration failed: prefs may hold the new weights for one
        // consumer. Report as non-retryable corruption guard.
        return SettingsOperationFailure(
          code: 'fsrs.rollbackFailed',
          userMessage: '应用参数失败且恢复旧参数时出错，'
              '建议清除自定义参数后重试。${_brief(error)}',
        );
      }
      return SettingsOperationFailure(
        code: 'fsrs.applyFailed',
        userMessage: '应用参数失败，已恢复原参数。${_brief(error)}',
        retryable: true,
      );
    }

    // Metadata is only written after BOTH consumers succeeded.
    if (parameters == null) {
      await srs.appPrefs.setString(LocalStateKeys.srsFsrsOptimizedAt, '');
      await srs.appPrefs.setInt(LocalStateKeys.srsFsrsOptimizedReviews, 0);
    } else {
      await srs.appPrefs.setString(
        LocalStateKeys.srsFsrsOptimizedAt,
        DateTime.now().toIso8601String(),
      );
      await srs.appPrefs.setInt(
        LocalStateKeys.srsFsrsOptimizedReviews,
        reviewCount,
      );
    }
    settings.reload();
    return const SettingsOperationSuccess();
  }

  static List<double>? _decodeWeights(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<num>()
            .map((value) => value.toDouble())
            .toList();
      }
    } catch (_) {
      // Fall through: restore defaults.
    }
    return null;
  }

  static String _brief(Object error) {
    final firstLine = error.toString().split('\n').first;
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }
}
