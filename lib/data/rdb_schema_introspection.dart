// Shim for `PRAGMA table_info`, which this engine cannot answer.
//
// drift's `Migrator.hasColumn` asks the database `PRAGMA table_info(<table>)`
// before it adds a column, and `CourseDatabase.migration` calls it on every
// open. A `querySql` for a PRAGMA resolves its promise and then never returns
// from the result-set accessors, so the open hangs: observed on device
// (HarmonyOS 7.0.0, API 26), where the last log line before the stall was
// always the PRAGMA. The schema build stopped dead there.
//
// So the one pragma drift actually needs is answered from the stored CREATE
// statement instead, which is an ordinary `sqlite_master` read. Parsing the
// DDL is the trade: it is a closed problem for the SQL this project generates
// (no generated columns, no `WITHOUT ROWID`), and it is unit-testable, which
// the bridge itself is not.
//
// The parser is deliberately not a general SQL parser. It extracts column
// names and their declared type and nothing else.

/// The columns of one table, as `PRAGMA table_info` would report them.
class RdbTableColumn {
  const RdbTableColumn({required this.name, required this.type});

  final String name;

  /// Declared type, upper-cased, e.g. `TEXT`. Empty when the DDL omits it.
  final String type;
}

/// Column names and types parsed out of a stored `CREATE TABLE` statement.
///
/// Returns an empty list when [createSql] is not a table statement, which is
/// the case for indexes and views. Callers treat that as "no columns", not as
/// "no such table", so a missing table surfaces through the query that fetched
/// the DDL instead.
List<RdbTableColumn> parseCreateTableColumns(String createSql) {
  final body = _tableBody(createSql);
  if (body == null) return const [];

  final columns = <RdbTableColumn>[];
  for (final part in _splitTopLevel(body)) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    // Table-level constraints share the comma-separated body with columns and
    // are not columns. `PRIMARY KEY (...)` is the common one; a column can also
    // carry an inline one, which stays with its column and is harmless here.
    if (_tableConstraintKeywords.any(trimmed.toUpperCase().startsWith)) {
      continue;
    }
    final parsed = _parseColumn(trimmed);
    if (parsed != null) columns.add(parsed);
  }
  return columns;
}

const _tableConstraintKeywords = <String>[
  'PRIMARY KEY',
  'UNIQUE',
  'CHECK',
  'FOREIGN KEY',
  'CONSTRAINT',
  'EXCLUDE',
];

/// Extracts the parenthesised body of a `CREATE TABLE` statement.
String? _tableBody(String sql) {
  final upper = sql.toUpperCase();
  if (!upper.contains('CREATE TABLE')) return null;
  final open = sql.indexOf('(');
  if (open < 0) return null;
  // The closing paren of the body is the last one in the statement; the ones
  // inside CHECK (...) or DEFAULT (...) belong to their own clauses.
  final close = sql.lastIndexOf(')');
  if (close <= open) return null;
  return sql.substring(open + 1, close);
}

/// Splits on commas that are not inside quotes or nested parentheses.
List<String> _splitTopLevel(String body) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var quote = '';

  for (var i = 0; i < body.length; i++) {
    final ch = body[i];

    if (quote.isNotEmpty) {
      buffer.write(ch);
      if (ch == quote) quote = '';
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`') {
      quote = ch;
      buffer.write(ch);
      continue;
    }
    if (ch == '(') depth++;
    if (ch == ')') depth--;

    if (ch == ',' && depth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(ch);
  }
  parts.add(buffer.toString());
  return parts;
}

RdbTableColumn? _parseColumn(String definition) {
  final match = RegExp(
    r'^\s*(?:"([^"]+)"|`([^`]+)`|\[([^\]]+)\]|([A-Za-z_][A-Za-z0-9_$]*))',
  ).firstMatch(definition);
  if (match == null) return null;

  final name = match.group(1) ??
      match.group(2) ??
      match.group(3) ??
      match.group(4);
  if (name == null) return null;

  // The declared type is the next bare word, if any. `"a" PRIMARY KEY` has no
  // type — `PRIMARY` is a constraint, not one — so the leading word has to be
  // checked against the keywords that can follow a column name.
  final after = definition.substring(match.end).trimLeft();
  final type = _parseType(after);
  return RdbTableColumn(name: name, type: type);
}

/// Words that may follow a column name and mean the column is untyped.
const _columnConstraintKeywords = <String>{
  'PRIMARY',
  'NOT',
  'UNIQUE',
  'CHECK',
  'DEFAULT',
  'REFERENCES',
  'COLLATE',
  'GENERATED',
  'AS',
  'CONSTRAINT',
  'AUTOINCREMENT',
  'NULL',
};

String _parseType(String after) {
  final first = RegExp(r'^([A-Za-z][A-Za-z0-9_]*)').firstMatch(after);
  if (first == null) return '';
  if (_columnConstraintKeywords.contains(first.group(1)!.toUpperCase())) {
    return '';
  }
  // A second word is part of the type only for the fixed multi-word spellings
  // SQLite recognises; anything else is a constraint, so stop at one word.
  const multiWordTypes = <String>{
    'DOUBLE PRECISION',
    'UNSIGNED BIG INT',
    'CHARACTER VARYING',
  };
  final two = RegExp(r'^([A-Za-z][A-Za-z0-9_]*\s+[A-Za-z][A-Za-z0-9_]*)')
      .firstMatch(after);
  if (two != null) {
    final candidate = two.group(1)!.trim().toUpperCase();
    if (multiWordTypes.contains(candidate)) return candidate;
  }
  return first.group(1)!.toUpperCase();
}
