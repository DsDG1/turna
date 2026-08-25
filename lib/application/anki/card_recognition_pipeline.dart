// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:crypto/crypto.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki_practice/embedded_options.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Where a recognition outcome came from — the preview UI surfaces this so a
/// user never mistakes a fallback for an AI verdict.
enum CardRecognitionSource { rule, persisted, ai, fallback }

/// Versioned recognition outcome: the mapping plus everything the preview
/// needs to be explainable (Plan 1 Phase 4 step 5).
class CardRecognitionResult {
  const CardRecognitionResult({
    required this.mapping,
    required this.confidence,
    required this.source,
    required this.evidence,
    this.warnings = const [],
  });

  final NotetypeMapping mapping;

  /// 0..1. Below [CardRecognitionPipeline.lowConfidenceThreshold] the
  /// preview expands the row and asks for confirmation.
  final double confidence;
  final CardRecognitionSource source;
  final String evidence;
  final List<String> warnings;

  bool get needsConfirmation =>
      confidence < CardRecognitionPipeline.lowConfidenceThreshold ||
      warnings.isNotEmpty;
}

/// Versioned fingerprint of a notetype's structure. Two notetypes with the
/// same signature are treated as "the same kind" and share persisted user
/// rules; the recognizer version is part of the key so a recognizer upgrade
/// re-validates instead of silently reusing old verdicts.
class NotetypeSignature {
  const NotetypeSignature._(this.value);

  final String value;

  static NotetypeSignature of(AnkiNotetype notetype, {int version = 1}) {
    final templateFingerprint = notetype.templates.isEmpty
        ? 't${notetype.templateNames.length}'
        : md5
            .convert(utf8.encode(notetype.templates
                .map((t) => '${t.qfmt}\u2028${t.afmt}')
                .join('\u2029')))
            .toString()
            .substring(0, 12);
    final fields =
        notetype.fieldNames.map((f) => f.trim().toLowerCase()).join('\u2028');
    return NotetypeSignature._(
      'v$version|cloze=${notetype.isCloze ? 1 : 0}'
      '|f=${notetype.fieldNames.length}:$fields'
      '|tpl=$templateFingerprint',
    );
  }
}

/// Privacy-safe aggregate of what the notes of one notetype look like. Only
/// shapes (counts, length buckets, media/cloze flags) — never field content
/// — leave the device, which strictly narrows the existing AI prompt that
/// already sent notetype/field/template names.
class NotetypeSampleFeatures {
  const NotetypeSampleFeatures({
    required this.sampleCount,
    required this.fieldStats,
  });

  final int sampleCount;
  final List<NotetypeFieldStats> fieldStats;

  static NotetypeSampleFeatures extract({
    required AnkiNotetype notetype,
    required List<AnkiNote> notes,
    int maxSamples = 20,
  }) {
    final samples = notes.where((n) => n.mid == notetype.id).take(maxSamples);
    final stats = [
      for (var i = 0; i < notetype.fieldNames.length; i++)
        NotetypeFieldStats.aggregate(
          fieldName: notetype.fieldNames[i],
          values: [
            for (final note in samples)
              if (i < note.fields.length) note.fields[i],
          ],
        ),
    ];
    return NotetypeSampleFeatures(
      sampleCount: samples.length,
      fieldStats: stats,
    );
  }

  Map<String, dynamic> toPromptJson() => {
        'sampleCount': sampleCount,
        'fields': [for (final f in fieldStats) f.toPromptJson()],
      };
}

/// Per-field shape: non-empty ratio, average length bucket, and media/cloze
/// markers — the evidence a classifier needs without the text itself.
class NotetypeFieldStats {
  const NotetypeFieldStats({
    required this.fieldName,
    required this.nonEmptyRatio,
    required this.avgLength,
    required this.audioRatio,
    required this.imageRatio,
    required this.clozeRatio,
    required this.optionLikeRatio,
  });

  final String fieldName;
  final double nonEmptyRatio;
  final double avgLength;
  final double audioRatio;
  final double imageRatio;
  final double clozeRatio;
  final double optionLikeRatio;

  static final _audioRe = RegExp(r'\[sound:[^\]]+\]');
  static final _imageRe = RegExp(r'<img[^>]+>', caseSensitive: false);
  static final _clozeRe = RegExp(r'\{\{c\d+::');
  static final _optionLikeRe =
      RegExp(r'^\s*[A-Ha-h][).：.、]\s*\S+|^\s*(选项|答案)[\s:：]', multiLine: true);

