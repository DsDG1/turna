// 回归测试：Playground「开始」无限卡死（自激重试风暴）的两个成因。
//
//  A. CourseProvider.ensureSectionLoaded 曾在把 in-flight future 写入
//     _sectionLoadFutures 之前就同步 notifyListeners()，监听回调里的同步
//     重入会击穿并发去重，产生重复 fetch（用户日志中同一 id 连续多行
//     "starting fetch"）。修复：先注册 completer future，再通知。
//
//  B. LanguagePlaygroundPage._onCourseChanged 曾在 _availableModes 为空时
//     对每一次 notify 重新 _loadAvailability；叠加失败不缓存，形成
//     fetch → 失败 → notify → 再 fetch 的自激风暴。修复：加载进行中
//     （_availabilityLoading）不再重触发。
//
// _PageSim 与修复后的页面行为同构（含 loading 守卫）。killAfter 只是回归
// 时的安全熔断：若任一修复被回退，风暴会被限制在阈值内，测试以明确
// 断言失败而不是打满机器。

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/playground/playground_assembler.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/courses/course_loader.dart';

import '../../helpers/in_memory_course_db.dart';

/// 与 LanguagePlaygroundPage 的监听行为同构：notify 时若加载不在进行中
/// 且可用模式为空（= 上次未成功），重新跑一次 availability 加载。
class _PageSim {
  _PageSim(this._provider, {this.killAfter = 0});

  final CourseProvider _provider;

  /// >0 为安全熔断：availability 加载达到该次数后停止触发。修复生效时
  /// 远不会触到；若被触到，说明风暴回归（断言会先失败）。
  final int killAfter;

  int availabilityRuns = 0;
  bool availabilityLoading = false;
  bool _stopped = false;

  void onNotify() => _onCourseChanged();

  // 与 LanguagePlaygroundPage._onCourseChanged（修复后）同构。
  void _onCourseChanged({bool initial = false}) {
    if (_stopped) return;
    if (killAfter > 0 && availabilityRuns >= killAfter) {
      _stopped = true;
      return;
    }
    if (initial || (!availabilityLoading && _modesEmpty)) {
      unawaited(_loadAvailability().catchError((Object _) {}));
    }
  }

  bool _modesEmpty = true;

  // 与 _loadAvailability → PlaygroundContentSource.load(recent) →
  // _fromCurrentUnit → await ensureSectionLoaded 同构。
  Future<void> _loadAvailability() async {
    availabilityRuns++;
    availabilityLoading = true;
    try {
      final bundle = await PlaygroundContentSource(_provider).load(
        PlaygroundContentScope.recent,
      );
      _modesEmpty = PlaygroundAssembler.availableModes(bundle).isEmpty;
    } finally {
      availabilityLoading = false;
    }
  }
}

Future<void> _drainEventLoop() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('playground 卡死回归（重入去重 + 重触发守卫）', () {
    late CourseProvider provider;
    late String targetSectionId;

    setUp(() async {
      await seedInMemoryCourseDb();
      provider = CourseProvider();
      await provider.load();
      // 选一个 body 尚未加载的 section（load() 只预载第一个）。
      targetSectionId = provider.sections.last.id;
      expect(provider.sectionLoadState(targetSectionId),
          SectionLoadState.initial);
    });

    test('挂页面式监听后，一次切换 section 只 fetch 一次', () async {
      var startingFetchCount = 0;
      void capture(LogEvent e) {
        final m = e.message.toString();
        if (m.contains('ensureSectionLoaded') &&
            m.contains('starting fetch')) {
          startingFetchCount++;
        }
      }
      Logger.addLogListener(capture);

      final page = _PageSim(provider);
      provider.addListener(page.onNotify);

      // switchToSection 先 notify（选中变化）再 fire-and-forget ensure：
      // notify → 页面 _loadAvailability → ensureSectionLoaded；若去重
      // 失效，闭包内的同步 notifyListeners 会再触发一轮 fetch。
      await runZonedGuarded(() async {
        provider.switchToSection(targetSectionId);
        await _drainEventLoop();
      }, (Object _, StackTrace __) {});

      Logger.removeLogListener(capture);
      provider.removeListener(page.onNotify);

      expect(startingFetchCount, 1,
          reason: '重入去重失效会产生多行 "starting fetch"（用户日志症状）');
      expect(page.availabilityRuns, 1,
          reason: '加载进行中不应重复触发 availability 加载');
      expect(provider.sectionLoadState(targetSectionId),
          SectionLoadState.loaded);
      expect(provider.findSectionById(targetSectionId)!.units, isNotEmpty);
    });

    test('section 加载持续失败时，不会形成自激重试风暴', () async {
      // 空库：shells 已在 setUp 从种子库加载，但 body 查询
      // (CourseRepository.section) 命中空表 → ArgumentError；失败不缓存。
      CourseLoader.overrideDatabase(emptyInMemoryCourseDatabase);

      var fetchAttempts = 0;
      void capture(LogEvent e) {
        final m = e.message.toString();
        if (m.contains('ensureSectionLoaded') &&
            m.contains('starting fetch')) {
          fetchAttempts++;
        }
      }
      Logger.addLogListener(capture);

      final page = _PageSim(provider, killAfter: 50);
      provider.addListener(page.onNotify);

      await runZonedGuarded(() async {
        provider.switchToSection(targetSectionId);
        await _drainEventLoop();
      }, (Object _, StackTrace __) {});

      Logger.removeLogListener(capture);
      provider.removeListener(page.onNotify);

      expect(page.availabilityRuns, 1,
          reason: '失败通知不应重触发 availability（风暴则远超 1 或触熔断）');
      expect(fetchAttempts, 1, reason: '同一 section 只应 fetch 一次');
      expect(provider.sectionLoadState(targetSectionId),
          SectionLoadState.error);
    });
  });
}
