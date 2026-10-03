// Package imports:
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Project imports:
import 'package:turna/data/sql_like.dart';

/// `sql_like.dart` is the only injection-defence primitive the whole app
/// agrees on: `review_history_dao`, `srs_state_dao` and `course_repository`
/// all build user-facing search and cleanup-sweep predicates through it, and
/// it had no direct test at all.
///
/// The binding is parameterised, so the thing worth proving is *semantics*:
/// that `%`, `_` and `\` in user input match literally instead of acting as
/// wildcards. A regression here would not throw or leak SQL — it would quietly
/// turn "search for 50%" into "search for anything starting with 50", or
/// widen the `anki-<id>-` uninstall sweep to other imports.
void main() {
  group('escapeLikePattern', () {
    test('escapes the three LIKE metacharacters', () {
      expect(escapeLikePattern('%'), r'\%');
      expect(escapeLikePattern('_'), r'\_');
      expect(escapeLikePattern(r'\'), r'\\');
    });

    test('escapes the backslash before anything else', () {
      // Order matters: a late backslash pass would double-escape the ones it
      // just added, turning `\%` into `\\%`, which matches a literal
      // backslash followed by a wildcard again.
      expect(escapeLikePattern(r'\%'), r'\\\%');
      expect(escapeLikePattern(r'100%'), r'100\%');
    });

    test('leaves ordinary text untouched', () {
      expect(escapeLikePattern('merhaba'), 'merhaba');
      expect(escapeLikePattern('günlük 复习'), 'günlük 复习');
      expect(escapeLikePattern(''), '');
    });

    test('is idempotent on already-escaped output for plain text', () {
      expect(escapeLikePattern('anki-123-'), 'anki-123-');
    });

    test('handles a Windows path, the case most likely to be typed', () {
      expect(escapeLikePattern(r'C:\path\to'), r'C:\\path\\to');
    });

    test('does not double-escape when applied once to a wildcard string', () {
      // The whole-wildcard input is the injection-ish shape: unescaped it
      // would match every row in the table.
      expect(escapeLikePattern('%%%'), r'\%\%\%');
      expect(escapeLikePattern('___'), r'\_\_\_');
    });
  });

  group('against a real sqlite database', () {
    late sql.Database db;

    setUpAll(() {
      // In-memory: no file, no cleanup, and the real LIKE/ESCAPE semantics of
      // the engine that ships in the app.
      db = sql.sqlite3.openInMemory();
      db.execute('CREATE TABLE t (label TEXT)');
      for (final value in [
        '50% off',
        '100 percent',
        'a_b literal',
        'axb wildcard lookalike',
        r'C:\path\to',
        r'C:\pathXto',
        'anki-abc-1',
        'anki-abc-2',
        'anki-xyz-1',
      ]) {
        db.execute('INSERT INTO t (label) VALUES (?)', [value]);
      }
    });

    tearDownAll(() => db.dispose());

    /// Run `SELECT label FROM t WHERE label LIKE ? ESCAPE '\'` with [pattern].
    List<String> matching(String pattern) => db
        .select(
            "SELECT label FROM t WHERE label LIKE ? ESCAPE '\\' ORDER BY label",
            [pattern])
        .map((row) => row['label'] as String)
        .toList();

    test("a '%' in user input matches literally, not as a wildcard", () {
      final hits = matching('%${escapeLikePattern('50%')}%');

      expect(hits, ['50% off'],
          reason: "unescaped, '50%' would also match '100 percent' — the "
              'search would return rows the user never asked for');
    });

    test("a '_' in user input matches literally", () {
      final hits = matching('%${escapeLikePattern('a_b')}%');

      expect(hits, ['a_b literal']);
      expect(hits, isNot(contains('axb wildcard lookalike')),
          reason: "unescaped, '_' matches any single character");
    });

    test(r'a backslash matches literally', () {
      final hits = matching('%${escapeLikePattern(r'C:\path\to')}%');

      expect(hits, [r'C:\path\to']);
      expect(hits, isNot(contains(r'C:\pathXto')),
          reason: r"unescaped, '\t' would be read as an escape sequence");
    });

    test('a pattern that is all wildcards matches only literal wildcards', () {
      // The regression that would matter most: a user typing '%' into a
      // search box. Unescaped, it matches every row in the table; escaped, it
      // is a literal percent sign.
      expect(matching('%${escapeLikePattern('%')}%'), ['50% off']);
      expect(matching('%${escapeLikePattern('%%%')}%'), isEmpty,
          reason: "three percent signs in a row appear in no row, while the "
              "unescaped form would have matched all of them");
    });

    test('a real search still works', () {
      expect(matching('%${escapeLikePattern('anki-abc')}%'),
          ['anki-abc-1', 'anki-abc-2']);
    });

    test('an empty needle matches everything, as before', () {
      // Not a security property, but a behaviour change here would silently
      // break "clear the search box to see all cards".
      expect(matching('%${escapeLikePattern('')}%'), hasLength(9));
    });
  });

  group('prefixLike — the uninstall sweep shape', () {
    late sql.Database db;

    setUpAll(() {
      db = sql.sqlite3.openInMemory();
      db.execute('CREATE TABLE t (note_id TEXT)');
      for (final value in [
        'anki-abc-1',
        'anki-abc-2',
        'anki-xyz-1',
        'deck-anki-abc-1',
      ]) {
        db.execute('INSERT INTO t (note_id) VALUES (?)', [value]);
      }
    });

    tearDownAll(() => db.dispose());

    test('sweeps only the requested import', () {
      final pattern = '${escapeLikePattern('anki-abc-')}%';
      final hits = db
          .select(
              "SELECT note_id FROM t WHERE note_id LIKE ? ESCAPE '\\' "
              'ORDER BY note_id',
              [pattern])
          .map((row) => row['note_id'] as String)
          .toList();

      expect(hits, ['anki-abc-1', 'anki-abc-2']);
      expect(hits, isNot(contains('anki-xyz-1')),
          reason: "an unescaped prefix would sweep other users' imports");
      expect(hits, isNot(contains('deck-anki-abc-1')),
          reason: 'a prefix sweep must not reach keys that merely end with it');
    });

    test('a literal backslash in the prefix is escaped, not dropped', () {
      final pattern = '${escapeLikePattern(r'C:\data\')}%';

      expect(pattern, r'C:\\data\\%');
    });
  });

  group('helper wiring', () {
    // Asserted through the expression's own fields rather than by capturing
    // generated SQL: a hand-rolled QueryExecutor would be pinned to one drift
    // version's abstract surface, and drift upgrades would break the test
    // without anything about the escape behaviour having changed.
    const label = CustomExpression<String>('label');

    test('containsLike binds an escaped contains-pattern with ESCAPE \\', () {
      final expr = containsLike(label, r'50%\tail') as LikeEscaped;

      expect(expr.target, same(label));
      expect(expr.pattern.value, r'%50\%\\tail%',
          reason: 'wildcards in user input must be escaped before binding');
      expect(expr.escape, r'\',
          reason: "the ESCAPE constant must stay '\\' to match the patterns "
              'built above — changing one without the other makes every '
              'pattern match as a wildcard again');
    });

    test('prefixLike binds an escaped prefix and only a trailing wildcard', () {
      final expr = prefixLike(label, r'anki\a-b') as LikeEscaped;

      expect(expr.pattern.value, r'anki\\a-b%');
      expect(expr.escape, r'\');
    });
  });
}
