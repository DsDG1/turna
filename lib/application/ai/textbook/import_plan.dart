// Project imports:
import 'package:turna/application/ai/textbook/knowledge_merger.dart';

/// Command-level action resolved from (collision, strategy).
/// Mirrors `tool/gui/src/backend/import_strategy.py`.
enum ImportAction { append, merge, skip, replace, appendNew }

/// Per-section decision for a bulk textbook import.
class SectionImportPlan {
  const SectionImportPlan({
    required this.index,
    required this.sourceId,
    required this.targetId,
    required this.exists,
    required this.action,
    this.chapterTitle = '',
    this.wordCount = 0,
    this.expressionCount = 0,
    this.grammarCount = 0,
  });

  final int index;
  final String sourceId;
  final String targetId;
  final bool exists;
  final ImportAction action;
  final String chapterTitle;
  final int wordCount;
  final int expressionCount;
  final int grammarCount;

  bool get willWrite => action != ImportAction.skip;
}

/// Resolve the command-level action for one section.
ImportAction resolveImportAction({
  required bool existsInCourse,
  required ImportStrategy strategy,
}) {
  if (!existsInCourse) return ImportAction.append;
  switch (strategy) {
    case ImportStrategy.skipExisting:
      return ImportAction.skip;
    case ImportStrategy.forceReplace:
      return ImportAction.replace;
    case ImportStrategy.appendAsNew:
      return ImportAction.appendNew;
    case ImportStrategy.merge:
      return ImportAction.merge;
  }
}

/// Return an id derived from [baseId] that is not in [taken].
String uniqueSectionId(Set<String> taken, String baseId) {
  if (baseId.isEmpty) return baseId;
  if (!taken.contains(baseId)) return baseId;
  var suffix = 2;
  while (taken.contains('$baseId-$suffix')) {
    suffix++;
  }
  return '$baseId-$suffix';
}

/// Simulate a sequential batch import and return one plan per section.
List<SectionImportPlan> planBulkImport({
  required List<Map<String, dynamic>> sections,
  required Set<String> existingSectionIds,
  required ImportStrategy strategy,
  List<String>? chapterTitles,
}) {
  final taken = {...existingSectionIds};
  final plans = <SectionImportPlan>[];

  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    final sid = section['id']?.toString() ?? '';
    final exists = sid.isNotEmpty && taken.contains(sid);
    final action = resolveImportAction(
      existsInCourse: exists,
      strategy: strategy,
    );
    final targetId =
        action == ImportAction.appendNew ? uniqueSectionId(taken, sid) : sid;
    if (action != ImportAction.skip && targetId.isNotEmpty) {
      taken.add(targetId);
    }

    final words = section['words'];
    final expressions = section['expressions'];
    final grammar = section['grammarPoints'];

    plans.add(
      SectionImportPlan(
        index: i,
        sourceId: sid,
        targetId: targetId,
        exists: exists,
        action: action,
        chapterTitle: (chapterTitles != null && i < chapterTitles.length)
            ? chapterTitles[i]
            : (section['name']?.toString() ?? ''),
        wordCount: words is List ? words.length : 0,
        expressionCount: expressions is List ? expressions.length : 0,
        grammarCount: grammar is List ? grammar.length : 0,
      ),
    );
  }
  return plans;
}

/// Apply [plan] to a section JSON: rewrite id when appendNew; return null to skip.
Map<String, dynamic>? applyPlanToSection(
  Map<String, dynamic> section,
  SectionImportPlan plan,
) {
  if (!plan.willWrite) return null;
  if (plan.action == ImportAction.appendNew &&
      plan.targetId != plan.sourceId) {
    return _rewriteSectionId(section, plan.sourceId, plan.targetId);
  }
  return section;
}

Map<String, dynamic> _rewriteSectionId(
  Map<String, dynamic> section,
  String from,
  String to,
) {
  final out = Map<String, dynamic>.from(section);
  out['id'] = to;
  final units = out['units'];
  if (units is! List) return out;
  out['units'] = [
    for (final u in units)
      if (u is Map) _rewriteNestedId(Map<String, dynamic>.from(u), from, to)
      else u,
  ];
  return out;
}

Map<String, dynamic> _rewriteNestedId(
  Map<String, dynamic> node,
  String from,
  String to,
) {
  final id = node['id']?.toString() ?? '';
  if (id.startsWith(from)) {
    node['id'] = id.replaceFirst(from, to);
  }
  final lessons = node['lessons'];
  if (lessons is List) {
    node['lessons'] = [
      for (final l in lessons)
        if (l is Map)
          _rewriteNestedId(Map<String, dynamic>.from(l), from, to)
        else
          l,
    ];
  }
  return node;
}
