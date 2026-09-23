// Package imports:
import 'package:drift/drift.dart';

/// `col LIKE ? ESCAPE '\'` — drift's [Expression.like] has no escape support,
/// so this emits the ESCAPE clause manually. The pattern is bound as a SQL
/// variable (no injection risk); the escape character is a constant.
///
/// Pair with [escapeLikePattern] so user-supplied `%`/`_`/`\` match literally
/// instead of acting as wildcards.
class LikeEscaped extends Expression<bool> {
  LikeEscaped(this.target, this.pattern, this.escape);

  final Expression<String> target;
  final Variable<String> pattern;
  final String escape;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    writeInner(context, target);
    context.buffer.write(' LIKE ');
    writeInner(context, pattern);
    context.buffer.write(" ESCAPE '");
    context.buffer.write(escape);
    context.buffer.write("'");
  }

  @override
  int get hashCode => Object.hash(target, pattern, escape);

  @override
  bool operator ==(Object other) =>
      other is LikeEscaped &&
      other.target == target &&
      other.pattern == pattern &&
      other.escape == escape;
}

/// Escape SQL LIKE wildcards in [raw] so they match literally under
/// `ESCAPE '\'`: the backslash first (it is the escape char), then `%` and `_`.
String escapeLikePattern(String raw) {
  return raw
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Convenience: [LikeEscaped] over [target] with `'%<escaped raw>%'`,
/// the usual contains-match against user input.
Expression<bool> containsLike(Expression<String> target, String raw) {
  return LikeEscaped(
    target,
    Variable.withString('%${escapeLikePattern(raw)}%'),
    r'\',
  );
}

/// Convenience: [LikeEscaped] over [target] with `'<escaped prefix>%'`
/// for prefix sweeps (e.g. `anki-<importId>-` uninstall cleanup).
Expression<bool> prefixLike(Expression<String> target, String prefix) {
  return LikeEscaped(
    target,
    Variable.withString('${escapeLikePattern(prefix)}%'),
    r'\',
  );
}
