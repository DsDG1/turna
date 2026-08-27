// Plan 1 Phase 4 tests: deterministic rules skip the AI, the remaining
// notetypes travel in ONE batched request carrying privacy-safe features
// only, AI verdicts are consistency-checked and downgraded, persisted rules
// are reused by signature, and failures fall back with an explicit label.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_result.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/service/locator.dart';

class _RecordingAiEngine extends AiEngine {
  _RecordingAiEngine(this.reply)
      : super(
          AiHttpClient.withClient(
            MockClient((_) async => throw UnimplementedError()),
          ),
          AiCache.forTest(),
        );

  final String reply;
  int chatCalls = 0;
  List<Map<String, dynamic>> lastMessages = const [];

  @override
  Future<AiEngineResult> chat({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.5,
    void Function(String delta)? onChunk,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    chatCalls++;
    lastMessages = messages;
    return AiEngineResult(content: reply);
  }
}

AnkiNotetype _notetype(
  int id,
  String name,
  List<String> fields, {
  bool isCloze = false,
}) =>
    AnkiNotetype(id: id, name: name, fieldNames: fields, isCloze: isCloze);

AnkiNote _note(int id, int mid, List<String> fields, {String tags = ''}) =>
    AnkiNote(id: id, mid: mid, fields: fields, tags: tags);

const _config = AiEngineConfig(apiKey: 'test-key');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late AnkiNotetypeRuleStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(preferences);
    store = AnkiNotetypeRuleStore(prefs);
  });

  test('cloze and choice layouts are recognized by rules without any AI call',
      () async {
    final engine = _RecordingAiEngine('{}');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final notetypes = {
      1: _notetype(1, 'Cloze', ['Text', 'Extra'], isCloze: true),
      2: _notetype(2, 'MCQ', ['Question', 'A', 'B', 'C', 'Answer']),
    };
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: notetypes,
      notes: const [],
    );

    expect(results[1]!.source, CardRecognitionSource.rule);
    expect(results[1]!.mapping.type, NotetypeMappingType.cloze);
    expect(results[1]!.confidence, greaterThan(0.9));
    expect(results[2]!.source, CardRecognitionSource.rule);
    expect(results[2]!.mapping.type, NotetypeMappingType.multipleChoice);
    expect(engine.chatCalls, 0,
        reason: 'high-confidence rule hits never call the AI');
  });

  test('offline preview accepts explicit Front/Back field-name rules',
      () async {
    final engine = _RecordingAiEngine('{}');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final results = await pipeline.recognizeAll(
      config: const AiEngineConfig(apiKey: ''),
      notetypes: {3: _notetype(3, 'Basic', ['Front', 'Back'])},
      notes: const [],
    );

    expect(results[3]!.source, CardRecognitionSource.rule);
    expect(results[3]!.mapping.type, NotetypeMappingType.wordEntry);
    expect(results[3]!.needsConfirmation, isFalse);
    expect(engine.chatCalls, 0);
  });

  test(
      'undecided notetypes share ONE batched AI request with privacy-safe '
      'features only', () async {
    final engine = _RecordingAiEngine(jsonEncode({
      'results': [
        {
          'id': 7,
          'mapping': 'wordEntry',
          'frontField': 'Field1',
          'backField': 'Field2',
          'confidence': 0.9,
          'reason': 'short front term + translation back',
        },
      ]
    }));
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final notetypes = {
      7: _notetype(7, 'CustomMix', ['Field1', 'Field2', 'Extra'])
    };
    final notes = [
      _note(1, 7, ['ev', 'house', 'noun']),
      _note(2, 7, ['kitap', 'book', 'noun']),
    ];
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: notetypes,
      notes: notes,
    );

    final result = results[7]!;
    expect(result.source, CardRecognitionSource.ai);
    expect(result.mapping.type, NotetypeMappingType.wordEntry);
    expect(result.mapping.frontFieldIndex, 0);
    expect(result.mapping.backFieldIndex, 1);
    expect(result.confidence, greaterThan(0.8));
    expect(engine.chatCalls, 1,
        reason: 'one batch request replaces N serial requests');

    // Privacy contract: the outbound user message carries shapes, never the
    // note content ("ev"/"house"/"kitap" must not appear anywhere).
    final userMessage = engine.lastMessages.last['content'].toString();
    expect(userMessage, contains('"avgLen"'));
    expect(userMessage, contains('Field1'));
    expect(userMessage, isNot(contains('house')));
    expect(userMessage, isNot(contains('kitap')));
  });

  test('shape-inconsistent AI verdicts are downgraded with warnings', () async {
    final engine = _RecordingAiEngine(jsonEncode({
      'results': [
        {
          'id': 9,
          'mapping': 'listenPick',
          'frontField': 'Field1',
          'backField': 'Field2',
          'confidence': 0.95,
          'reason': 'assumed listening',
        },
      ]
    }));
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: {
        9: _notetype(9, 'Plain', ['Field1', 'Field2'])
      },
      notes: [
        _note(1, 9, ['long sentence front', 'long answer back'])
      ],
    );

    final result = results[9]!;
    expect(result.source, CardRecognitionSource.ai);
    expect(result.confidence, lessThan(0.6),
        reason: 'no front-face audio evidence -> heavy downgrade');
    expect(result.warnings, isNotEmpty);
    expect(result.needsConfirmation, isTrue);
  });

  test('AI failure or missing config falls back explicitly per notetype',
      () async {
    final engine = _RecordingAiEngine('not json at all');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: {
        3: _notetype(3, 'Ambiguous', ['Field1', 'Field2'])
      },
      notes: const [],
    );

    final result = results[3]!;
    expect(result.source, CardRecognitionSource.fallback);
    expect(result.confidence, greaterThan(0.6));
    expect(result.needsConfirmation, isFalse);
  });

  test('persisted rules are saved by signature and reused without AI',
      () async {
    final signature = NotetypeSignature.of(
      _notetype(5, 'Vocab2', ['Front', 'Back']),
      version: CardRecognitionPipeline.recognizerVersion,
    ).value;
    await store.save(
      signature,
      const NotetypeMapping(type: NotetypeMappingType.wordEntry),
    );

    final engine = _RecordingAiEngine('{}');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: store,
    );
    // A different deck importing the same structural notetype reuses the
    // rule offline.
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: {
        11: _notetype(11, 'Renamed', ['Front', 'Back'])
      },
      notes: const [],
    );

    final result = results[11]!;
    expect(result.source, CardRecognitionSource.persisted);
    expect(result.mapping.type, NotetypeMappingType.wordEntry);
    expect(result.confidence, greaterThan(0.9));
    expect(engine.chatCalls, 0);
  });

  test('signatures separate notetypes that only differ in structure', () {
    final twoField = NotetypeSignature.of(
      _notetype(1, 'A', ['Front', 'Back']),
    ).value;
    final threeField = NotetypeSignature.of(
      _notetype(2, 'B', ['Front', 'Back', 'Extra']),
    ).value;
    final cloze = NotetypeSignature.of(
      _notetype(3, 'C', ['Text', 'Extra'], isCloze: true),
    ).value;
    expect(twoField, isNot(equals(threeField)));
    expect(twoField, isNot(equals(cloze)));
    // Same structure under a different name/id shares the signature.
    expect(
      NotetypeSignature.of(_notetype(4, 'Other', ['Front', 'Back'])).value,
      twoField,
    );
  });

  test('sample A/B/C text is recognized as choice without option fields',
      () async {
    final engine = _RecordingAiEngine('{}');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: {4: _notetype(4, '1000题', ['Prompt', 'Key'])},
      notes: [
        _note(1, 4, [
          '首都是？\nA. 伦敦\nB. 巴黎\nC. 柏林',
          'B',
        ]),
        _note(2, 4, [
          '2+2？\nA. 3\nB. 4\nC. 5',
          'B',
        ]),
      ],
    );
    expect(results[4]!.mapping.type, NotetypeMappingType.multipleChoice);
    expect(results[4]!.source, CardRecognitionSource.rule);
    expect(engine.chatCalls, 0);
  });

  test('sample cloze markers are recognized without the cloze flag', () async {
    final engine = _RecordingAiEngine('{}');
    final pipeline = CardRecognitionPipeline(
      engine: engine,
      ruleStore: AnkiNotetypeRuleStore(prefs),
    );
    final results = await pipeline.recognizeAll(
      config: _config,
      notetypes: {5: _notetype(5, 'Text', ['Text', 'Extra'])},
      notes: [
        _note(1, 5, ['The {{c1::sun}} is hot', '']),
      ],
    );
    expect(results[5]!.mapping.type, NotetypeMappingType.cloze);
    expect(engine.chatCalls, 0);
  });
}
