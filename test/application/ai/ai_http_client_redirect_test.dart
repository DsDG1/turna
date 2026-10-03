import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

/// The AI request carries `Authorization: Bearer <apiKey>` on every call.
/// Whether that header survives a cross-host 30x hop is up to each platform
/// HTTP stack's own origin scrubbing, so the client must not follow the
/// redirect at all: a user-configured endpoint should not get to decide where
/// the key is sent.
void main() {
  late HttpServer redirector;
  late HttpServer target;
  late Uri targetUri;

  /// Every request [target] observed, with its Authorization header.
  final observedAtTarget = <Map<String, String?>>[];

  setUp(() async {
    redirector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    targetUri = Uri.parse('http://127.0.0.1:${target.port}/v1');

    target.listen((request) async {
      observedAtTarget.add({
        'method': request.method,
        'path': request.uri.path,
        'auth': request.headers.value(HttpHeaders.authorizationHeader),
      });
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'model': 'test',
        'choices': [
          {
            'message': {'content': 'never reached'}
          }
        ],
      }));
      await request.response.close();
    });
  });

  tearDown(() async {
    await redirector.close(force: true);
    await target.close(force: true);
  });

  AiEngineConfig configFor(Uri base) => AiEngineConfig(
        preset: kCustomPreset,
        customBaseUrl: base.toString(),
        apiKey: 'sk-super-secret-key-value',
        modelChat: 'gpt-test',
        modelJson: 'gpt-test',
      );

  test('a 302 is refused and the redirect target is never contacted', () async {
    redirector.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers
          .set(HttpHeaders.locationHeader, targetUri.toString());
      await request.response.close();
    });

    final httpClient = http.Client();
    final client = AiHttpClient.withClient(httpClient);
    addTearDown(httpClient.close);

    await expectLater(
      client.postJson(
        config: configFor(Uri.parse('http://127.0.0.1:${redirector.port}/v1')),
        model: 'gpt-test',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
      ),
      throwsA(isA<AiRedirectNotFollowed>()),
    );

    // The whole point: the second host must not have seen anything, and in
    // particular not the key.
    expect(observedAtTarget, isEmpty,
        reason: 'following the redirect would have handed the API key to a '
            'host the user never configured');
  });

  test('the refusal is mapped to fixed user-facing copy', () {
    final mapping = AiErrorMapper.map(const AiRedirectNotFollowed(302));

    expect(mapping.kind, AiErrorKind.endpointRedirect);
    expect(mapping.canRetry, isFalse);
    expect(mapping.canConfigure, isTrue);
    // No status code and no body text leaks into what the user sees.
    expect(mapping.message, isNot(contains('302')));
  });

  test('a 307 on the streaming path is refused too', () async {
    redirector.listen((request) async {
      request.response.statusCode = HttpStatus.temporaryRedirect;
      request.response.headers
          .set(HttpHeaders.locationHeader, targetUri.toString());
      await request.response.close();
    });

    final httpClient = http.Client();
    final client = AiHttpClient.withClient(httpClient);
    addTearDown(httpClient.close);

    await expectLater(
      client.postStream(
        config: configFor(Uri.parse('http://127.0.0.1:${redirector.port}/v1')),
        model: 'gpt-test',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
      ).drain<void>(),
      throwsA(isA<AiRedirectNotFollowed>()),
    );
    expect(observedAtTarget, isEmpty);
  });

  test('a normal 200 still works — the guard is not over-broad', () async {
    final httpClient = http.Client();
    final client = AiHttpClient.withClient(httpClient);
    addTearDown(httpClient.close);

    final body = await client.postJson(
      config: configFor(targetUri),
      model: 'gpt-test',
      messages: const [
        {'role': 'user', 'content': 'hi'}
      ],
    );

    expect(body['model'], 'test');
    expect(observedAtTarget, hasLength(1));
    expect(observedAtTarget.single['auth'], 'Bearer sk-super-secret-key-value');
  });
}