  factory NotetypeFieldStats.aggregate({
    required String fieldName,
    required List<String> values,
  }) {
    if (values.isEmpty) {
      return NotetypeFieldStats(
        fieldName: fieldName,
        nonEmptyRatio: 0,
        avgLength: 0,
        audioRatio: 0,
        imageRatio: 0,
        clozeRatio: 0,
        optionLikeRatio: 0,
      );
    }
    var nonEmpty = 0;
    var audio = 0;
    var image = 0;
    var cloze = 0;
    var optionLike = 0;
    var totalLen = 0;
    for (final raw in values) {
      final v = raw.trim();
      if (v.isNotEmpty) nonEmpty++;
      totalLen += v.length;
      if (_audioRe.hasMatch(v)) audio++;
      if (_imageRe.hasMatch(v)) image++;
      if (_clozeRe.hasMatch(v)) cloze++;
      if (_optionLikeRe.hasMatch(v)) optionLike++;
    }
    return NotetypeFieldStats(
      fieldName: fieldName,
      nonEmptyRatio: nonEmpty / values.length,
      avgLength: totalLen / values.length,
      audioRatio: audio / values.length,
      imageRatio: image / values.length,
      clozeRatio: cloze / values.length,
      optionLikeRatio: optionLike / values.length,
    );
  }

  Map<String, dynamic> toPromptJson() => {
        'name': fieldName,
        'nonEmpty': nonEmptyRatio.toStringAsFixed(2),
        'avgLen': avgLength.round(),
        'audio': audioRatio.toStringAsFixed(2),
        'image': imageRatio.toStringAsFixed(2),
        'cloze': clozeRatio.toStringAsFixed(2),
        'optionLike': optionLikeRatio.toStringAsFixed(2),
      };
}

/// Persisted user rules: one JSON blob per signature key, stored under
/// `anki.notetype_rule.v2.<signature>`. Written when the user confirms a
/// mapping (explicit edit or completing an import with AI results);
/// consulted before any AI call so the same kind of notetype is recognized
/// offline on the next import.
class AnkiNotetypeRuleStore {
  AnkiNotetypeRuleStore([AppPrefs? prefs]) : _prefs = prefs;

  static const keyPrefix = 'anki.notetype_rule.v2.';

  final AppPrefs? _prefs;

  String _key(String signature) => '$keyPrefix$signature';

