// 回归测试：监听器在 loading 通知里同步重入 ensureSectionLoaded 必须
// 合并到同一个 in-flight future。
//
// 背景（原 Playground「开始」无限卡死成因之一）：ensureSectionLoaded 曾在
// 把 in-flight future 写入 _sectionLoadFutures 之前就同步
// notifyListeners()，监听回调里的同步重入会击穿并发去重，产生重复 fetch
//（用户日志中同一 id 连续多行 "starting fetch"）。修复：先注册 completer
// future，再通知。当时的另一成因是页面侧加载中反复重触发，已随
// Playground 页面一并删除；本文件只守 provider 层的去重不变量。

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';

import '../helpers/in_memory_course_db.dart';

/// 夹具 section —— 自带一个 unit, 用来证明"正文真的被装载了".
///
/// 现成的课程 section 都不行: nt-s2…nt-s8 是"预留 · 待施工"（0 unit）,
/// 而 nt-s1 正是 load() 预载的那一个. 这里自己插一行, 让本测试不依赖课程
/// 资产的施工进度.
const String _fixtureSectionId = 'nt-fixture-body';
const String _fixtureUnitId = 'nt-fixture-body-u1';

Future<void> _insertFixtureSection(CourseDatabase db) async {
  await db.into(db.sections).insert(
        SectionsCompanion.insert(
          id: _fixtureSectionId,
          name: '夹具 · 有正文',
          // 排在课程 section 之后 —— load() 只预载第一个, 夹具不能当第一个.
          sortOrder: const Value(999),
        ),
      );
  await db.into(db.units).insert(
        UnitsCompanion.insert(
          id: _fixtureUnitId,
          sectionId: _fixtureSectionId,
          name: '夹具 unit',
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureSectionLoaded 重入去重', () {
    late CourseProvider provider;
    late String targetSectionId;

    setUp(() async {
      final db = await seedInMemoryCourseDb();
      await _insertFixtureSection(db);
      provider = CourseProvider();
      await provider.load();
      // 选一个 body 尚未加载、但有正文的 section（load() 只预载第一个）。
      targetSectionId = _fixtureSectionId;
      expect(provider.sections.map((s) => s.id), contains(targetSectionId));
      expect(
          provider.sectionLoadState(targetSectionId), SectionLoadState.initial);
    });

    test('loading 通知内同步重入只 fetch 一次', () async {
      var startingFetchCount = 0;
      void capture(LogEvent e) {
        final m = e.message.toString();
        if (m.contains('ensureSectionLoaded') && m.contains('starting fetch')) {
          startingFetchCount++;
        }
      }

      Logger.addLogListener(capture);

      // 与典型页面监听同构：看到 loading 通知就再要一次正文。
      void listener() {
        if (provider.sectionLoadState(targetSectionId) ==
            SectionLoadState.loading) {
          unawaited(provider.ensureSectionLoaded(targetSectionId));
        }
      }

      provider.addListener(listener);
      await provider.ensureSectionLoaded(targetSectionId);
      provider.removeListener(listener);
      Logger.removeLogListener(capture);

      expect(startingFetchCount, 1,
          reason: '重入去重失效会产生多行 "starting fetch"（用户日志症状）');
      expect(
          provider.sectionLoadState(targetSectionId), SectionLoadState.loaded);
      expect(provider.findSectionById(targetSectionId)!.units, isNotEmpty);
    });

    test('加载失败落到 error 态且不重复 fetch', () async {
      // 空库：shells 已在 setUp 从种子库加载，但 body 查询命中空表 →
      // ArgumentError；失败不缓存。
      CourseLoader.overrideDatabase(emptyInMemoryCourseDatabase);

      var fetchAttempts = 0;
      void capture(LogEvent e) {
        final m = e.message.toString();
        if (m.contains('ensureSectionLoaded') && m.contains('starting fetch')) {
          fetchAttempts++;
        }
      }

      Logger.addLogListener(capture);

      void listener() {
        if (provider.sectionLoadState(targetSectionId) ==
            SectionLoadState.loading) {
          unawaited(provider.ensureSectionLoaded(targetSectionId));
        }
      }

      provider.addListener(listener);
      await provider.ensureSectionLoaded(targetSectionId);
      provider.removeListener(listener);
      Logger.removeLogListener(capture);

      expect(fetchAttempts, 1, reason: '同一 section 只应 fetch 一次');
      expect(
          provider.sectionLoadState(targetSectionId), SectionLoadState.error);
    });
  });
}
