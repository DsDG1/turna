// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/companion_rate_limiter.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/ai/learner_ai_context_assembler.dart';
import 'package:turna/service/locator.dart';

void main() {
  group('CompanionRateLimiter', () {
    test('blocks second acquire within interval', () {
      final lim = CompanionRateLimiter(minInterval: const Duration(seconds: 5));
      expect(lim.tryAcquire('x'), isTrue);
      expect(lim.tryAcquire('x'), isFalse);
      expect(lim.tryAcquire('y'), isTrue);
      lim.reset('x');
      expect(lim.tryAcquire('x'), isTrue);
    });
  });

  group('AiExplainPrefsStore.resolve', () {
    test('explicit prefs wins over ephemeral', () {
      final a = AiExplainPrefsStore(
        initial: const AiExplainPrefsSnapshot(
          replyLanguage: AiReplyLanguage.en,
        ),
      );
      final r = AiExplainPrefsStore.resolve(prefs: a, allowEphemeral: true);
      expect(identical(r, a), isTrue);
      expect(r.replyLanguage, AiReplyLanguage.en);
    });
  });

  group('injectLearnerContext off', () {
    test('assembleIfInjectEnabled returns empty context when inject false',
        () async {
      final prefs = AiExplainPrefsStore(
        initial: const AiExplainPrefsSnapshot(injectLearnerContext: false),
      );
      final ctx = await LearnerAiContextAssembler.assembleIfInjectEnabled(
        languageName: 'Turkish',
        prefs: prefs,
      );
      expect(ctx.isEmpty, isTrue);
      expect(ctx.toPromptBlock(), isNot(contains('Recent mistakes')));
    });

    test('hint system prompt has no LearnerContext when inject off', () {
      final prefs = AiExplainPrefsStore(
        initial: const AiExplainPrefsSnapshot(injectLearnerContext: false),
      );
      final hint = AiHintProvider(
        engine: AiEngine(
          AiHttpClient.withClient(_NoopHttp()),
          AiCache.forTest(maxEntries: 0, enabled: false),
        ),
        prefs: prefs,
      );
      hint.setLearnerContext(LearnerAiContext.assemble(
        languageName: 'Turkish',
        weakTerms: const ['merhaba'],
      ));
      final sys = hint.buildSystemPrompt(const AiQuestionContext(
        language: 'Turkish',
        typeLabel: 'Multiple Choice',
        promptLabel: 'x',
      ));
      expect(sys.contains('[LearnerContext]'), isFalse);
      expect(sys.contains('merhaba'), isFalse);
    });
  });

  group('export does not include AI API key', () {
    test('progress manifest excludes ai.engineConfig', () {
      final exportSrc =
          File('lib/service/export_service.dart').readAsStringSync();
      expect(exportSrc.contains('ai.engineConfig'), isFalse);
      expect(exportSrc.contains('LocalStateKeys.aiEngineConfig'), isFalse);
      // Key must not appear as an exportable field name.
      expect(
        exportSrc.contains(LocalStateKeys.aiEngineConfig),
        isFalse,
      );
    });
  });

  group('companion / course-schema boundary', () {
    test('companion provider sources do not import ai_prompt_builder', () {
      final companionFiles = [
        'lib/application/ai/ai_hint_provider.dart',
        'lib/application/ai/ai_tutor_chat_provider.dart',
        'lib/application/ai/ai_diagnosis_provider.dart',
        'lib/application/ai/dictionary_ai_provider.dart',
        'lib/application/ai/ai_card_explain_provider.dart',
        'lib/application/ai/learner_ai_context.dart',
        'lib/application/ai/learner_ai_context_assembler.dart',
        'lib/application/ai/ai_error_mapper.dart',
        'lib/application/ai/ai_explain_prefs.dart',
        'lib/application/ai/companion_rate_limiter.dart',
        'lib/application/ai/ai_saved_explanations.dart',
      ];
      for (final path in companionFiles) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('ai_prompt_builder'),
          isFalse,
          reason: '$path must not import course prompt builder',
        );
        expect(
          src.contains('"units"') && src.contains('"lessons"'),
          isFalse,
          reason: '$path must not embed units+lessons course schema',
        );
      }
    });
  });
}

class _NoopHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}
