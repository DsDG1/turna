import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_tutor_chat_session.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences preferences;
  late AiTutorChatSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await StreamingSharedPreferences.instance;
    store = AiTutorChatSessionStore(prefs: AppPrefs(preferences));
  });

  test('session json round-trips mode, language, and messages', () async {
    await store.save(const AiTutorChatSession(
      modeName: 'roleplay',
      language: 'Turkish',
      messages: [
        AiChatMessage(role: 'user', content: 'merhaba'),
        AiChatMessage(role: 'assistant', content: 'merhaba!'),
      ],
    ));

    final loaded = store.load();
    expect(loaded, isNotNull);
    expect(loaded!.modeName, 'roleplay');
    expect(loaded.language, 'Turkish');
    expect(loaded.messages.map((m) => m.content), ['merhaba', 'merhaba!']);
    expect(store.hasSession, isTrue);
  });

  test('empty and blank messages are not a session', () async {
    await store.save(const AiTutorChatSession(
      modeName: 'qa',
      language: 'Turkish',
      messages: [AiChatMessage(role: 'assistant', content: '   ')],
    ));
    expect(store.load(), isNull);
    expect(store.hasSession, isFalse);
  });

  test('a new chat keeps the previous transcript in the list', () async {
    await store.save(const AiTutorChatSession(
      modeName: 'qa',
      language: 'Turkish',
      messages: [AiChatMessage(role: 'user', content: 'first')],
    ));
    await store.beginNew();
    expect(store.load(), isNull);
    expect(store.hasSession, isTrue);

    await store.save(const AiTutorChatSession(
      modeName: 'roleplay',
      language: 'Turkish',
      messages: [AiChatMessage(role: 'user', content: 'second')],
    ));
    expect(store.list(), hasLength(2));
    expect(store.load()?.messages.single.content, 'second');
    expect(store.list().map((s) => s.title), containsAll(['first', 'second']));
  });

  test('legacy single-object json still restores', () async {
    await preferences.setString(
      kTutorChatSessionKey,
      '{"mode":"qa","language":"Turkish","messages":[{"role":"user","content":"eski"}]}',
    );
    expect(store.load()?.messages.single.content, 'eski');
    expect(store.list(), hasLength(1));
  });

  test('corrupt json is an empty session', () async {
    await preferences.setString(kTutorChatSessionKey, '{not json');
    expect(store.load(), isNull);
  });

  test('hub resumes tutor chat only when a session exists', () {
    final task = AiRecentTask(
      kind: AiTaskKind.tutorChat,
      summary: '自由问答',
      timestamp: DateTime.utc(2026, 9, 22),
      route: AiRecentTaskRoute.tutorChat,
    );
    expect(
      isAiCompanionTaskResumable(task, tutorChatHasSession: false),
      isFalse,
    );
    expect(
      isAiCompanionTaskResumable(task, tutorChatHasSession: true),
      isTrue,
    );
    expect(
      isAiCompanionTaskResumable(
        AiRecentTask(
          kind: AiTaskKind.wish,
          summary: 'wish',
          timestamp: DateTime.utc(2026, 9, 22),
          route: AiRecentTaskRoute.wishChat,
        ),
        tutorChatHasSession: true,
      ),
      isFalse,
    );
  });
}
