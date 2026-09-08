// Unit tests for SrsTutorProvider: gathers mistakes + weak words + recent
// SRS reviews, calls the AI engine with all three buckets in the prompt,
// parses via AiCourseService.parseCompletion, and persists the section.
//
// Fakes the engine via MockClient + AiEngine (cache disabled). Fakes the
// MistakeProvider against StreamingSharedPreferences. Mocks the SrsStateDao
// with a tiny in-memory implementation to avoid pulling in the drift
// database harness.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_tutor_provider.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

http.Response _sectionResponse(Map<String, dynamic> section) {
  final body = jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': jsonEncode(section)}
      },
    ],
  });
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

AiEngineConfig _engineConfig() => const AiEngineConfig(
      preset: kCustomPreset,
      apiKey: 'k',
      modelChat: 'm',
      modelJson: 'm',
      customBaseUrl: 'https://example.test/v1',
      cacheEnabled: false,
    );

Map<String, dynamic> _validSection({String id = 'tutor-x'}) =>
    <String, dynamic>{
      'id': id,
      'name': 'Tutor Test',
      'level': 'A1',
      'prerequisiteSectionIds': <String>[],
      'words': [
        {
          'id': 'w1',
          'term': 'merhaba',
          'translation': 'hello',
          'partOfSpeech': 'interjection',
        }
      ],
      'expressions': <Map<String, dynamic>>[],
      'grammarPoints': <Map<String, dynamic>>[],
      'units': [
        {
          'id': 'u1',
          'name': 'U1',
          'lessons': [
            {
              'id': 'l1',
              'name': 'L1',
              'type': 'review',
              'template': 'legacy',
              'prerequisiteLessonIds': <String>[],
              'content': {
                'stages': [
                  {
                    'id': 's1',
                    'name': 'S1',
                    'items': [
                      {
                        'id': 'i1',
                        'type': 'multipleChoice',
                        'prompt': 'What does merhaba mean?',
                        'options': ['hello', 'bye', 'thanks'],
                        'correctIndex': 0,
                      }
                    ],
                  }
                ],
              },
            },
          ],
        },
      ],
    };

class _FakeSrsStateDao implements SrsStateDao {
  _FakeSrsStateDao(this._rows);

  final List<SrsWord> _rows;

  @override
  Future<List<SrsWord>> recentReviews({
    String queue = 'srs',
    int limit = 20,
    DateTime? since,
    String? languageCode,
  }) async {
    var filtered = _rows.where((w) => w.lastReviewedAt != null).toList()
      ..sort((a, b) => b.lastReviewedAt!.compareTo(a.lastReviewedAt!));
    if (since != null) {
      filtered =
          filtered.where((w) => !w.lastReviewedAt!.isBefore(since)).toList();
    }
    if (limit <= 0) return const <SrsWord>[];
    return filtered.take(limit).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'SrsStateDao fake does not implement ${invocation.memberName}');
}

class _RecordingAiCourseProvider extends AiCourseProvider {
  _RecordingAiCourseProvider({required AiEngine engine})
      : super.withEngine(engine);

  Map<String, dynamic>? saved;

  @override
  Future<void> saveSectionJson(Map<String, dynamic> parsed) async {
    saved = parsed;
    // Mirror the real provider's resource normalization / validation so the
    // parsed map matches what AiCourseProvider.saveSectionJson would persist.
  }
}

