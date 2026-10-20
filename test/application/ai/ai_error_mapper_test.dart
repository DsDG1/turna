// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  group('AiErrorMapper model failures', () {
    // 实测报文（MiniMax，2026-10-20）：模型 id 为空串时服务端回这条 400。
    test('an unknown-model 400 becomes modelUnavailable', () {
      final mapped = AiErrorMapper.map(
        Exception(
          'HTTP 400: {"type":"error","error":{"type":"bad_request_error",'
          '"message":"invalid params, unknown model \'\' (2013)",'
          '"http_code":"400"},"request_id":"0726b18134b80ab3a3c6e83e0a6410e2"}',
        ),
      );
      expect(mapped.kind, AiErrorKind.modelUnavailable);
      expect(mapped.message, AppStrings.aiErrorModelUnavailable);
      // 重试同一个模型 id 不会变好，只能去设置里改。
      expect(mapped.canRetry, isFalse);
      expect(mapped.canConfigure, isTrue);
    });

    test('the OpenAI-style model_not_found body maps the same way', () {
      final mapped = AiErrorMapper.map(
        Exception('HTTP 404: {"error":{"code":"model_not_found"}}'),
      );
      expect(mapped.kind, AiErrorKind.modelUnavailable);
    });

    test('a plain 400 without model wording stays unknown', () {
      final mapped = AiErrorMapper.map(Exception('HTTP 400: bad request'));
      expect(mapped.kind, AiErrorKind.unknown);
    });

    test('auth failures still win over the generic path', () {
      final mapped = AiErrorMapper.map(Exception('HTTP 401: unauthorized'));
      expect(mapped.kind, AiErrorKind.unauthorized);
    });
  });
}
