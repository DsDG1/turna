import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

enum OfficialAnkiFieldRole {
  targetText,
  nativeText,
  pronunciation,
  audio,
  image,
  exampleTarget,
  exampleNative,
  unitLabel,
  lessonLabel,
  optionPool,
  ignored,
}

class OfficialAnkiFieldCandidate {
  const OfficialAnkiFieldCandidate({
    required this.role,
    required this.fieldIndex,
    required this.fieldName,
    required this.confidence,
    required this.evidence,
  });

  final OfficialAnkiFieldRole role;
  final int fieldIndex;
  final String fieldName;
  final double confidence;
  final List<String> evidence;
}

enum OfficialAnkiMappingStatus {
  autoCandidate,
  needsConfirm,
  needsMapping,
  needsReview,
  skipped,
}

class OfficialAnkiMappingSuggestion {
  const OfficialAnkiMappingSuggestion({
    required this.candidates,
    required this.status,
    this.notetypeId = 0,
    this.schemaFingerprint = '',
    this.mappingVersion = 1,
    this.userConfirmed = false,
    this.updatedAtMillis = 0,
    this.enabledKinds = const <String>[
      'showWord',
      'flip',
      'multipleChoice',
      'multiSelect',
      'listenPick',
      'typeAnswer',
      'fillBlank',
      'canonicalLink',
    ],
    this.singleFieldMode = false,
    this.direction = 'targetToNative',
  });

  final List<OfficialAnkiFieldCandidate> candidates;
  final OfficialAnkiMappingStatus status;
  final int notetypeId;
  final String schemaFingerprint;
  final int mappingVersion;
  final bool userConfirmed;
  final int updatedAtMillis;
  final List<String> enabledKinds;
  final bool singleFieldMode;
  final String direction;

  OfficialAnkiFieldCandidate? role(OfficialAnkiFieldRole role) {
    final matches = candidates.where((c) => c.role == role).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return matches.isEmpty ? null : matches.first;
  }

  OfficialAnkiMappingSuggestion copyWith({
    List<OfficialAnkiFieldCandidate>? candidates,
    OfficialAnkiMappingStatus? status,
    int? notetypeId,
    String? schemaFingerprint,
    int? mappingVersion,
    bool? userConfirmed,
    int? updatedAtMillis,
    List<String>? enabledKinds,
    bool? singleFieldMode,
    String? direction,
  }) {
    return OfficialAnkiMappingSuggestion(
      candidates: candidates ?? this.candidates,
      status: status ?? this.status,
      notetypeId: notetypeId ?? this.notetypeId,
      schemaFingerprint: schemaFingerprint ?? this.schemaFingerprint,
      mappingVersion: mappingVersion ?? this.mappingVersion,
      userConfirmed: userConfirmed ?? this.userConfirmed,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      enabledKinds: enabledKinds ?? this.enabledKinds,
      singleFieldMode: singleFieldMode ?? this.singleFieldMode,
      direction: direction ?? this.direction,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        'notetypeId': notetypeId,
        'schemaFingerprint': schemaFingerprint,
        'mappingVersion': mappingVersion,
        'userConfirmed': userConfirmed,
        'updatedAtMillis': updatedAtMillis,
        'enabledKinds': enabledKinds,
        'singleFieldMode': singleFieldMode,
        'direction': direction,
        'candidates': candidates
            .map(
              (c) => <String, Object?>{
                'role': c.role.name,
                'fieldIndex': c.fieldIndex,
                'fieldName': c.fieldName,
                'confidence': c.confidence,
                'evidence': c.evidence,
              },
            )
            .toList(),
      };

  factory OfficialAnkiMappingSuggestion.fromJson(Map<String, Object?> json) {
    final raw = json['candidates'];
    final statusName = json['status'] as String? ?? 'needsMapping';
    final kinds = json['enabledKinds'];
    return OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => OfficialAnkiMappingStatus.needsMapping,
      ),
      notetypeId: (json['notetypeId'] as num?)?.toInt() ?? 0,
      schemaFingerprint: json['schemaFingerprint'] as String? ?? '',
      mappingVersion: (json['mappingVersion'] as num?)?.toInt() ?? 1,
      userConfirmed: json['userConfirmed'] == true,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
      enabledKinds: kinds is List
          ? kinds.map((e) => e.toString()).toList()
          : const <String>[
              'flip',
              'multipleChoice',
              'listenPick',
              'typeAnswer',
              'canonicalLink',
            ],
      singleFieldMode: json['singleFieldMode'] == true,
      direction: json['direction'] as String? ?? 'targetToNative',
      candidates: raw is List
          ? raw.whereType<Map>().map((item) {
              final map = Map<String, Object?>.from(item);
              final roleName = map['role'] as String? ?? 'ignored';
              return OfficialAnkiFieldCandidate(
                role: OfficialAnkiFieldRole.values.firstWhere(
                  (role) => role.name == roleName,
                  orElse: () => OfficialAnkiFieldRole.ignored,
                ),
                fieldIndex: (map['fieldIndex'] as num?)?.toInt() ?? 0,
                fieldName: map['fieldName'] as String? ?? '',
                confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
                evidence: (map['evidence'] as List? ?? const [])
                    .map((e) => e.toString())
                    .toList(),
              );
            }).toList()
          : const <OfficialAnkiFieldCandidate>[],
    );
  }
}

