// Provider-level streaming tests (Plan 3 §21): 1,000 network deltas must
// produce a bounded number of UI notifications (coalesced batches), deltas
// must never be lost, and dispose must cancel the stream + pending batches.

// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

class _StreamOnceClient extends http.BaseClient {
  _StreamOnceClient(this.body);

  final List<int> body;
  bool _sent = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_sent) {
      throw StateError('stream client reused');
    }
    _sent = true;
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

AiEngineConfig _config() => const AiEngineConfig(
      preset: kCustomPreset,
      apiKey: 'k',
      modelChat: 'm',
      modelJson: 'm',
      customBaseUrl: 'https://example.test/v1',
      cacheEnabled: false,
    );

AiEngine _engine(http.Client client) => AiEngine(
      AiHttpClient.withClient(client),
      AiCache.forTest(maxEntries: 0, enabled: false),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<int> sseBody(Iterable<String> deltas) => utf8.encode([
        for (final d in deltas)
          'data: ${jsonEncode({
            'choices': [
              {'delta': {'content': d}}
            ]
          })}\n\n',
        'data: [DONE]\n\n',
      ].join());

  test('1000 deltas coalesce into a bounded number of UI commits',
      () async {
    const total = 1000;
    final body = sseBody(List.generate(total, (i) => 'x'));
    final provider = AiTutorChatProvider(
      engine: _engine(_StreamOnceClient(body)),
      prefs: AiExplainPrefsStore(),
    );

    var notifications = 0;
    var revisions = 0;
    provider.addListener(() {
      notifications++;
      if (provider.streamingRevision > revisions) {
        revisions = provider.streamingRevision;
      }
    });

    await provider.ask(config: _config(), text: 'stream please');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(provider.state, AiTutorChatState.ready);
    // Content complete: every delta arrived exactly once, in order.
    expect(provider.messages.last.content, 'x' * total);
    // The notification count is bounded by batches, not by network deltas.
    expect(notifications, lessThan(50),
        reason: '1000 deltas must not cause 1000 notifications');
    expect(revisions, lessThan(50));
  });

  test('dispose cancels the in-flight stream and pending batches', () async {
    final controller = StreamController<List<int>>();
    final client = _ControllableClient(controller);
    final provider = AiTutorChatProvider(
      engine: _engine(client),
      prefs: AiExplainPrefsStore(),
    );

    final askFuture = provider.ask(config: _config(), text: 'long');
    await Future<void>.delayed(Duration.zero);
    // Feed one delta, then dispose the page mid-stream.
    controller.add(utf8.encode(
        'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n'));
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
    controller.add(utf8.encode(
        'data: {"choices":[{"delta":{"content":"-after-dispose"}}]}\n\n'));
    controller.add(utf8.encode('data: [DONE]\n\n'));
    await controller.close();

    var notified = false;
    // A new listener after dispose must not be pinged by late batches.
    // (ChangeNotifier itself throws on notify after dispose in debug, and
    // our _disposed guard prevents the coalescer from even trying.)
    try {
      provider.addListener(() => notified = true);
    } on AssertionError {
      // Flutter disallows addListener after dispose — also acceptable proof
      // the provider is really disposed.
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(provider.messages.last.content, anyOf(isEmpty, 'partial'),
        reason: 'no post-dispose content may arrive');
    expect(notified, isFalse);
    await askFuture.catchError((_) => true);
  });
}

class _ControllableClient extends http.BaseClient {
  _ControllableClient(this.controller);

  final StreamController<List<int>> controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(controller.stream, 200,
        headers: {'content-type': 'text/event-stream'});
  }
}
