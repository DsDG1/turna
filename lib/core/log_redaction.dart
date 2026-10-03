/// Secret redaction for the transparency log.
///
/// ## Why
///
/// `LogCapture` registers a `Logger.addLogListener` that sees **every** log
/// event in **both** debug and release builds, persists them to
/// `transparency_log.jsonl`, and lets the user export that file as a
/// diagnostic bundle. The AI layer makes that dangerous: OpenAI-compatible
/// endpoints sometimes echo a slice of the key back in the error body
/// (`Incorrect API key provided: sk-proj-…`), `ai_http_client` folds that body
/// into the thrown exception message, and the providers log it with
/// `logger.w('…failed: $e')`. So a mistyped key can reach disk, and from
/// disk into a file the user is encouraged to share.
///
/// Redacting here rather than at each AI call site means a future provider
/// inherits the protection for free. The API key itself is unaffected by
/// this: it lives in secure storage (Keystore / Keychain), never in the
/// message stream.
///
/// ## What it is not
///
/// This is a log-hygiene backstop, not a data-loss-prevention boundary. It
/// targets the credential shapes the app actually handles; it is not a
/// general secret scanner, and it must never be treated as one.
///
/// ## Invariant
///
/// [redact] is pure, must never log, and must never throw — it runs inside
/// the logger's own callback, where a throw or a `logger` call would recurse.
abstract final class LogRedaction {
  /// The replacement token. Bracketed so it is obvious in an exported log
  /// that a value was removed on purpose rather than lost.
  static const String placeholder = '[REDACTED]';

  /// `Authorization: Bearer <token>` — keeps the scheme so the log still
  /// shows that a bearer credential was sent.
  static final RegExp _bearer = RegExp(r'\bBearer\s+\S+', caseSensitive: false);

  /// `"apiKey": "<value>"` — the quoted form (config dumps, JSON error
  /// bodies). The lookahead stops the value at the matching quote so a
  /// quoted secret with spaces inside is still fully consumed.
  static final RegExp _apiKeyQuoted = RegExp(
      r'''(api[_-]?key)(\s*["']?\s*[:=]\s*)(["'])(?:(?!\3).)*\3''',
      caseSensitive: false);

  /// `apiKey=<value>` / `api-key: <value>` — the bare form, stopping at
  /// whitespace or a structural delimiter so surrounding log text survives.
  ///
  /// The negative lookahead is what makes [redact] idempotent: the bare
  /// value class excludes `]`, so without it a second pass would match the
  /// placeholder's own `]` and emit `apiKey=[REDACTED]]` — a scrubber that
  /// corrupts its own output is worse than no scrubber.
  static final RegExp _apiKeyBare = RegExp(
    _apiKeyBarePattern.replaceAll('@P', RegExp.escape(placeholder)),
    caseSensitive: false,
  );
  static const String _apiKeyBarePattern =
      r'''(api[_-]?key)(\s*["']?\s*[:=]\s*)(?!@P)[^\s"',;)}\]]+''';

  /// Bare OpenAI/Anthropic-style keys (`sk-…`, including `sk-ant-…`).
  /// The 8-character minimum keeps ordinary prose that happens to start with
  /// `sk-` (a hyphenated word) out of the net.
  static final RegExp _openAiStyleKey = RegExp(r'sk-[A-Za-z0-9_-]{8,}');

  /// Strip credential-shaped substrings from [input].
  ///
  /// Order matters: the structured `apiKey` field is matched before the bare
  /// `sk-` sweep so a field value is replaced as a whole rather than
  /// leaving a mangled `apiKey=[REDACTED]tail` behind.
  ///
  /// The field patterns rebuild their match from explicit capture groups
  /// instead of relying on `$1` substitution in the replacement string: Dart
  /// reads `${1}` as the *integer* 1, which silently emits "123" in place of
  /// the three groups.
  static String redact(String input) {
    if (input.isEmpty) return input;
    var out = input.replaceAll(_bearer, 'Bearer $placeholder');
    out = out.replaceAllMapped(
      _apiKeyQuoted,
      (m) => '${m.group(1)}${m.group(2)}${m.group(3)}'
          '$placeholder${m.group(3)}',
    );
    out = out.replaceAllMapped(
      _apiKeyBare,
      (m) => '${m.group(1)}${m.group(2)}$placeholder',
    );
    return out.replaceAll(_openAiStyleKey, placeholder);
  }

  /// [redact] for optional fields (an absent `error` stays absent).
  static String? redactNullable(String? input) =>
      input == null ? null : redact(input);
}