/// Infers field roles from names, sample values, tags, and deck path only.
class OfficialAnkiProjectionMapper {
  OfficialAnkiMappingSuggestion suggest({
    required OfficialAnkiProjectionSchema schema,
    List<String> tags = const <String>[],
    List<String> deckPath = const <String>[],
  }) {
    final candidates = <OfficialAnkiFieldCandidate>[];
    for (var i = 0; i < schema.fieldNames.length; i++) {
      final name = schema.fieldNames[i];
      final samples = schema.samples
          .map((sample) => i < sample.fields.length ? sample.fields[i] : '')
          .toList();
      candidates.addAll(_candidatesFor(name, i, samples, tags, deckPath));
    }
    return OfficialAnkiMappingSuggestion(
      candidates: candidates,
      status: _status(candidates),
    );
  }

  OfficialAnkiMappingStatus _status(List<OfficialAnkiFieldCandidate> candidates) {
    OfficialAnkiFieldCandidate? best(OfficialAnkiFieldRole role) {
      final matches = candidates.where((c) => c.role == role).toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      return matches.isEmpty ? null : matches.first;
    }

    final target = best(OfficialAnkiFieldRole.targetText);
    final native = best(OfficialAnkiFieldRole.nativeText);
    if (target != null &&
        native != null &&
        target.fieldIndex != native.fieldIndex &&
        target.confidence >= 0.85 &&
        native.confidence >= 0.85) {
      return OfficialAnkiMappingStatus.autoCandidate;
    }
    final strongest = candidates.isEmpty
        ? 0.0
        : candidates.map((c) => c.confidence).reduce((a, b) => a > b ? a : b);
    if (strongest < 0.60) return OfficialAnkiMappingStatus.needsMapping;
    return OfficialAnkiMappingStatus.needsConfirm;
  }

