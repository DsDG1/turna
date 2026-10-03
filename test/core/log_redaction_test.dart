import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/log_redaction.dart';

/// Credential-shaped strings must never survive into the transparency log
/// or the export bundle. Every case below corresponds to a real leak path:
/// the provider error body (OpenAI echoes a key slice on 401), a config dump,
/// and an `Authorization` header caught in a debug print.
void main() {
  const marker = LogRedaction.placeholder;

  group('redacts key material', () {
    test('an OpenAI-style key echoed by the provider', () {
      const body =
          '{"error":{"message":"Incorrect API key provided: sk-proj-a1b2c3d4e5f6"}}';
      final out = LogRedaction.redact(body);

      expect(out, isNot(contains('sk-proj-a1b2c3d4e5f6')));
      expect(out, contains(marker));
      // The diagnosis must survive redaction or the log stops being useful.
      expect(out, contains('Incorrect API key provided'));
    });

    test('an Anthropic-style key', () {
      final out = LogRedaction.redact('key sk-ant-api03-AbCdEf123456 rejected');

      expect(out, isNot(contains('sk-ant-api03')));
      expect(out, contains(marker));
    });

    test('a bearer token keeps its scheme', () {
      final out = LogRedaction.redact(
          'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig');

      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains('Bearer $marker'),
          reason: 'the scheme is what makes the log line diagnosable');
    });

    test('a bare apiKey field', () {
      final out = LogRedaction.redact('apiKey=super-secret-value-123');

      expect(out, isNot(contains('super-secret-value-123')));
      expect(out, startsWith('apiKey=$marker'));
    });

    test('a quoted apiKey field keeps its JSON shape', () {
      final out =
          LogRedaction.redact('config dump: {"apiKey": "sk-live-abc123"}');

      expect(out, isNot(contains('sk-live-abc123')));
      expect(out, contains('"$marker"'),
          reason: 'the surrounding quotes must survive so the line stays '
              'readable as JSON');
    });

    test('a hyphenated / underscored field name variant', () {
      expect(LogRedaction.redact('api-key: hunter2hunter2'),
          isNot(contains('hunter2hunter2')));
      expect(LogRedaction.redact('API_KEY=hunter2hunter2'),
          isNot(contains('hunter2hunter2')));
    });

    test('a quoted value containing spaces is fully consumed', () {
      final out =
          LogRedaction.redact('{"api_key": "two word secret value", "n": 1}');

      expect(out, isNot(contains('two word secret value')));
      expect(out, contains('"n": 1'), reason: 'the next field must survive');
    });

    test('a secret in a URL query is caught by the key sweep', () {
      final out =
          LogRedaction.redact('GET /v1/models?key=sk-query-secret-abc failed');

      expect(out, isNot(contains('sk-query-secret-abc')));
    });

    test('several secrets in one line are all removed', () {
      final out = LogRedaction.redact(
          'a=sk-aaaaaaaaaaaa b=Bearer bbbbbbbbbbbb c=apiKey=cccccccccccc');

      expect(out, isNot(contains('aaaaaaaaaaaa')));
      expect(out, isNot(contains('bbbbbbbbbbb')));
      expect(out, isNot(contains('cccccccccccc')));
    });
  });

  group('leaves learning content alone', () {
    test('a short sk- hyphenation is not a key', () {
      const prose = 'The sk-8ball trick never worked in class';
      expect(LogRedaction.redact(prose), prose);
    });

    test('ordinary Turkish course text is untouched', () {
      const prose =
          'Merhaba dünya, bugün API öğreniyoruz! Anahtar kelime: kitap';
      expect(LogRedaction.redact(prose), prose);
    });

    test('an empty string is returned as-is', () {
      expect(LogRedaction.redact(''), '');
    });

    test('a sentence mentioning the word apikey is preserved', () {
      const prose = 'The apikey setting is stored in the system vault';
      expect(LogRedaction.redact(prose), prose,
          reason: 'no value follows the name, so nothing is redacted');
    });

    test('redaction is idempotent', () {
      const raw = 'apiKey=sk-abcdefgh123456';
      final once = LogRedaction.redact(raw);

      expect(LogRedaction.redact(once), once);
    });

    test('redactNullable keeps null null', () {
      expect(LogRedaction.redactNullable(null), isNull);
      expect(LogRedaction.redactNullable('sk-abcdefgh123456'),
          isNot(contains('sk-abcdefgh123456')));
    });
  });
}
