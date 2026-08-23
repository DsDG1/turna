// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/service/locator.dart';

/// Scalar storage type of a backed-up preference key.
enum BackupPrefType { bool_, int_, double_, string, stringList }

/// One entry of the unified backup manifest: either an exact key or a dynamic
/// prefix (per-course settings), paired with the scalar type(s) the key may
/// legally hold. Use [primaryType] for read/write dispatch — prefix entries
/// declare a single-element [allowedTypes] set today, and the getter keeps
/// that invariant in one place.
class BackupPrefEntry {
  const BackupPrefEntry(this.key, this.type)
      : prefix = null,
        allowedTypes = const {};

  const BackupPrefEntry.prefix(this.prefix, this.allowedTypes)
      : key = null,
        type = null;

  /// Exact prefs key (null for prefix entries).
  final String? key;

  /// Dynamic key prefix (null for exact entries).
  final String? prefix;

  /// Type for exact entries (null for prefix entries).
  final BackupPrefType? type;

  /// Legal types for prefix entries (empty for exact entries).
  final Set<BackupPrefType> allowedTypes;

  bool get isPrefix => prefix != null;

  /// The single type used for read/write dispatch.
  BackupPrefType get primaryType => type ?? allowedTypes.first;

  bool matches(String candidate) =>
      isPrefix ? candidate.startsWith(prefix!) : candidate == key;

  bool acceptsType(BackupPrefType candidate) =>
      isPrefix ? allowedTypes.contains(candidate) : candidate == type;
}