  NotetypeMapping? load(String signature) {
    final prefs = _tryPrefs();
    if (prefs == null) return null;
    final raw = prefs.preferences
        .getString(_key(signature), defaultValue: '')
        .getValue();
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = _parseType(json['type']?.toString() ?? '');
      if (type == null) return null;
      return NotetypeMapping(
        type: type,
        frontFieldIndex: (json['front'] as num?)?.toInt() ?? 0,
        backFieldIndex: (json['back'] as num?)?.toInt() ?? 1,
        reason: 'persisted rule v${json['v'] ?? '?'}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String signature, NotetypeMapping mapping) async {
    final prefs = _tryPrefs();
    if (prefs == null) return;
    await prefs.setString(
      _key(signature),
      jsonEncode({
        'v': CardRecognitionPipeline.recognizerVersion,
        'type': mapping.type.name,
        'front': mapping.frontFieldIndex,
        'back': mapping.backFieldIndex,
      }),
    );
  }

  AppPrefs? _tryPrefs() {
    final own = _prefs;
    if (own != null) return own;
    if (!getIt.isRegistered<AppPrefs>()) return null;
    return getIt<AppPrefs>();
  }

  static NotetypeMappingType? _parseType(String raw) {
    for (final t in NotetypeMappingType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// Plan 1 Phase 4: versioned pipeline that replaces the per-notetype serial
/// AI loop. Contract:
///   signature -> persisted rule -> deterministic rule -> one batched AI
///   request (privacy-safe features only) -> consistency check -> result
///   with mapping + confidence + evidence + source + warnings.
///
/// High-confidence rule hits never call the AI, and the remaining notetypes
/// travel in a single request instead of N serial ones.
class CardRecognitionPipeline {
  CardRecognitionPipeline({AiEngine? engine, AnkiNotetypeRuleStore? ruleStore})
      : _engine = engine,
        _ruleStore = ruleStore ?? AnkiNotetypeRuleStore();

  static const recognizerVersion = 1;
  static const lowConfidenceThreshold = 0.6;

  final AiEngine? _engine;
  final AnkiNotetypeRuleStore _ruleStore;

  Future<Map<int, CardRecognitionResult>> recognizeAll({
    required AiEngineConfig config,
    required Map<int, AnkiNotetype> notetypes,
    required List<AnkiNote> notes,
  }) async {
    final results = <int, CardRecognitionResult>{};
    final signatures = <int, NotetypeSignature>{};
    final pendingAi = <int, AnkiNotetype>{};

    for (final entry in notetypes.entries) {
      final signature = NotetypeSignature.of(
        entry.value,
        version: recognizerVersion,
      );
      signatures[entry.key] = signature;

      final persisted = _ruleStore.load(signature.value);
      if (persisted != null) {
        results[entry.key] = CardRecognitionResult(
          mapping: persisted,
          confidence: 0.95,
          source: CardRecognitionSource.persisted,
          evidence: '已保存的映射规则（识别器 v$recognizerVersion）',
        );
        continue;
      }

      final rule = _applyDeterministicRules(
        entry.value,
        notes,
        allowFieldNameRule: !config.isComplete || _engine == null,
      );
      if (rule != null) {
        results[entry.key] = rule;
        continue;
      }
      pendingAi[entry.key] = entry.value;
    }

    if (pendingAi.isNotEmpty && config.isComplete && _engine != null) {
      final aiResults = await _recognizeViaAi(
          config: config, pending: pendingAi, notes: notes);
      results.addAll(aiResults);
    }

    // Anything still undecided (no AI configured, request failed, parse
    // failed) falls back to the legacy heuristic — labeled as such.
    for (final entry in notetypes.entries) {
      if (results.containsKey(entry.key)) continue;
      results[entry.key] = CardRecognitionResult(
        mapping: AnkiCardAdapter.inferMapping(entry.value),
        confidence: 0.4,
        source: CardRecognitionSource.fallback,
        evidence: '启发式回退（字段名模式）',
        warnings: const ['未能获得高置信识别结果，建议人工确认'],
      );
    }

    for (final key in results.keys.toList()) {
      results[key] = _validate(results[key]!, notetypes[key], notes);
    }
    return results;
  }

  /// Deterministic rules, in confidence order. A non-null return skips the
  /// AI entirely for that notetype (Plan step 3).
  CardRecognitionResult? _applyDeterministicRules(
    AnkiNotetype notetype,
    List<AnkiNote> notes, {
    required bool allowFieldNameRule,
  }) {
    if (notetype.isCloze) {
      return CardRecognitionResult(
        mapping: const NotetypeMapping(
          type: NotetypeMappingType.cloze,
          reason: 'Cloze notetype flag',
        ),
        confidence: 0.95,
        source: CardRecognitionSource.rule,
        evidence: 'notetype 标记为 Cloze',
      );
    }

    final layout = EmbeddedOptionsParser.detectChoiceLayout(
      fieldNames: notetype.fieldNames,
      notetypeName: notetype.name,
    );
    if (layout != null) {
      return CardRecognitionResult(
        mapping: NotetypeMapping(
          type: NotetypeMappingType.multipleChoice,
          frontFieldIndex: layout.promptIndex,
          backFieldIndex: layout.answerIndex,
          reason: 'Choice option fields detected',
        ),
        confidence: 0.9,
        source: CardRecognitionSource.rule,
        evidence: '检测到结构化选项字段（${notetype.fieldNames.join('/')}）',
      );
    }

    // Sample-driven listening rule: front face is dominated by audio and the
    // answer side is short — the shape of a listen-and-answer deck.
    final features = NotetypeSampleFeatures.extract(
      notetype: notetype,
      notes: notes,
    );
    final stats = features.fieldStats;
    if (stats.length >= 2 &&
        stats.first.audioRatio >= 0.7 &&
        stats.first.avgLength < 80 &&
        stats.last.nonEmptyRatio >= 0.8) {
      return CardRecognitionResult(
        mapping: NotetypeMapping(
          type: NotetypeMappingType.listenPick,
          frontFieldIndex: 0,
          backFieldIndex: notetype.fieldNames.length > 1 ? 1 : 0,
          reason: 'front-face audio dominates samples',
        ),
        confidence: 0.8,
        source: CardRecognitionSource.rule,
        evidence: '样本特征：正面音频占比 '
            '${(stats.first.audioRatio * 100).round()}%',
      );
    }

    // The legacy adapter already has stable field-name rules for ordinary
    // vocabulary, expression and named quiz layouts. Treat those explicit
    // matches as local recognition successes; only the truly generic
    // first-field/second-field default remains a low-confidence fallback.
    final inferred = AnkiCardAdapter.inferMapping(notetype);
    if (allowFieldNameRule && inferred.reason != 'Default flip card mapping') {
      return CardRecognitionResult(
        mapping: inferred,
        confidence: 0.8,
        source: CardRecognitionSource.rule,
        evidence: '根据字段名称自动识别',
      );
    }

    return null;
  }

  Future<Map<int, CardRecognitionResult>> _recognizeViaAi({
    required AiEngineConfig config,
    required Map<int, AnkiNotetype> pending,
    required List<AnkiNote> notes,
  }) async {
    try {
      final payload = [
        for (final entry in pending.entries)
          {
            'id': entry.key,
            'name': entry.value.name,
            'isCloze': entry.value.isCloze,
            'fields': entry.value.fieldNames,
            'templates': entry.value.templateNames,
            'features': NotetypeSampleFeatures.extract(
              notetype: entry.value,
              notes: notes,
            ).toPromptJson(),
          },
      ];
      final result = await _engine!.chat(
        config: config,
        messages: [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content': jsonEncode({'notetypes': payload})
          },
        ],
        temperature: 0.2,
        timeout: const Duration(seconds: 45),
      );
      return _parseBatchReply(result.content, pending);
    } catch (e) {
      logger.w('CardRecognitionPipeline AI batch failed: $e');
      return const {};
    }
  }

  static const _systemPrompt = '''
You are an Anki deck analysis assistant. For each notetype below, decide which
Turna card type it best maps to:

1. `ankiCard` — generic flip card (non-language content, or ambiguous fields)
2. `wordEntry` — vocabulary card (front is a word/term, back is definition/translation)
3. `expression` — sentence/expression card (fill-in-the-blank exercises)
4. `cloze` — cloze deletion card ({{c1::}} markers)
5. `multipleChoice` — choice quiz (option fields or embedded A/B/C/D options)
6. `fillBlank` — type-the-answer fill-in-the-blank
7. `listenPick` — listening exercise driven by front-face audio

Besides names and fields, each notetype carries privacy-safe aggregate
features of up to 20 sample notes: per-field non-empty ratio, average length,
audio/image/cloze/option-like ratios. Use them as evidence: short front +
medium back = wordEntry; long front with sentence shape = expression; audio on
the front = listenPick; option-like text on the back = multipleChoice.

Respond with ONLY a JSON object (no markdown fences):
{"results": [{"id": <notetype id>, "mapping": "<type>",
  "frontField": "<exact field name>", "backField": "<exact field name>",
  "confidence": 0.0-1.0, "reason": "<brief evidence-based explanation>"}]}

One entry per input notetype. frontField/backField must be exact field names.
''';

  Map<int, CardRecognitionResult> _parseBatchReply(
    String reply,
    Map<int, AnkiNotetype> pending,
  ) {
    try {
      var cleaned = reply.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceAll(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final rows = (json['results'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final byId = {
        for (final row in rows) (row['id'] as num?)?.toInt() ?? -1: row,
      };
      final results = <int, CardRecognitionResult>{};
      for (final entry in pending.entries) {
        final row = byId[entry.key];
        if (row == null) continue;
        final notetype = entry.value;
        final type = _parseMappingType(row['mapping']?.toString() ?? '');
        if (type == null) continue;
        final frontField = row['frontField']?.toString() ?? '';
        final backField = row['backField']?.toString() ?? '';
        final frontIdx = notetype.fieldNames.indexOf(frontField);
        final backIdx = notetype.fieldNames.indexOf(backField);
        final warnings = <String>[];
        if (frontIdx < 0 || backIdx < 0) {
          warnings.add('AI 返回的字段名不在 notetype 字段列表中，已回退到默认索引');
        }
        var confidence =
            double.tryParse(row['confidence']?.toString() ?? '') ?? 0.5;
        if (confidence < 0 || confidence > 1) confidence = 0.5;
        results[entry.key] = CardRecognitionResult(
          mapping: NotetypeMapping(
            type: type,
            frontFieldIndex: frontIdx >= 0 ? frontIdx : 0,
            backFieldIndex: backIdx >= 0
                ? backIdx
                : (frontIdx == 0 && notetype.fieldNames.length > 1 ? 1 : 0),
            reason: row['reason']?.toString() ?? '',
          ),
          confidence: confidence.clamp(0.0, 1.0),
          source: CardRecognitionSource.ai,
          evidence: row['reason']?.toString().isNotEmpty == true
              ? row['reason'].toString()
              : 'AI 批量识别',
          warnings: warnings,
        );
      }
      return results;
    } catch (e) {
      logger.w('CardRecognitionPipeline parse failed: $e');
      return const {};
    }
  }

  NotetypeMappingType? _parseMappingType(String raw) {
    switch (raw.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '')) {
      case 'ankicard':
      case 'basic':
        return NotetypeMappingType.ankiCard;
      case 'wordentry':
      case 'word':
        return NotetypeMappingType.wordEntry;
      case 'expression':
      case 'sentence':
        return NotetypeMappingType.expression;
      case 'cloze':
        return NotetypeMappingType.cloze;
      case 'multiplechoice':
      case 'mcq':
      case 'singlechoice':
      case 'multiselect':
      case 'multichoice':
      case 'multipleanswer':
      case 'choice':
        return NotetypeMappingType.multipleChoice;
      case 'fillblank':
      case 'typeanswer':
        return NotetypeMappingType.fillBlank;
      case 'listenpick':
      case 'listening':
        return NotetypeMappingType.listenPick;
      default:
        return null;
    }
  }

  /// Consistency validation (Plan step 6): field indexes must be in range
  /// and distinct on multi-field notetypes; an AI choice/answer mapping on
  /// a notetype whose samples carry no option-like or short-answer shape is
  /// downgraded with a warning instead of silently trusted.
  CardRecognitionResult _validate(
    CardRecognitionResult result,
    AnkiNotetype? notetype,
    List<AnkiNote> notes,
  ) {
    if (notetype == null) return result;
    final warnings = [...result.warnings];
    var confidence = result.confidence;
    final fieldCount = notetype.fieldNames.length;
    final mapping = result.mapping;

    if (mapping.frontFieldIndex >= fieldCount ||
        mapping.backFieldIndex >= fieldCount ||
        mapping.frontFieldIndex < 0 ||
        mapping.backFieldIndex < 0) {
      warnings.add('字段索引超出范围');
      confidence *= 0.5;
    } else if (fieldCount > 1 &&
        mapping.frontFieldIndex == mapping.backFieldIndex) {
      warnings.add('正面与答案使用了同一个字段');
      confidence *= 0.7;
    }

    if (result.source == CardRecognitionSource.ai) {
      final shapeMismatch = _aiShapeMismatch(mapping.type, notetype, notes);
      if (shapeMismatch != null) {
        warnings.add(shapeMismatch);
        confidence *= 0.6;
      }
    }

    if (warnings.length == result.warnings.length) return result;
    return CardRecognitionResult(
      mapping: mapping,
      confidence: confidence.clamp(0.0, 1.0),
      source: result.source,
      evidence: result.evidence,
      warnings: warnings,
    );
  }

  /// Sample-shape cross-check for AI verdicts. Deterministic-rule and
  /// persisted verdicts are already evidence-backed by construction.
  String? _aiShapeMismatch(
    NotetypeMappingType type,
    AnkiNotetype notetype,
    List<AnkiNote> notes,
  ) {
    final features = NotetypeSampleFeatures.extract(
      notetype: notetype,
      notes: notes,
    );
    if (features.sampleCount == 0) return null;
    final stats = features.fieldStats;
    switch (type) {
      case NotetypeMappingType.cloze:
        final anyCloze = stats.any((s) => s.clozeRatio > 0);
        if (!notetype.isCloze && !anyCloze) {
          return '样本中未发现 Cloze 标记';
        }
      case NotetypeMappingType.multipleChoice:
        final anyOptions =
            stats.any((s) => s.optionLikeRatio > 0.2 || s.avgLength > 120);
        if (!anyOptions && notetype.fieldNames.length < 3) {
          return '样本中未发现选项结构，却映射为选择题';
        }
      case NotetypeMappingType.listenPick:
        final frontAudio = stats.isEmpty ? 0.0 : stats.first.audioRatio;
        if (frontAudio < 0.3) {
          return '正面音频占比过低，听力映射证据不足';
        }
      case NotetypeMappingType.wordEntry:
        final front = stats.isEmpty ? null : stats.first;
        if (front != null && front.avgLength > 80) {
          return '正面平均长度更像句子而非单词';
        }
      default:
        break;
    }
    return null;
  }
}
