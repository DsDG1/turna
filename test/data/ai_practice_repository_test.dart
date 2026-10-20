// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/data/ai_practice_repository.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/domain/ai/ai_course.dart';

import '../helpers/in_memory_course_db.dart';

AiCourse _course({
  String id = 'aip-1',
  bool pinned = false,
  DateTime? expiresAt,
  int minute = 0,
}) {
  final at = DateTime(2026, 1, 1).add(Duration(minutes: minute));
  return AiCourse(
    id: id,
    languageCode: 'tr',
    title: 'Practice $id',
    source: AiPracticeSource.mistakes,
    level: 'A2',
    topic: 'topic',
    pinned: pinned,
    expiresAt: expiresAt ?? at.add(kAiCourseDraftTtl),
    createdAt: at,
    updatedAt: at,
  );
}

AiCourseVersion _version({
  String id = 'aip-1',
  String courseId = 'aip-1',
  AiPracticeStatus status = AiPracticeStatus.ready,
  String? sectionJson = '{"id":"aip-1"}',
  String? qualityJson,
  String? error,
  int minute = 0,
}) {
  final at = DateTime(2026, 1, 1).add(Duration(minutes: minute));
  return AiCourseVersion(
    id: id,
    courseId: courseId,
    status: status,
    sectionJson: sectionJson,
    requestJson: '{"id":"$courseId"}',
    qualityJson: qualityJson,
    progressDone: status == AiPracticeStatus.ready ? 1 : 0,
    progressTotal: 1,
    errorMessage: error,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.CourseDatabase database;
  late AiPracticeRepository repository;

  setUp(() {
    database = emptyInMemoryCourseDatabase();
    repository = AiPracticeRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('round-trips a course together with its versions', () async {
    await repository.upsertCourse(_course());
    await repository.upsertVersion(_version(qualityJson: '{"passed":true}'));

    final rows = await repository.list(languageCode: 'tr');
    expect(rows, hasLength(1));
    final course = rows.single;
    expect(course.title, 'Practice aip-1');
    expect(course.source, AiPracticeSource.mistakes);
    expect(course.level, 'A2');
    expect(course.status, AiPracticeStatus.ready);
    expect(course.isPlayable, isTrue);
    expect(course.sectionJson, '{"id":"aip-1"}');
    expect(course.qualityJson, '{"passed":true}');
    expect(course.versions, hasLength(1));

    final byId = await repository.byId('aip-1');
    expect(byId?.id, 'aip-1');
    expect(await repository.byId('missing'), isNull);
  });

  test('a second version becomes the newest but the old one stays playable',
      () async {
    await repository.upsertCourse(_course());
    await repository.upsertVersion(_version(id: 'v1', sectionJson: '{"v":1}'));
    await repository.upsertVersion(_version(
      id: 'v2',
      status: AiPracticeStatus.failed,
      sectionJson: null,
      error: 'boom',
      minute: 5,
    ));

    final course = (await repository.list()).single;
    expect(course.versions.map((v) => v.id), ['v2', 'v1']);
    expect(course.status, AiPracticeStatus.failed);
    // A failed re-generation must not hide the previous working content.
    expect(course.isPlayable, isTrue);
    expect(course.playableVersion?.id, 'v1');
  });

  test('markInterruptedOnStartup rewrites queued/running versions only',
      () async {
    for (final (id, status) in [
      ('queued', AiPracticeStatus.queued),
      ('running', AiPracticeStatus.running),
      ('ready', AiPracticeStatus.ready),
    ]) {
      await repository.upsertCourse(_course(id: id));
      await repository
          .upsertVersion(_version(id: id, courseId: id, status: status));
    }

    final changed = await repository.markInterruptedOnStartup();
    expect(changed, 2);

    final byId = {for (final row in await repository.list()) row.id: row};
    expect(byId['queued']?.status, AiPracticeStatus.interrupted);
    expect(byId['running']?.status, AiPracticeStatus.interrupted);
    expect(byId['ready']?.status, AiPracticeStatus.ready);
    expect(byId['queued']?.errorMessage, isNotNull);
  });

  test('pruneExpired deletes expired drafts but never favourites', () async {
    final now = DateTime(2026, 1, 8);
    await repository.upsertCourse(_course(
      id: 'expired',
      expiresAt: now.subtract(const Duration(minutes: 1)),
    ));
    await repository
        .upsertVersion(_version(id: 'expired', courseId: 'expired'));
    await repository.upsertCourse(_course(
      id: 'fresh',
      expiresAt: now.add(const Duration(days: 3)),
    ));
    await repository.upsertVersion(_version(id: 'fresh', courseId: 'fresh'));
    await repository.upsertCourse(_course(
      id: 'kept',
      pinned: true,
      expiresAt: now.subtract(const Duration(days: 30)),
    ));
    await repository.upsertVersion(_version(id: 'kept', courseId: 'kept'));

    final removed = await repository.pruneExpired(now: now);
    expect(removed, 1);

    final ids = {for (final row in await repository.list()) row.id};
    expect(ids, {'fresh', 'kept'});
    // The version rows of the swept course are gone too.
    expect(await repository.byId('expired'), isNull);
  });

  test('favouriting clears the deadline; un-favouriting starts a new week',
      () async {
    await repository.upsertCourse(_course(expiresAt: DateTime(2026, 1, 3)));
    await repository.upsertVersion(_version());

    final now = DateTime(2026, 1, 2);
    await repository.setPinned(['aip-1'], pinned: true, now: now);
    var course = (await repository.list()).single;
    expect(course.pinned, isTrue);
    expect(course.expiresAt, isNull);

    await repository.setPinned(['aip-1'], pinned: false, now: now);
    course = (await repository.list()).single;
    expect(course.pinned, isFalse);
    expect(course.expiresAt, now.add(kAiCourseDraftTtl));
  });

  test('deleteMany removes only the selected courses and their versions',
      () async {
    await repository.upsertCourse(_course(id: 'a'));
    await repository.upsertVersion(_version(id: 'a', courseId: 'a'));
    await repository.upsertCourse(_course(id: 'b'));
    await repository.upsertVersion(_version(id: 'b', courseId: 'b'));

    await repository.deleteMany(['a']);

    final ids = {for (final row in await repository.list()) row.id};
    expect(ids, {'b'});
  });
}