/// Single source of truth for which SharedPreferences keys travel inside a
/// backup — shared by the local JSON export (ExportService) and the remote
/// WebDAV snapshot (BackupSnapshotService). Before this policy existed the
/// two pipelines each maintained their own manifest and had already drifted;
/// any key listed here round-trips through both paths automatically.
///
/// Rules:
///  * Keys are included only when explicitly listed (exact or prefix) AND not
///    matched by an exclusion rule below.
///  * Device-local state (remote backup config / device id, per-day counters),
///    system health events, restore journal markers and any credential are
///    structurally excluded — they must never leave the device.
///  * [sanitizeForSerialization] strips embedded secrets (AI engine config
///    API key) at the serialization boundary so no post-export scrubbing is
///    needed.
abstract final class BackupManifestPolicy {
  /// Exact keys with their scalar types, grouped by domain.
  static const List<BackupPrefEntry> typedEntries = <BackupPrefEntry>[
    // ── marker / game state ──
    BackupPrefEntry(LocalStateKeys.initialized, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.score, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.streak, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.lastStreakDate, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.lessonsCompleted, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.perfectLessons, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.streakWasBroken, BackupPrefType.bool_),
    BackupPrefEntry(
        LocalStateKeys.streakProtectedDays, BackupPrefType.stringList),
    BackupPrefEntry(LocalStateKeys.streakAutoUseVoucher, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.wordsLearned, BackupPrefType.int_),
    // ── per-lesson progress ──
    BackupPrefEntry(
        LocalStateKeys.completedLessonIds, BackupPrefType.stringList),
    BackupPrefEntry(LocalStateKeys.perfectLessonIds, BackupPrefType.stringList),
    // ── currency / achievements / cosmetics ──
    BackupPrefEntry(LocalStateKeys.gems, BackupPrefType.int_),
    // v1 achievement list: read-only migration input, exported for
    // downgrade compatibility.
    BackupPrefEntry(LocalStateKeys.achievements, BackupPrefType.stringList),
    // Achievements v2: versioned state, metric projection, migration marker.
    BackupPrefEntry(LocalStateKeys.achievementsStateV2, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.achievementsProjectionV1, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.achievementsMigrationVersion, BackupPrefType.int_),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsUnlocked, BackupPrefType.stringList),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedRing, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedAvatarRing, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedProfileTheme, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedCardBack, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.cosmeticsEquippedCompletionEffect,
        BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedSoundPack, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.cosmeticsEquippedMascotAccessory, BackupPrefType.string),
    // ── SRS / mistakes ──
    BackupPrefEntry(LocalStateKeys.srsState, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.lessonWordLinks, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.grammarReviewState, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.mistakeLog, BackupPrefType.string),
    // ── study logs / daily stats ──
    BackupPrefEntry('study.logs', BackupPrefType.string),
    BackupPrefEntry('study.logs.recent', BackupPrefType.string),
    BackupPrefEntry('study.dailyStats', BackupPrefType.string),
    // ── FSRS tuning (loss of these is unrecoverable) ──
    BackupPrefEntry(LocalStateKeys.srsDesiredRetention, BackupPrefType.double_),
    BackupPrefEntry(LocalStateKeys.srsFsrsParameters, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.srsFsrsOptimizedAt, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.srsFsrsOptimizedReviews, BackupPrefType.int_),
    // ── feedback settings ──
    BackupPrefEntry(LocalStateKeys.themeMode, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.soundEffects, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.haptic, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.ttsSpeed, BackupPrefType.double_),
    BackupPrefEntry(LocalStateKeys.ttsEngine, BackupPrefType.string),
    BackupPrefEntry(
        LocalStateKeys.ttsAvailabilityPromptShown, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.dailyReminderEnabled, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.dailyReminderHour, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.dailyReminderMinute, BackupPrefType.int_),
    BackupPrefEntry(
        LocalStateKeys.contentVersionAcknowledged, BackupPrefType.string),
    // ── accessibility / ui ──
    BackupPrefEntry(LocalStateKeys.autoRotate, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.uiLocale, BackupPrefType.string),
    BackupPrefEntry(LocalStateKeys.textScale, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.reducedMotion, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.highContrast, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.dyslexiaFont, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.sensoryReduce, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.focusMode, BackupPrefType.bool_),
    // ── Anki settings ──
    BackupPrefEntry(LocalStateKeys.ankiPreRenderEnabled, BackupPrefType.bool_),
    BackupPrefEntry(LocalStateKeys.ankiCaptureDelaySec, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.ankiLiteThreshold, BackupPrefType.int_),
    BackupPrefEntry(LocalStateKeys.ankiForceDisableJs, BackupPrefType.bool_),
    BackupPrefEntry('anki.dailyNewLimit', BackupPrefType.int_),
    BackupPrefEntry('anki.dailyReviewLimit', BackupPrefType.int_),
    BackupPrefEntry('anki.dailyChallengeIncludesAnki', BackupPrefType.bool_),
    // ── course state ──
    BackupPrefEntry(PrefsConstants.courseScope, BackupPrefType.string),
    BackupPrefEntry(PrefsConstants.courseOrder, BackupPrefType.stringList),
    // ── AI (engineConfig carries the API key — sanitized on write) ──
    BackupPrefEntry(LocalStateKeys.aiEngineConfig, BackupPrefType.string),
    BackupPrefEntry('ai.savedExplanations', BackupPrefType.string),
    BackupPrefEntry('ai.replyLanguage', BackupPrefType.string),
    BackupPrefEntry('ai.depth', BackupPrefType.string),
    BackupPrefEntry('ai.allowRevealAnswer', BackupPrefType.bool_),
    BackupPrefEntry('ai.injectLearnerContext', BackupPrefType.bool_),
    BackupPrefEntry('ai.recentCompanionTasks', BackupPrefType.string),
    // ── fun lab ──
    BackupPrefEntry(LocalStateKeys.funAutoAnswer, BackupPrefType.bool_),
    BackupPrefEntry(
        LocalStateKeys.funAllAchievementsUnlocked, BackupPrefType.bool_),
    // ── account + language ──
    BackupPrefEntry(PrefsConstants.currentLanguage, BackupPrefType.string),
    BackupPrefEntry(PrefsConstants.authUser, BackupPrefType.string),
  ];

  /// Dynamic per-course settings that round-trip by prefix.
  static const List<BackupPrefEntry> prefixEntries = <BackupPrefEntry>[
    BackupPrefEntry.prefix('settings.autoReadOnTap.', {BackupPrefType.bool_}),
    BackupPrefEntry.prefix('settings.nativeLang.', {BackupPrefType.string}),
  ];

  /// Excluded prefixes: device-local state, ephemeral per-day counters,
  /// restore bookkeeping. Anything under `remoteBackup.` is also where the
  /// legacy plaintext password lived — belt and braces against it ever being
  /// listed above by mistake.
  static const List<String> excludedPrefixes = <String>[
    'remoteBackup.',
    'anki.deck.',
    'restore.',
  ];

  static const Set<String> excludedExactKeys = <String>{
    LocalStateKeys.systemHealthEvent,
    'anki.newDoneToday',
    'anki.reviewDoneToday',
    'anki.limitsDate',
  };

  static bool shouldInclude(String key) {
    for (final prefix in excludedPrefixes) {
      if (key.startsWith(prefix)) return false;
    }
    if (excludedExactKeys.contains(key)) return false;
    for (final entry in typedEntries) {
      if (entry.key == key) return true;
    }
    for (final entry in prefixEntries) {
      if (key.startsWith(entry.prefix!)) return true;
    }
    return false;
  }

  /// The manifest entry governing [key], or null when the key is not
  /// backup-eligible.
  static BackupPrefEntry? entryFor(String key) {
    for (final entry in typedEntries) {
      if (entry.key == key) return entry;
    }
    for (final entry in prefixEntries) {
      if (key.startsWith(entry.prefix!)) return entry;
    }
    return null;
  }

  /// Serialization-boundary secret scrubbing. Returns the value safe to write
  /// into any backup, or null when the value must be dropped entirely.
  static Object? sanitizeForSerialization(String key, Object? value) {
    if (!shouldInclude(key)) return null;
    if (key == LocalStateKeys.aiEngineConfig && value is String) {
      return stripApiKeyFromEngineConfig(value);
    }
    return value;
  }

  /// Removes the API key from a persisted AI engine config JSON blob. The
  /// non-secret parts (preset, models, base url) still round-trip so a
  /// restore only asks for the secret again. A corrupt blob has no usable
  /// non-secret settings — dropping it is safer than copying an opaque string
  /// that might contain a legacy credential.
  static String stripApiKeyFromEngineConfig(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded['apiKey'] = '';
        return jsonEncode(decoded);
      }
    } catch (_) {
      // Corrupt config: fall through to the dropped value.
    }
    return '';
  }
}
