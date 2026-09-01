import 'package:drift/drift.dart';
import 'package:turna/data/course_database.dart';

/// `anki_course_tree_view` 的一行：一张卡在课程树中的位置（D3）。
class OfficialAnkiV2ViewRow {
  const OfficialAnkiV2ViewRow({
    required this.sourceId,
    required this.cardId,
    required this.noteId,
    required this.deckId,
    required this.wordId,
    required this.sectionKey,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.lessonKey,
    required this.presentationKind,
    required this.sourceHash,
    this.mappingVersion = 1,
  });

  final String sourceId;
  final int cardId;
  final int noteId;
  final int deckId;
  final String wordId;
  final String sectionKey;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final String lessonKey;
  final String presentationKind;
  final String sourceHash;
  final int mappingVersion;
}

/// 课程维度聚合（目录条目 / 树壳用）。
class OfficialAnkiV2ViewSectionSummary {
  const OfficialAnkiV2ViewSectionSummary({
    required this.sourceId,
    required this.sectionId,
    required this.sectionKey,
    required this.cardCount,
    required this.lessonCount,
  });

  final String sourceId;
  final String sectionId;
  final String sectionKey;
  final int cardCount;
  final int lessonCount;
}

/// course.db v23 视图表的唯一读写点（step4.md B3）。
///
/// 重建 = 单事务 DELETE+INSERT（原子换页）：任一时刻读者看到的是完整
/// 的旧视图或完整的新视图，中途强杀回滚到旧视图（K11「视图无状态，
/// 重跑即收敛」的结构保证）。无独立状态列、无游标、无版本机。
class OfficialAnkiV2ViewStore {
  OfficialAnkiV2ViewStore(this.course);

  final CourseDatabase course;

  static const _insertChunk = 200;

  /// 原子换页：用 [rows] 全量替换视图内容。空输入 = 清空视图（全部
  /// source 已卸载/retiring 时）。[rebuiltAtMillis] 仅作展示用途的时间
  /// 戳，不参与任何新鲜度判断。
  Future<void> replaceAll({
    required List<OfficialAnkiV2ViewRow> rows,
    required int rebuiltAtMillis,
  }) async {
    await course.transaction(() async {
      await course.customStatement('DELETE FROM anki_course_tree_view');
      for (var start = 0; start < rows.length; start += _insertChunk) {
        final chunk = rows.skip(start).take(_insertChunk).toList();
        final values = List.filled(chunk.length, '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').join(',');
        await course.customStatement(
          'INSERT INTO anki_course_tree_view '
          '(source_id, card_id, note_id, deck_id, word_id, section_key, '
          'section_id, unit_id, lesson_id, lesson_key, presentation_kind, '
          'source_hash, mapping_version, rebuilt_at_millis) VALUES $values',
          [
            for (final row in chunk)
              ...[
                row.sourceId,
                row.cardId,
                row.noteId,
                row.deckId,
                row.wordId,
                row.sectionKey,
                row.sectionId,
                row.unitId,
                row.lessonId,
                row.lessonKey,
                row.presentationKind,
                row.sourceHash,
                row.mappingVersion,
                rebuiltAtMillis,
              ],
          ],
        );
      }
    });
  }

  Future<bool> get isAvailable async {
    try {
      final rows = await course
          .customSelect('SELECT 1 FROM anki_course_tree_view LIMIT 1')
          .get();
      return rows.isNotEmpty;
    } catch (_) {
      // 表不存在（flag 关、schema 未升级）时读面自然回落 v1。
      return false;
    }
  }

  Future<int> cardCountForSource(String sourceId) async {
    try {
      final rows = await course.customSelect(
        'SELECT COUNT(*) AS n FROM anki_course_tree_view WHERE source_id = ?',
        variables: [Variable.withString(sourceId)],
      ).get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    } catch (_) {
      return 0;
    }
  }

  /// 视图内全部 source 的分区聚合（按 source、section 分组）。
  Future<List<OfficialAnkiV2ViewSectionSummary>> sectionSummaries() async {
    try {
      final rows = await course.customSelect(
        'SELECT source_id, section_id, section_key, '
        'COUNT(*) AS cards, COUNT(DISTINCT lesson_id) AS lessons '
        'FROM anki_course_tree_view '
        'GROUP BY source_id, section_id, section_key '
        'ORDER BY source_id, MIN(card_id)',
      ).get();
      return [
        for (final row in rows)
          OfficialAnkiV2ViewSectionSummary(
            sourceId: row.read<String>('source_id'),
            sectionId: row.read<String>('section_id'),
            sectionKey: row.read<String>('section_key'),
            cardCount: row.read<int>('cards'),
            lessonCount: row.read<int>('lessons'),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 一个课时下的卡映射（复习链 B6 读面：稳定 card-id 序）。
  Future<List<OfficialAnkiV2ViewRow>> rowsForLesson(String lessonId) async {
    try {
      final rows = await course.customSelect(
        'SELECT source_id, card_id, note_id, deck_id, word_id, section_key, '
        'section_id, unit_id, lesson_id, lesson_key, presentation_kind, '
        'source_hash, mapping_version FROM anki_course_tree_view '
        'WHERE lesson_id = ? ORDER BY card_id',
        variables: [Variable.withString(lessonId)],
      ).get();
      return [
        for (final row in rows)
          OfficialAnkiV2ViewRow(
            sourceId: row.read<String>('source_id'),
            cardId: row.read<int>('card_id'),
            noteId: row.read<int>('note_id'),
            deckId: row.read<int>('deck_id'),
            wordId: row.read<String>('word_id'),
            sectionKey: row.read<String>('section_key'),
            sectionId: row.read<String>('section_id'),
            unitId: row.read<String>('unit_id'),
            lessonId: row.read<String>('lesson_id'),
            lessonKey: row.read<String>('lesson_key'),
            presentationKind: row.read<String>('presentation_kind'),
            sourceHash: row.read<String>('source_hash'),
            mappingVersion: row.read<int>('mapping_version'),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 视图中出现过的全部 lesson id（树壳合成用）。
  Future<Set<String>> lessonIds() async {
    try {
      final rows = await course.customSelect(
        'SELECT DISTINCT lesson_id FROM anki_course_tree_view',
      ).get();
      return {for (final row in rows) row.read<String>('lesson_id')};
    } catch (_) {
      return const {};
    }
  }

  /// 课时名（lesson_key 展示用）：取每课时第一行的 key。
  Future<Map<String, String>> lessonKeysById() async {
    try {
      final rows = await course.customSelect(
        'SELECT lesson_id, lesson_key FROM anki_course_tree_view '
        'GROUP BY lesson_id HAVING MIN(card_id)',
      ).get();
      return {
        for (final row in rows)
          row.read<String>('lesson_id'): row.read<String>('lesson_key'),
      };
    } catch (_) {
      return const {};
    }
  }

  /// 某个 source 在视图中的全部卡 id（v2 锁对齐 / retiring 校验用）。
  Future<List<int>> cardIdsForSource(String sourceId) async {
    try {
      final rows = await course.customSelect(
        'SELECT card_id FROM anki_course_tree_view WHERE source_id = ? '
        'ORDER BY card_id',
        variables: [Variable.withString(sourceId)],
      ).get();
      return [for (final row in rows) row.read<int>('card_id')];
    } catch (_) {
      return const [];
    }
  }
}
