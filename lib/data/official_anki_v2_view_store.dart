import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/sql_like.dart';
import 'package:turna/domain/anki/official_anki_v2_view_models.dart';
import 'package:turna/domain/repositories/i_official_anki_v2_view_store.dart';

/// course.db v23+ 视图表的唯一读写点（ADR 0043）。
///
/// 重建 = 单事务 DELETE+INSERT（原子换页）：任一时刻读者看到的是完整
/// 的旧视图或完整的新视图，中途强杀回滚到旧视图（K11「视图无状态，
/// 重跑即收敛」的结构保证）。无独立状态列、无游标、无版本机。
@LazySingleton(as: IOfficialAnkiV2ViewStore)
class OfficialAnkiV2ViewStore implements IOfficialAnkiV2ViewStore {
  OfficialAnkiV2ViewStore(this.course);

  final CourseDatabase course;

  static const _insertChunk = 200;

  /// 原子换页：用 [rows] 全量替换视图内容。空输入 = 清空视图（全部
  /// source 已卸载/retiring 时）。[rebuiltAtMillis] 仅作展示用途的时间
  /// 戳，不参与任何新鲜度判断。
  @override
  Future<void> replaceAll({
    required List<OfficialAnkiV2ViewRow> rows,
    required int rebuiltAtMillis,
  }) async {
    await course.transaction(() async {
      await course.customStatement('DELETE FROM anki_course_tree_view');
      await _insertRows(rows, rebuiltAtMillis);
    });
  }

  /// 按 source 分组的范围换页（D2）：同一事务内先删掉不在
  /// [liveSourceIds] 里的残留行，再对 [rowsBySource] 覆盖到的 source
  /// 做 DELETE+INSERT；live 但未覆盖的 source 行保持不动。全量 rebuild
  /// 传全部分组即等价 replaceAll；commit 只传本次提交的 source。
  @override
  Future<void> replaceScoped({
    required Set<String> liveSourceIds,
    required Map<String, List<OfficialAnkiV2ViewRow>> rowsBySource,
    required int rebuiltAtMillis,
    void Function(int inserted, int total)? onInserted,
  }) async {
    final total = rowsBySource.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    var inserted = 0;
    onInserted?.call(inserted, total);
    await course.transaction(() async {
      if (liveSourceIds.isEmpty) {
        await course.customStatement('DELETE FROM anki_course_tree_view');
      } else {
        await course.customStatement(
          'DELETE FROM anki_course_tree_view WHERE source_id NOT IN '
          '(${List.filled(liveSourceIds.length, '?').join(',')})',
          [for (final id in liveSourceIds) id],
        );
      }
      for (final entry in rowsBySource.entries) {
        await course.customStatement(
          'DELETE FROM anki_course_tree_view WHERE source_id = ?',
          [entry.key],
        );
        await _insertRows(
          entry.value,
          rebuiltAtMillis,
          onChunk: (count) {
            inserted += count;
            onInserted?.call(inserted, total);
          },
        );
      }
    });
  }

