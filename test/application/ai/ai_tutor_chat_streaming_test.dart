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
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/ai/ai_card_explain_provider.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
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
                  {
                    'delta': {'content': d}
                  }
                ]
              })}\n\n',
        'data: [DONE]\n\n',
      ].join());

  test('1000 deltas coalesce into a bounded number of UI commits', () async {
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
    controller.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n'));
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

  test('hint 1000 deltas use the same bounded batching contract', () async {
    const total = 1000;
    final provider = AiHintProvider(
      engine: _engine(_StreamOnceClient(sseBody(List.filled(total, 'h')))),
      prefs: AiExplainPrefsStore(),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.explainQuestion(
      config: _config(),
      ctx: const AiQuestionContext(
        language: 'Turkish',
        typeLabel: 'Vocabulary',
        promptLabel: 'merhaba',
      ),
    );

    expect(provider.latestReply, 'h' * total);
    expect(provider.streamingRevision, lessThan(50));
    expect(notifications, lessThan(50));
  });

  test('card explain 1000 deltas use the same bounded batching contract',
      () async {
    const total = 1000;
    final provider = AiCardExplainProvider(
      engine: _engine(_StreamOnceClient(sseBody(List.filled(total, 'e')))),
      prefs: AiExplainPrefsStore(),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.explain(config: _config(), context: _cardContext());

    expect(provider.explanation, 'e' * total);
    expect(provider.streamingRevision, lessThan(50));
    expect(notifications, lessThan(50));
  });

  test('hint and card explain reject all late chunks after dispose', () async {
    final hintController = StreamController<List<int>>();
    final hint = AiHintProvider(
      engine: _engine(_ControllableClient(hintController)),
      prefs: AiExplainPrefsStore(),
    );
    final hintFuture = hint.explainQuestion(
      config: _config(),
      ctx: const AiQuestionContext(
        language: 'Turkish',
        typeLabel: 'Vocabulary',
        promptLabel: 'merhaba',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    hintController.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"before"}}]}\n\n'));
    await Future<void>.delayed(Duration.zero);
    hint.dispose();
    final hintRevision = hint.streamingRevision;
    hintController.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"after"}}]}\n\n'));
    hintController.add(utf8.encode('data: [DONE]\n\n'));
    await hintController.close();
    await hintFuture.catchError((_) {});
    expect(hint.streamingRevision, hintRevision);
    expect(hint.latestReply ?? '', isNot(contains('after')));

    final cardController = StreamController<List<int>>();
    final card = AiCardExplainProvider(
      engine: _engine(_ControllableClient(cardController)),
      prefs: AiExplainPrefsStore(),
    );
    final cardFuture = card.explain(config: _config(), context: _cardContext());
    await Future<void>.delayed(Duration.zero);
    cardController.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"before"}}]}\n\n'));
    await Future<void>.delayed(Duration.zero);
    card.dispose();
    final cardRevision = card.streamingRevision;
    cardController.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"after"}}]}\n\n'));
    cardController.add(utf8.encode('data: [DONE]\n\n'));
    await cardController.close();
    await cardFuture.catchError((_) => null);
    expect(card.streamingRevision, cardRevision);
    expect(card.explanation ?? '', isNot(contains('after')));
  });
}

AiCardContext _cardContext() => const AiCardContext(
      schemaVersion: AiCardContext.kSchemaVersion,
      source: LearningSourceRef(
        kind: LearningSourceKind.course,
        sourceId: 'course',
        displayName: 'Course',
      ),
      cardId: 'card-1',
      presentationKind: 'standard',
      questionPlainText: 'Merhaba',
      answerPlainText: 'Hello',
      language: 'Turkish',
      answerRevealed: true,
    );

class _ControllableClient extends http.BaseClient {
  _ControllableClient(this.controller);

  final StreamController<List<int>> controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(controller.stream, 200,
        headers: {'content-type': 'text/event-stream'});
  }
}