  List<OfficialAnkiFieldCandidate> _candidatesFor(
    String name,
    int index,
    List<String> samples,
    List<String> tags,
    List<String> deckPath,
  ) {
    final lower = name.toLowerCase().trim();
    final evidence = <String>[];
    OfficialAnkiFieldRole? role;
    var confidence = 0.40;
    if (lower.contains('front') ||
        lower.contains('target') ||
        lower == 'word' ||
        lower.contains('expression') ||
        lower == 'q' ||
        lower.contains('question') ||
        lower.contains('正面') ||
        lower.contains('单词') ||
        lower.contains('词') ||
        lower.contains('问题') ||
        lower.contains('前面') ||
        lower.contains('题目') ||
        lower.contains('题干')) {
      role = OfficialAnkiFieldRole.targetText;
      confidence = 0.92;
      evidence.add('name:${lower.contains('front') || lower.contains('正面') ? 'front' : 'target'}');
    } else if (lower.contains('back') ||
        lower.contains('native') ||
        lower.contains('meaning') ||
        lower.contains('translation') ||
        lower == 'a' ||
        lower.contains('answer') ||
        lower.contains('反面') ||
        lower.contains('释义') ||
        lower.contains('翻译') ||
        lower.contains('答案') ||
        lower.contains('后面')) {
      role = OfficialAnkiFieldRole.nativeText;
      confidence = 0.91;
      evidence.add('name:${lower.contains('back') || lower.contains('反面') ? 'back' : 'native'}');
    } else if (lower.contains('audio') ||
        lower.contains('sound') ||
        lower.contains('音频') ||
        lower.contains('发音') ||
        lower.contains('声音')) {
      role = OfficialAnkiFieldRole.audio;
      confidence = 0.88;
      evidence.add('name:audio');
    } else if (lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('图片') ||
        lower.contains('插图')) {
      role = OfficialAnkiFieldRole.image;
      confidence = 0.86;
      evidence.add('name:image');
    } else if (lower.contains('pronun') ||
        lower.contains('ipa') ||
        lower.contains('音标') ||
        lower.contains('拼音')) {
      role = OfficialAnkiFieldRole.pronunciation;
      confidence = 0.84;
      evidence.add('name:pronunciation');
    } else if (lower.contains('example') && lower.contains('native')) {
      role = OfficialAnkiFieldRole.exampleNative;
      confidence = 0.80;
      evidence.add('name:exampleNative');
    } else if (lower.contains('example') || lower.contains('例句')) {
      role = OfficialAnkiFieldRole.exampleTarget;
      confidence = 0.78;
      evidence.add('name:exampleTarget');
    } else if (lower.contains('unit')) {
      role = OfficialAnkiFieldRole.unitLabel;
      confidence = 0.82;
      evidence.add('name:unit');
    } else if (lower.contains('lesson')) {
      role = OfficialAnkiFieldRole.lessonLabel;
      confidence = 0.82;
      evidence.add('name:lesson');
    } else if (lower.contains('option') ||
        lower.contains('choice') ||
        lower.contains('选项')) {
      role = OfficialAnkiFieldRole.optionPool;
      confidence = 0.75;
      evidence.add('name:optionPool');
    }
    final nonempty = samples.where((s) => s.trim().isNotEmpty).length;
    if (samples.isNotEmpty) {
      evidence.add('non_empty:$nonempty/${samples.length}');
    }
    if (samples.any((s) => _isPlainText(s))) {
      evidence.add('sample:plain_text');
      if (role == OfficialAnkiFieldRole.targetText ||
          role == OfficialAnkiFieldRole.nativeText) {
        confidence = confidence < 0.90 ? 0.90 : confidence;
      }
    }
    if (samples.any((s) => s.contains('[sound:') || s.contains('[anki:play'))) {
      role = OfficialAnkiFieldRole.audio;
      confidence = 0.93;
      evidence.add('sample:official_av');
    }
    if (samples.any((s) => s.contains('<img') || s.contains('[image:'))) {
      role = OfficialAnkiFieldRole.image;
      confidence = 0.90;
      evidence.add('sample:image_ref');
    }
    if (tags.any((t) => t.startsWith('unit::')) &&
        role == OfficialAnkiFieldRole.unitLabel) {
      evidence.add('tag:unit');
    }
    if (tags.any((t) => t.startsWith('lesson::')) &&
        role == OfficialAnkiFieldRole.lessonLabel) {
      evidence.add('tag:lesson');
    }
    if (deckPath.isNotEmpty) {
      evidence.add('deck:${deckPath.join('/')}');
    }
    role ??= OfficialAnkiFieldRole.ignored;
    if (role == OfficialAnkiFieldRole.ignored) {
      confidence = 0.20;
      evidence.add('name:unknown');
    }
    return [
      OfficialAnkiFieldCandidate(
        role: role,
        fieldIndex: index,
        fieldName: name,
        confidence: confidence,
        evidence: evidence,
      ),
    ];
  }

  bool _isPlainText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('<') || trimmed.contains('[sound:')) return false;
    return true;
  }

  String shortText(String raw) {
    return raw
        .replaceAll(RegExp('<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\[sound:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? extractMediaFilename(String raw) {
    final sound = RegExp(r'\[sound:([^\]\r\n]+)\]').firstMatch(raw);
    if (sound != null) return _safeMediaName(sound.group(1)!);
    final av = RegExp(r'\[anki:play:[^\]]*?:([^\]\r\n]+)\]').firstMatch(raw);
    if (av != null) return _safeMediaName(av.group(1)!);
    final img = RegExp(
      r'''<img[^>]+src=["']([^"'>\s]+)["']''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (img != null) return _safeMediaName(img.group(1)!);
    return null;
  }

  List<String> parseOptionPool(String raw, {int maxOptions = 8, int maxChars = 80}) {
    final parts = raw
        .split(RegExp(r'[\n|;,]+'))
        .map(shortText)
        .where((part) => part.isNotEmpty)
        .toList();
    final unique = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      final clipped = part.length > maxChars ? part.substring(0, maxChars) : part;
      if (seen.add(clipped.toLowerCase())) {
        unique.add(clipped);
      }
      if (unique.length >= maxOptions) break;
    }
    return unique;
  }

  String? _safeMediaName(String raw) {
    final name = raw.trim().split(RegExp(r'[/\\]')).last;
    if (name.isEmpty) return null;
    if (name.contains('://') || name.startsWith('file:')) return null;
    if (name.contains('..')) return null;
    return name;
  }

  String? mappingConflict(OfficialAnkiMappingSuggestion suggestion) {
    final target = suggestion.role(OfficialAnkiFieldRole.targetText);
    final native = suggestion.role(OfficialAnkiFieldRole.nativeText);
    if (target != null &&
        native != null &&
        target.fieldIndex == native.fieldIndex &&
        !suggestion.singleFieldMode) {
      return 'target_native_same_field';
    }
    return null;
  }
}
