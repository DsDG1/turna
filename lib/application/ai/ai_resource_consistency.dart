// Dart imports:
import 'dart:convert';

/// Resource self-consistency helpers mirroring
/// `tool/gui/src/backend/ai_generator.py` resource functions.

/// Ensure words/expressions/grammarPoints are lists (default empty).
void normalizeResources(Map<String, dynamic> parsed) {
  for (final key in const ['words', 'expressions', 'grammarPoints']) {
    final val = parsed[key];
    if (val == null) {
      parsed[key] = <Map<String, dynamic>>[];
    } else if (val is! List) {
      throw FormatException("顶层 '$key' 必须是数组。");
    }
  }
}

/// Yield every interaction item dict inside a lesson's content.
Iterable<Map<String, dynamic>> iterItems(Map lesson) sync* {
  final content = lesson['content'];
  if (content is! Map) return;
  final stages = content['stages'];
  if (stages is List) {
    for (final stage in stages) {
      if (stage is! Map) continue;
      final items = stage['items'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is Map) yield Map<String, dynamic>.from(item);
      }
    }
  }
  final subLessons = content['subLessons'];
  if (subLessons is List) {
    for (final sub in subLessons) {
      if (sub is! Map) continue;
      final stages2 = sub['stages'];
      if (stages2 is! List) continue;
      for (final stage in stages2) {
        if (stage is! Map) continue;
        final items = stage['items'];
        if (items is! List) continue;
        for (final item in items) {
          if (item is Map) yield Map<String, dynamic>.from(item);
        }
      }
    }
  }
  final phases = content['listeningPhases'];
  if (phases is List) {
    for (final phase in phases) {
      if (phase is! Map) continue;
      final items = phase['items'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is Map) yield Map<String, dynamic>.from(item);
      }
    }
  }
}

/// Auto-fix dangling resource references by adding stub entries.
///
/// When the AI forgets to define a word/expression/grammar point in the
/// top-level arrays while still referencing it from a lesson item, this
/// synthesizes a minimal stub entry so the section can be imported.
void autoFixResources(Map<String, dynamic> parsed) {
  final words =
      (parsed['words'] as List?)?.cast<Map<String, dynamic>?>() ?? const [];
  final expressions =
      (parsed['expressions'] as List?)?.cast<Map<String, dynamic>?>() ??
          const [];
  final grammarPoints =
      (parsed['grammarPoints'] as List?)?.cast<Map<String, dynamic>?>() ??
          const [];

  final wordIds = <String>{
    for (final w in words) if (w != null) w['id']?.toString() ?? '',
  }..remove('');
  final exprIds = <String>{
    for (final e in expressions) if (e != null) e['id']?.toString() ?? '',
  }..remove('');
  final grammarIds = <String>{
    for (final g in grammarPoints) if (g != null) g['id']?.toString() ?? '',
  }..remove('');

  final wordsList = words.whereType<Map<String, dynamic>>().toList();
  final exprList = expressions.whereType<Map<String, dynamic>>().toList();
  final grammarList = grammarPoints.whereType<Map<String, dynamic>>().toList();
  parsed['words'] = wordsList;
  parsed['expressions'] = exprList;
  parsed['grammarPoints'] = grammarList;

  final units = parsed['units'];
  if (units is! List) return;
  for (final unit in units) {
    if (unit is! Map) continue;
    final lessons = unit['lessons'];
    if (lessons is! List) continue;
    for (final lesson in lessons) {
      if (lesson is! Map) continue;
      for (final item in iterItems(lesson)) {
        final rt = item['runtimeType'];
        if (rt == 'showWord') {
          final wid = item['wordId']?.toString();
          if (wid != null && wid.isNotEmpty && !wordIds.contains(wid)) {
            final context = item['context']?.toString() ?? '';
            String term = '';
            String translation = '';
            if (context.isNotEmpty) {
              final parts = context.split('—');
              if (parts.length == 2) {
                term = parts[0].trim();
                translation = parts[1].trim();
              } else {
                term = context.trim();
              }
            }
            wordsList.add({
              'id': wid,
              'term': term.isEmpty ? wid : term,
              'translation': translation,
              'pronunciation': null,
              'audioAsset': null,
              'tags': ['auto-fix'],
            });
            wordIds.add(wid);
          }
        }
        final eid = item['expressionId']?.toString();
        if (eid != null && eid.isNotEmpty && !exprIds.contains(eid)) {
          final prompt =
              item['prompt']?.toString() ?? item['source']?.toString() ?? '';
          final expected = item['expected']?.toString() ??
              item['expectedAnswer']?.toString() ??
              '';
          exprList.add({
            'id': eid,
            'term': expected.isEmpty ? eid : expected,
            'translation': prompt,
            'pronunciation': null,
            'audioAsset': null,
            'tags': ['auto-fix'],
          });
          exprIds.add(eid);
        }
        final gid = item['grammarPointId']?.toString();
        if (gid != null && gid.isNotEmpty && !grammarIds.contains(gid)) {
          grammarList.add({
            'id': gid,
            'title': gid,
            'explanation': '',
            'exampleExpressionIds': [],
            'exampleSentenceIds': [],
            'practiceItems': [],
          });
          grammarIds.add(gid);
        }
      }
    }
  }
}

/// Verify every wordId/expressionId/grammarPointId is defined in the
/// top-level resource arrays. Throws [FormatException] listing all dangling
/// refs.
void checkResourceSelfConsistency(Map<String, dynamic> parsed) {
  final wordIds = <String>{
    for (final w in (parsed['words'] as List? ?? const []))
      if (w is Map) w['id']?.toString() ?? '',
  }..remove('');
  final exprIds = <String>{
    for (final e in (parsed['expressions'] as List? ?? const []))
      if (e is Map) e['id']?.toString() ?? '',
  }..remove('');
  final grammarIds = <String>{
    for (final g in (parsed['grammarPoints'] as List? ?? const []))
      if (g is Map) g['id']?.toString() ?? '',
  }..remove('');

  final missing = <String>[];
  final units = parsed['units'];
  if (units is List) {
    for (final unit in units) {
      if (unit is! Map) continue;
      final lessons = unit['lessons'];
      if (lessons is! List) continue;
      for (final lesson in lessons) {
        if (lesson is! Map) continue;
        final lid = lesson['id']?.toString() ?? '?';
        for (final item in iterItems(lesson)) {
          final rt = item['runtimeType'];
          if (rt == 'showWord') {
            final wid = item['wordId']?.toString();
            if (wid != null && wid.isNotEmpty && !wordIds.contains(wid)) {
              missing.add('lesson $lid: showWord 引用了未定义的 wordId「$wid」');
            }
          }
          final eid = item['expressionId']?.toString();
          if (eid != null && eid.isNotEmpty && !exprIds.contains(eid)) {
            missing.add('lesson $lid: 引用了未定义的 expressionId「$eid」');
          }
          final gid = item['grammarPointId']?.toString();
          if (gid != null && gid.isNotEmpty && !grammarIds.contains(gid)) {
            missing.add('lesson $lid: 引用了未定义的 grammarPointId「$gid」');
          }
        }
      }
    }
  }
  if (missing.isNotEmpty) {
    final shown = missing.take(20).join('\n');
    throw FormatException(
      '资源自洽校验失败（引用的资源 id 未在顶层 words/expressions/grammarPoints 中定义）:\n$shown',
    );
  }
}

/// Encode tags list to JSON string for DB storage.
String encodeTagsForDb(List<dynamic> tags) => jsonEncode(tags);