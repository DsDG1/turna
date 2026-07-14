// Tests for the bundled course JSON loader, the on-disk course data, and the
// strict course validator. The bundled course is currently a minimal Turkish
// scaffold (one section, one lesson, empty vocab) — these tests assert the
// loader works against that scaffold and that the validators catch structural
// violations in inline lesson graphs.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/courses/course_validator.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/listening_phase.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/sub_lesson.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/domain/course/word_entry.dart';

import '../helpers/in_memory_course_db.dart';

/// Per-section files live under this directory; the index orders them.
final Directory _sectionsDir =
    Directory('assets/courses/turkish/sections');

/// Parse every per-section file (in stable, sorted order) into a flat list
/// of [Section]s, mirroring what [CourseLoader.load] assembles at runtime.
List<Section> _loadAllSections() {
  final files = _sectionsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files
      .map((f) => parseSection(f.readAsStringSync()))
      .toList(growable: false);
}

void main() {
  // CourseLoader.load() reads the bundled assets via rootBundle, which
  // requires the Flutter binding to be initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('turkish/sections/*.json', () {
    late List<Section> sections;

    setUpAll(() {
      sections = _loadAllSections();
    });

    test('parses without error and is non-empty', () {
      expect(sections, isNotEmpty);
    });

    test('all section / unit / lesson ids are unique', () {
      final sectionIds = sections.map((s) => s.id).toSet();
      expect(sectionIds.length, sections.length,
          reason: 'duplicate section ids detected');

      final unitIds = <String>{};
      for (final s in sections) {
        for (final u in s.units) {
          expect(unitIds.add(u.id), isTrue,
              reason: 'duplicate unit id: ${u.id}');
        }
      }

      final lessonIds = <String>{};
      for (final s in sections) {
        for (final u in s.units) {
          for (final l in u.lessons) {
            expect(lessonIds.add(l.id), isTrue,
                reason: 'duplicate lesson id: ${l.id}');
          }
        }
      }
    });

    test('all stage ids are unique within each lesson', () {
      for (final s in sections) {
        for (final u in s.units) {
          for (final l in u.lessons) {
            final stageIds = <String>{};
            for (final stage in l.content.stages) {
              expect(stageIds.add(stage.id), isTrue,
                  reason: 'duplicate stage id in lesson ${l.id}');
            }
          }
        }
      }
    });

    test('all item ids are unique within each stage and non-empty', () {
      var totalInteractions = 0;
      for (final s in sections) {
        for (final u in s.units) {
          for (final l in u.lessons) {
            for (final stage in l.content.stages) {
              final ids = stage.items
                  .map((i) => i.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              expect(ids.toSet().length, ids.length,
                  reason: 'duplicate item id in ${l.id}/${stage.id}');
              expect(stage.items.every((i) => i.id != ''), isTrue,
                  reason: 'item without id in ${l.id}/${stage.id}');
              totalInteractions += stage.items.length;
            }
          }
        }
      }
      expect(totalInteractions, greaterThan(0));
    });

    test('every ShowWord references an existing word id', () {
      final vocab = parseVocabulary(
          File('assets/courses/turkish/vocab.json').readAsStringSync());
      final wordIds = vocab.map((w) => w.id).toSet();
      for (final s in sections) {
        for (final u in s.units) {
          for (final l in u.lessons) {
            for (final stage in l.content.stages) {
              for (final item in stage.items) {
                if (item is ShowWord) {
                  expect(wordIds.contains(item.wordId), isTrue,
                      reason: 'ShowWord in ${l.id} references missing '
                          'wordId ${item.wordId}');
                }
              }
            }
          }
        }
      }
    });
  });

  group('turkish/vocab.json', () {
    late List<WordEntry> words;

    setUpAll(() {
      words = parseVocabulary(
          File('assets/courses/turkish/vocab.json').readAsStringSync());
    });

    test('parses without error', () {
      // The scaffold ships an empty (but well-formed) vocab list.
      expect(words, isA<List<WordEntry>>());
    });

    test('all word ids are unique', () {
      final ids = words.map((w) => w.id).toSet();
      expect(ids.length, words.length);
    });
  });

  group('CourseLoader.load (in-memory DB)', () {
    setUpAll(() async {
      await seedInMemoryCourseDb();
    });

    test('yields section shells; bodies load on demand', () async {
      final course = await CourseLoader.load();
      // Shells are non-empty and carry no units until loaded on demand.
      expect(course.sectionShells, isNotEmpty);
      for (final shell in course.sectionShells) {
        expect(shell.units, isEmpty,
            reason: 'section ${shell.id} shell should have empty units');
      }

      // The scaffold's single section's L1 tree loads lazily and is cached.
      final world1 = await CourseLoader.loadSection('section1');
      final world2 = await CourseLoader.loadSection('section1');
      expect(identical(world1, world2), isTrue,
          reason: 'loadSection should cache the resolved section');
      expect(world1.units, isNotEmpty);

      // Tree lessons are metadata-only; content comes from lessonById.
      final meta = world1.units
          .expand((u) => u.lessons)
          .firstWhere((l) => l.id == 's1-l1');
      expect(meta.content.stages, isEmpty);

      final body = await CourseLoader.loadLessonById('s1-l1');
      expect(body.content.stages, isNotEmpty);
    });

    test('loadSection throws for an unknown section id', () async {
      await CourseLoader.load(); // ensure index is loaded
      expect(() => CourseLoader.loadSection('does-not-exist'),
          throwsArgumentError);
    });

    test('loadLessonById returns the right lesson with content', () async {
      await CourseLoader.load();
      final lesson = await CourseLoader.loadLessonById('s1-l1');
      expect(lesson.id, 's1-l1');
      expect(lesson.content.stages, isNotEmpty);
    });

    test('loadLessonById throws for an unknown id', () async {
      await CourseLoader.load();
      expect(() => CourseLoader.loadLessonById('does-not-exist'),
          throwsArgumentError);
    });

    test('DB reconstruction matches seed metadata; bodies via lessonById',
        () async {
      await CourseLoader.load();
      final fromDb = await CourseLoader.loadSection('section1');
      final fromFile = parseSection(
          File('assets/courses/turkish/sections/section1.json')
              .readAsStringSync());
      expect(fromDb.id, fromFile.id);
      expect(fromDb.name, fromFile.name);
      expect(
        fromDb.units.map((u) => u.id).toList(),
        fromFile.units.map((u) => u.id).toList(),
      );
      final dbLessons = [
        for (final u in fromDb.units) ...u.lessons,
      ];
      final fileLessons = [
        for (final u in fromFile.units) ...u.lessons,
      ];
      expect(
        dbLessons.map((l) => l.id).toList(),
        fileLessons.map((l) => l.id).toList(),
      );
      for (final fileLesson in fileLessons) {
        final body = await CourseLoader.loadLessonById(fileLesson.id);
        expect(body.content, fileLesson.content,
            reason: 'body mismatch for ${fileLesson.id}');
      }
    });
  });

  group('Lesson.flattenedStages', () {
    test('legacy lessons keep content.stages unchanged', () {
      const lesson = Lesson(
        id: 'l-legacy',
        name: 'Legacy',
        template: LessonTemplate.legacy,
        content: LessonContent(stages: [
          Stage(
            id: 's1',
            name: 'Stage 1',
            items: [Interaction.showWord(id: 'sw1', wordId: 'w1')],
          ),
        ]),
      );
      expect(lesson.flattenedStages, hasLength(1));
      expect(lesson.flattenedStages.first.id, 's1');
      expect(lesson.flattenedStages.first.name, 'Stage 1');
    });

    test('intro lessons flatten subLessons with prefixed ids', () {
      const lesson = Lesson(
        id: 'l-intro',
        name: 'Intro',
        template: LessonTemplate.intro,
        content: LessonContent(
          subLessons: [
            SubLesson(
              id: 'sub-1',
              name: 'Greetings',
              stages: [
                Stage(
                  id: 'vocab',
                  name: 'Vocab',
                  items: [Interaction.showWord(id: 'sw1', wordId: 'w1')],
                ),
                Stage(
                  id: 'practice',
                  name: 'Practice',
                  items: [Interaction.multipleChoice(
                    id: 'mc1',
                    prompt: 'p',
                    options: ['a', 'b'],
                    correctIndex: 0,
                  )],
                ),
              ],
            ),
          ],
        ),
      );
      expect(lesson.flattenedStages, hasLength(2));
      expect(lesson.flattenedStages.first.id, 'sub-sub-1-vocab');
      expect(lesson.flattenedStages.first.name, 'Greetings > Vocab');
      expect(lesson.flattenedStages.last.id, 'sub-sub-1-practice');
    });

    test('listening lessons include summary as synthetic listenOnly', () {
      const lesson = Lesson(
        id: 'l-listening',
        name: 'Listening',
        template: LessonTemplate.listening,
        content: LessonContent(
          listeningPhases: [
            ListeningPhase(
              id: 'lp-word',
              name: 'Word Pairing',
              type: ListeningPhaseType.wordPairing,
              items: [
                Interaction.multipleChoice(
                  id: 'mc1',
                  prompt: 'p',
                  options: ['a', 'b'],
                  correctIndex: 0,
                ),
              ],
            ),
            ListeningPhase(
              id: 'lp-summary',
              name: 'Summary',
              type: ListeningPhaseType.summary,
              transcript: 'Merhaba!',
              items: [],
            ),
          ],
        ),
      );
      expect(lesson.flattenedStages, hasLength(2));
      expect(lesson.flattenedStages.first.id, 'lp-lp-word');
      expect(lesson.flattenedStages.first.name, 'Word Pairing');
      final summary = lesson.flattenedStages.last;
      expect(summary.id, 'lp-lp-summary');
      expect(summary.name, 'Summary');
      expect(summary.items, hasLength(1));
      expect(summary.items.single, isA<ListenOnly>());
      final listenOnly = summary.items.single as ListenOnly;
      expect(listenOnly.id, 'lp-summary-listen');
      expect(listenOnly.transcript, 'Merhaba!');
    });

    test('reading lessons keep content.stages as questions', () {
      const lesson = Lesson(
        id: 'l-reading',
        name: 'Reading',
        template: LessonTemplate.reading,
        content: LessonContent(
          stages: [
            Stage(
              id: 'q1',
              name: 'Question 1',
              items: [Interaction.readingMcq(
                id: 'mc1',
                prompt: 'p',
                options: ['a', 'b'],
                correctIndex: 0,
              )],
            ),
          ],
        ),
      );
      expect(lesson.flattenedStages, hasLength(1));
      expect(lesson.flattenedStages.first.id, 'q1');
    });
  });

  group('validateCourse', () {
    late List<WordEntry> vocab;

    setUpAll(() {
      vocab = parseVocabulary(
          File('assets/courses/turkish/vocab.json').readAsStringSync());
    });

    List<Section> oneLessonSections(Lesson lesson) => [
          Section(
            id: 's',
            name: 'S',
            description: '',
            units: [
              Unit(
                id: 'u',
                name: 'U',
                description: '',
                lessons: [lesson],
              )
            ],
          )
        ];

    test('accepts a well-formed course (no throw)', () {
      final sections = _loadAllSections();
      // The bundled course must pass its own validator.
      expect(() => validateCourse(sections, vocab), returnsNormally);
    });

    test('throws on a duplicate stage id within a lesson', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        content: LessonContent(stages: [
          Stage(
            id: 'stage-dup',
            name: 'A',
            items: [Interaction.multipleChoice(id: 'i1', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
          Stage(
            id: 'stage-dup',
            name: 'B',
            items: [Interaction.multipleChoice(id: 'i2', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws on an empty item id', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.multipleChoice(id: '', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws on a dangling ShowWord wordId', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.showWord(id: 'item', wordId: 'no-such-word')],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws when intro template has no subLessons', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        template: LessonTemplate.intro,
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.multipleChoice(id: 'i1', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws when listening template has no listeningPhases', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        template: LessonTemplate.listening,
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.multipleChoice(id: 'i1', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws when reading template has no passage', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        template: LessonTemplate.reading,
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.readingMcq(id: 'i1', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateCourse(oneLessonSections(lesson), vocab),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });

  group('validateSectionTree', () {
    test('accepts metadata-only section within scale limits', () {
      final lessons = List.generate(
        5,
        (i) => Lesson(
          id: 'l-$i',
          name: 'L$i',
          content: const LessonContent(),
        ),
      );
      final section = Section(
        id: 's',
        name: 'S',
        units: [
          Unit(id: 'u', name: 'U', lessons: lessons),
        ],
      );
      expect(() => validateSectionTree(section), returnsNormally);
    });

    test('throws when units exceed kMaxUnitsPerSection', () {
      final unitsFixed = [
        for (var i = 0; i < kMaxUnitsPerSection + 1; i++)
          Unit(
            id: 'u-$i',
            name: 'U$i',
            lessons: [
              Lesson(id: 'l-$i', name: 'L', content: const LessonContent()),
            ],
          ),
      ];
      final section = Section(id: 's', name: 'S', units: unitsFixed);
      expect(
        () => validateSectionTree(section),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws when lessons per unit exceed kMaxLessonsPerUnit', () {
      final lessons = List.generate(
        kMaxLessonsPerUnit + 1,
        (i) => Lesson(
          id: 'l-$i',
          name: 'L$i',
          content: const LessonContent(),
        ),
      );
      final section = Section(
        id: 's',
        name: 'S',
        units: [Unit(id: 'u', name: 'U', lessons: lessons)],
      );
      expect(
        () => validateSectionTree(section),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });

  group('validateSection', () {
    late Set<String> vocabIds;

    setUpAll(() {
      final vocab = parseVocabulary(
          File('assets/courses/turkish/vocab.json').readAsStringSync());
      vocabIds = {for (final w in vocab) w.id};
    });

    Section oneLessonSection(Lesson lesson) => Section(
          id: 's',
          name: 'S',
          description: '',
          units: [
            Unit(
              id: 'u',
              name: 'U',
              description: '',
              lessons: [lesson],
            )
          ],
        );

    test('accepts each bundled section in isolation (no throw)', () {
      for (final section in _loadAllSections()) {
        expect(() => validateSection(section, vocabIds), returnsNormally,
            reason: 'section ${section.id} should pass per-section validation');
      }
    });

    test('throws on a duplicate stage id within a lesson', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        content: LessonContent(stages: [
          Stage(
            id: 'stage-dup',
            name: 'A',
            items: [Interaction.multipleChoice(id: 'i1', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
          Stage(
            id: 'stage-dup',
            name: 'B',
            items: [Interaction.multipleChoice(id: 'i2', prompt: 'p', options: ['a', 'b'], correctIndex: 0)],
          ),
        ]),
      );
      expect(
        () => validateSection(oneLessonSection(lesson), vocabIds),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('throws on a dangling ShowWord wordId', () {
      const lesson = Lesson(
        id: 'l',
        name: 'L',
        content: LessonContent(stages: [
          Stage(
            id: 'stage',
            name: 'A',
            items: [Interaction.showWord(id: 'item', wordId: 'no-such-word')],
          ),
        ]),
      );
      expect(
        () => validateSection(oneLessonSection(lesson), vocabIds),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });
}