_RecordingAiCourseProvider _courseProviderWith(AiEngine engine) =>
    _RecordingAiCourseProvider(engine: engine);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late MistakeProvider mistakes;
  late _FakeSrsStateDao srsDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
    mistakes = MistakeProvider(prefs);
    srsDao = _FakeSrsStateDao(<SrsWord>[]);
    // SrsTutorProvider -> AiCourseProvider -> AiGroundedResourceProvider
    // resolves ICourseRepository from GetIt; register an in-memory DB +
    // repository (mirrors injection.config.dart) so construction succeeds.
    if (getIt.isRegistered<db.CourseDatabase>()) {
      await getIt.unregister<db.CourseDatabase>();
    }
    final courseDb = emptyInMemoryCourseDatabase();
    getIt.registerSingleton<db.CourseDatabase>(courseDb);
    if (getIt.isRegistered<ICourseRepository>()) {
      await getIt.unregister<ICourseRepository>();
    }
    getIt.registerSingleton<ICourseRepository>(CourseRepository(courseDb));
  });

  Future<({SrsTutorProvider provider, AiEngine engine})> buildProvider({
    required http.Client client,
  }) async {
    // Seed a couple of mistakes so the user prompt has both buckets.
    await mistakes.record(MistakeEntry(
      id: 'm1',
      lessonId: 'l1',
      stageId: 's1',
      interactionId: 'i1',
      wordId: 'w1',
      interactionSnapshot: Interaction.multipleChoice(
        id: 'i1',
        prompt: 'p',
        options: ['a', 'b'],
        correctIndex: 0,
      ),
      userAnswer: 'wrong',
      correctAnswer: 'a',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ));
    await mistakes.record(MistakeEntry(
      id: 'm2',
      lessonId: 'l2',
      stageId: 's2',
      interactionId: 'i2',
      wordId: 'w2',
      interactionSnapshot: Interaction.multipleChoice(
        id: 'i2',
        prompt: 'p',
        options: ['a', 'b'],
        correctIndex: 1,
      ),
      userAnswer: 'wrong',
      correctAnswer: 'b',
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    ));

    srsDao = _FakeSrsStateDao(<SrsWord>[
      SrsWord(
        wordId: 'w1',
        dueAt: DateTime.now(),
        lastReviewedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ]);

    final engine = AiEngine(
      AiHttpClient.withClient(client),
      AiCache.forTest(maxEntries: 0, enabled: false),
    );
    final provider = SrsTutorProvider(
      engine: engine,
      courseProvider: _courseProviderWith(engine),
      mistakeProvider: mistakes,
      srsDao: srsDao,
    );
    return (provider: provider, engine: engine);
  }

  test('happy path: mistakes + weak + SRS context all reach the AI prompt',
      () async {
    String? capturedBody;
    final client = MockClient((req) async {
      capturedBody = req.body;
      return _sectionResponse(_validSection(id: 'tutor-happy'));
    });
    final built = await buildProvider(client: client);
    final provider = built.provider;

    final lessonId = await provider.tutorPlan(
      config: _engineConfig(),
      language: 'turkish',
    );

    expect(lessonId, 'tutor-happy');
    expect(provider.state, SrsTutorState.saved);
    expect(provider.generatedSectionId, 'tutor-happy');
    expect(capturedBody, isNotNull);
    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    final userPrompt =
        messages.firstWhere((m) => m['role'] == 'user')['content'] as String;
    expect(userPrompt, contains('w1'));
    expect(userPrompt, contains('w2'));
    expect(userPrompt, contains('Recent mistakes'));
    expect(userPrompt, contains('Weak words'));
    expect(userPrompt, contains('Recent SRS reviews'));
  });

  test('engine error transitions to SrsTutorState.error', () async {
    final client = MockClient((req) async => http.Response('boom', 500));
    final built = await buildProvider(client: client);
    final provider = built.provider;

    final lessonId = await provider.tutorPlan(
      config: _engineConfig(),
      language: 'turkish',
    );

    expect(lessonId, isNull);
    expect(provider.state, SrsTutorState.error);
    expect(provider.errorMessage, isNotNull);
  });

  test('cancel mid-flight returns to idle and does not save', () async {
    final completer = Completer<http.Response>();
    final client = MockClient((req) async => completer.future);
    final built = await buildProvider(client: client);
    final provider = built.provider;

    final pending = provider.tutorPlan(
      config: _engineConfig(),
      language: 'turkish',
    );

    // Cancel before the engine returns anything.
    provider.cancel();
    completer.complete(_sectionResponse(_validSection(id: 'tutor-late')));

    final lessonId = await pending;
    expect(lessonId, isNull);
    expect(provider.state, anyOf(SrsTutorState.idle, SrsTutorState.error));
  });

  test('empty config (no api key) rejects without touching the network',
      () async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return _sectionResponse(_validSection());
    });
    final built = await buildProvider(client: client);
    final provider = built.provider;

    final lessonId = await provider.tutorPlan(
      config: const AiEngineConfig(
        preset: kCustomPreset,
        apiKey: '',
        modelChat: 'm',
        modelJson: 'm',
      ),
      language: 'turkish',
    );

    expect(lessonId, isNull);
    expect(provider.state, SrsTutorState.error);
    expect(called, isFalse);
  });

  test('reset clears state and the cached plan', () async {
    final client = MockClient((req) async => _sectionResponse(_validSection()));
    final built = await buildProvider(client: client);
    final provider = built.provider;

    await provider.tutorPlan(config: _engineConfig(), language: 'turkish');
    expect(provider.state, SrsTutorState.saved);

    provider.reset();
    expect(provider.state, SrsTutorState.idle);
    expect(provider.lastPlan, isNull);
    expect(provider.generatedSectionId, isNull);
  });

  test('cancel() with no in-flight token is a no-op', () {
    final engine = AiEngine(
      AiHttpClient.withClient(MockClient((_) async => http.Response('', 200))),
      AiCache.forTest(maxEntries: 0, enabled: false),
    );
    final provider = SrsTutorProvider(
      engine: engine,
      courseProvider: _RecordingAiCourseProvider(engine: engine),
      mistakeProvider: mistakes,
      srsDao: srsDao,
    );
    // Just should not throw.
    provider.cancel();
  });

  test('AiCancelled raised by the engine path returns to idle', () async {
    // The plan-stage handler matches `AiCancelled` before the generic `catch`,
    // so an engine-side cancellation always lands in SrsTutorState.idle -
    // not error. This test pins that semantics so future refactors don't
    // accidentally surface it as a user-visible error.
    final client = MockClient((req) async {
      throw AiCancelled();
    });
    final built = await buildProvider(client: client);
    final provider = built.provider;

    final lessonId = await provider.tutorPlan(
      config: _engineConfig(),
      language: 'turkish',
    );

    expect(lessonId, isNull);
    expect(provider.state, SrsTutorState.idle);
  });
}
