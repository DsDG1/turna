// Regression test: the AI grounding resource pool must be scoped to the
// current practice language — with Turkish and French installed, the context
// fed to AI prompts may only contain the active language's rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

class _RecordingRepository implements ICourseRepository {
  final List<(String, String?)> calls = [];

  @override
  Future<List<WordEntry>> vocabulary({String? languageCode}) async {
    calls.add(('vocabulary', languageCode));
    return const [];
  }

  @override
  Future<List<Expression>> expressions({String? languageCode}) async {
    calls.add(('expressions', languageCode));
    return const [];
  }

  @override
  Future<List<GrammarPoint>> grammarPoints({String? languageCode}) async {
    calls.add(('grammarPoints', languageCode));
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GetIt.I.reset);

  test('load scopes every fetch to the selected language', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    GetIt.I.registerSingleton<LanguageProvider>(
      LanguageProvider(prefs)..setLanguageCode(LanguageCodes.french),
    );

    final repo = _RecordingRepository();
    final provider = AiGroundedResourceProvider(repository: repo);

    await provider.load();

    expect(repo.calls, hasLength(3));
    expect(
      repo.calls.map((c) => c.$2).toSet(),
      {LanguageCodes.french},
    );
  });

  test('without a LanguageProvider the fetch stays unscoped (tests)', () async {
    final repo = _RecordingRepository();
    final provider = AiGroundedResourceProvider(repository: repo);

    await provider.load();

    expect(repo.calls.map((c) => c.$2).toSet(), {null});
  });
}