  Future<void> _insertRows(
    List<OfficialAnkiV2ViewRow> rows,
    int rebuiltAtMillis, {
    void Function(int count)? onChunk,
  }) async {
    for (var start = 0; start < rows.length; start += _insertChunk) {
      final end = start + _insertChunk;
      final chunk = rows.sublist(start, end > rows.length ? rows.length : end);
      final values = List.filled(
              chunk.length, '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
          .join(',');
      await course.customStatement(
        'INSERT INTO anki_course_tree_view '
        '(source_id, card_id, note_id, deck_id, word_id, section_key, '
        'section_id, unit_id, unit_key, lesson_id, lesson_key, '
        'source_hash, mapping_version, rebuilt_at_millis) VALUES $values',
        [
          for (final row in chunk) ...[
            row.sourceId,
            row.cardId,
            row.noteId,
            row.deckId,
            row.wordId,
            row.sectionKey,
            row.sectionId,
            row.unitId,
            row.unitKey,
            row.lessonId,
            row.lessonKey,
            row.sourceHash,
            row.mappingVersion,
            rebuiltAtMillis,
          ],
        ],
      );
      onChunk?.call(chunk.length);
    }
  }

  /// 整视图 distinct section 数（scoped 换页后的整表口径）。
  @override
  Future<int> distinctSectionCount() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT COUNT(DISTINCT section_id) AS n FROM anki_course_tree_view',
          )
          .get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    }, 0);
  }

  /// Sections whose key records a 60/40 split (`(Part N)`).
  @override
  Future<int> splitSectionCount() {
    return _readView(() async {
      final rows = await course.customSelect(
        'SELECT COUNT(DISTINCT section_id) AS n '
        'FROM anki_course_tree_view '
        'WHERE ${sqlLikeEscapedClause('section_key')}',
        variables: [containsLikeVariable('(Part ')],
      ).get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    }, 0);
  }

  /// 整视图 distinct lesson 数。
  @override
  Future<int> distinctLessonCount() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT COUNT(DISTINCT lesson_id) AS n FROM anki_course_tree_view',
          )
          .get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    }, 0);
  }

  @override
  Future<bool> get isAvailable {
    return _readView(() async {
      final rows = await course
          .customSelect('SELECT 1 FROM anki_course_tree_view LIMIT 1')
          .get();
      return rows.isNotEmpty;
    }, false);
  }

  @override
  Future<int> cardCountForSource(String sourceId) {
    return _readView(() async {
      final rows = await course.customSelect(
        'SELECT COUNT(*) AS n FROM anki_course_tree_view WHERE source_id = ?',
        variables: [Variable.withString(sourceId)],
      ).get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    }, 0);
  }

  /// 视图内全部 source 的分区聚合（按 source、section 分组）。
  @override
  Future<List<OfficialAnkiV2ViewSectionSummary>> sectionSummaries() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT source_id, section_id, section_key, '
            'COUNT(*) AS cards, COUNT(DISTINCT lesson_id) AS lessons '
            'FROM anki_course_tree_view '
            'GROUP BY source_id, section_id, section_key '
            'ORDER BY source_id, MIN(card_id)',
          )
          .get();
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
    }, const <OfficialAnkiV2ViewSectionSummary>[]);
  }

  /// 一个课时下的卡映射（复习链 B6 读面：稳定 card-id 序）。
  @override
  Future<List<OfficialAnkiV2ViewRow>> rowsForLesson(String lessonId) {
    return _readView(() async {
      final rows = await course.customSelect(
        'SELECT source_id, card_id, note_id, deck_id, word_id, section_key, '
        'section_id, unit_id, unit_key, lesson_id, lesson_key, '
        'source_hash, mapping_version '
        'FROM anki_course_tree_view '
        'WHERE lesson_id = ? ORDER BY card_id',
        variables: [Variable.withString(lessonId)],
      ).get();
      return [for (final row in rows) _rowFromQuery(row)];
    }, const <OfficialAnkiV2ViewRow>[]);
  }

  /// 整视图按树序排列的全部行（用于离线投影课程树壳）。
  @override
  Future<List<OfficialAnkiV2ViewRow>> treeRows() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT source_id, card_id, note_id, deck_id, word_id, '
            'section_key, section_id, unit_id, unit_key, lesson_id, '
            'lesson_key, source_hash, mapping_version '
            'FROM anki_course_tree_view '
            'ORDER BY source_id, section_id, unit_id, lesson_id, card_id',
          )
          .get();
      return [for (final row in rows) _rowFromQuery(row)];
    }, const <OfficialAnkiV2ViewRow>[]);
  }

  OfficialAnkiV2ViewRow _rowFromQuery(QueryRow row) {
    return OfficialAnkiV2ViewRow(
      sourceId: row.read<String>('source_id'),
      cardId: row.read<int>('card_id'),
      noteId: row.read<int>('note_id'),
      deckId: row.read<int>('deck_id'),
      wordId: row.read<String>('word_id'),
      sectionKey: row.read<String>('section_key'),
      sectionId: row.read<String>('section_id'),
      unitId: row.read<String>('unit_id'),
      unitKey: row.read<String>('unit_key'),
      lessonId: row.read<String>('lesson_id'),
      lessonKey: row.read<String>('lesson_key'),
      sourceHash: row.read<String>('source_hash'),
      mappingVersion: row.read<int>('mapping_version'),
    );
  }

  /// 视图中出现过的全部 lesson id（树壳合成用）。
  @override
  Future<Set<String>> lessonIds() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT DISTINCT lesson_id FROM anki_course_tree_view',
          )
          .get();
      return {for (final row in rows) row.read<String>('lesson_id')};
    }, const <String>{});
  }

  /// 课时名（lesson_key 展示用）：取每课时第一行的 key。
  @override
  Future<Map<String, String>> lessonKeysById() {
    return _readView(() async {
      final rows = await course
          .customSelect(
            'SELECT lesson_id, MIN(lesson_key) AS lesson_key '
            'FROM anki_course_tree_view GROUP BY lesson_id',
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('lesson_id'): row.read<String>('lesson_key'),
      };
    }, const <String, String>{});
  }

  /// 某个 source 在视图中的全部卡 id（v2 锁对齐 / retiring 校验用）。
  @override
  Future<List<int>> cardIdsForSource(String sourceId) {
    return _readView(() async {
      final rows = await course.customSelect(
        'SELECT card_id FROM anki_course_tree_view WHERE source_id = ? '
        'ORDER BY card_id',
        variables: [Variable.withString(sourceId)],
      ).get();
      return [for (final row in rows) row.read<int>('card_id')];
    }, const <int>[]);
  }

  /// 定向删除某个 source 的视图行（retiring 即刻不可见 / 终删兜底）。
  @override
  Future<void> deleteBySource(String sourceId) {
    return course.customStatement(
      'DELETE FROM anki_course_tree_view WHERE source_id = ?',
      [sourceId],
    );
  }

  /// 清空全部视图行。
  @override
  Future<void> clear() {
    return course.customStatement('DELETE FROM anki_course_tree_view');
  }

  /// 表不存在（尚未建视图）时返回 [ifAbsent] 并记一条 info。
  /// 其它 SQL 错误记 warning 后原样抛出，调用方不能把坏视图当成「没有官方课程」。
  Future<T> _readView<T>(Future<T> Function() query, T ifAbsent) async {
    try {
      return await query();
    } catch (error, stackTrace) {
      if (error is SqliteException && error.message.contains('no such table')) {
        logger.i('anki_course_tree_view absent: ${error.message}');
        return ifAbsent;
      }
      logger.w(
        'anki_course_tree_view read failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
