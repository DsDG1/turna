// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/courses/components/lesson_tile.dart';
import 'package:turna/views/courses/components/unit_card.dart';
import 'package:turna/views/home/components/ambient_backdrop.dart';
import 'package:turna/views/home/motion/turna_motion.dart';
import 'package:turna/views/theme.dart';
import 'components/section_switcher.dart';

/// 学习页（课程树）——「湿地晨光」重构后的滚动结构：
///
/// 1. 吸顶变形头（章节卡 ↔ 悬浮条，滚动擦拭变形），是页内「一镜到底」
///    的起点；
/// 2. 单元卡列表（展开时内嵌课程旅程面：旅程线 + 课程瓦片，帘式逐行
///    揭示；收起反向收回，切换单元时收/展双动画并发）。
///
/// 数据管线不变：章节懒加载、due/weak 投影、每节独立的手风琴状态、
/// PageStorage 滚动位置全部保留。
class CourseTree extends StatefulWidget {
  const CourseTree({super.key});

  @override
  State<CourseTree> createState() => _CourseTreeState();
}

class _CourseTreeState extends State<CourseTree>
    with TickerProviderStateMixin {
  /// Defensive section loads already scheduled for the next frame.
  final Set<String> _scheduledEnsure = {};

  /// Accordion state is kept per section, so changing sections does not make
  /// the learner lose the place they were working from.
  final Map<String, String?> _expandedUnitBySection = {};

  /// 每个「section/unit」一把揭示控制器：目标单元 forward、收起单元
  /// reverse，两把同时跑即手风琴切换的并发双动画。控制器常驻本表、
  /// 不在中途 dispose——section 切换的 AnimatedSwitcher 淡出期间旧子树
  /// 仍持有派生动画的监听，提前释放会触发 dispose-while-listened
  /// assert；随 State dispose 统一释放。
  final Map<String, AnimationController> _revealByUnit = {};

  /// 正在收回、课程行仍保留在列表中的单元键。控制器归零后行才移除
  /// （此时行高已为 0，移除不产生视觉跳变）。
  final Set<String> _collapsingUnitKeys = {};

  /// 状态投影缓存：due/weak 聚合是 O(全部待复习词)，且只取决于三个
  /// 输入——section、due 词集、错题列表。三者均为实例稳定来源（内容
  /// 变化才产生新实例：SrsProvider.dueWordIdSet / MistakeProvider.entries
  /// 的内部缓存 getter；CourseProvider 重载时更换 section 实例），因此
  /// 用 identity 三元组判失效。展开手风琴等与投影无关的重建直接复用。
  _StatusProjection? _projectionCache;
  Section? _projectionSection;
  Set<String>? _projectionDueWords;
  List<MistakeEntry>? _projectionMistakeEntries;

  @override
  void dispose() {
    for (final controller in _revealByUnit.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        context.select<AccessibilityProvider, bool>((p) => p.reducedMotion);

    return AmbientBackdrop(
      reduceMotion: reduceMotion,
      child: Selector<CourseProvider, _CourseSnapshot>(
        selector: (_, provider) => _CourseSnapshot.from(provider),
        shouldRebuild: _CourseSnapshot.shouldRebuild,
        builder: (context, snapshot, _) {
          if (!snapshot.hasSections) {
            if (snapshot.isLoaded) {
              return _buildErrorMessage(
                context,
                title: AppStrings.coursesCouldNotLoadCourse,
                error: AppStrings.coursesNoSectionsFound,
                onRetry: () => context.read<CourseProvider>().reloadCourse(),
              );
            }
            return const Center(child: _LoadingIndicator());
          }

          final currentId = snapshot.currentSectionId;
          if (currentId != null &&
              snapshot.loadState == SectionLoadState.initial) {
            _scheduleEnsureSection(context.read<CourseProvider>(), currentId);
          }

          final section = snapshot.section;

          final scrollView = _buildSectionScrollView(
            context,
            snapshot: snapshot,
            section: section,
            reduceMotion: reduceMotion,
          );

          if (reduceMotion) return scrollView;

          return AnimatedSwitcher(
            duration: TurnaMotion.smooth,
            switchInCurve: TurnaMotion.easeOut,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey<String>('section-viewport-${section?.id}'),
              child: scrollView,
            ),
          );
        },
      ),
    );
  }

  void _scheduleEnsureSection(CourseProvider courseState, String id) {
    if (_scheduledEnsure.contains(id)) return;
    _scheduledEnsure.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      courseState.ensureSectionLoaded(id).whenComplete(() {
        _scheduledEnsure.remove(id);
      });
    });
  }

  Widget _buildSectionScrollView(
    BuildContext context, {
    required _CourseSnapshot snapshot,
    required Section? section,
    required bool reduceMotion,
  }) {
    final bodySlivers = switch (snapshot.loadState) {
      SectionLoadState.initial || SectionLoadState.loading => <Widget>[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _LoadingIndicator(),
          ),
        ],
      SectionLoadState.error => <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildErrorMessage(
              context,
              title: AppStrings.coursesCouldNotLoadSection,
              error: snapshot.error,
              onRetry: () =>
                  context.read<CourseProvider>().reloadSection(section!.id),
            ),
          ),
        ],
      SectionLoadState.loaded when section == null || section.units.isEmpty =>
        <Widget>[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyMessage(),
          ),
        ],
      SectionLoadState.loaded => _buildLoadedSlivers(
          context,
          section: section!,
          reduceMotion: reduceMotion,
        ),
    };

    return CustomScrollView(
      key: PageStorageKey<String>('course-tree-${section?.id}'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 吸顶章节头：页首为完整章节卡，滚动时擦拭收缩为悬浮条。
        if (section != null)
          SliverPersistentHeader(
            pinned: true,
            delegate: SectionSwitcherHeaderDelegate(section: section),
          ),
        ...bodySlivers,
      ],
    );
  }

  List<Widget> _buildLoadedSlivers(
    BuildContext context, {
    required Section section,
    required bool reduceMotion,
  }) {
    final status = _resolveStatusProjection(context, section);
    final expandedUnitId = _expandedUnitBySection[section.id];

    // 单元头 + 展开单元的课程行交替铺开为 Sliver 列表行：课程行经
    // [LessonRowShell] 与单元卡头逐行拼合成一张整卡，同时保留懒加载
    // （百课单元不全量构建）。收起中的单元行也保留在列表里，直到揭示
    // 动画归零后再移除。
    final items = <_TreeItem>[];
    for (final unit in section.units) {
      final expanded = expandedUnitId == unit.id;
      final retracting = !expanded &&
          _collapsingUnitKeys.contains(_unitKey(section.id, unit.id));
      items.add(
        _UnitHeaderItem(
          sectionId: section.id,
          unit: unit,
          dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
          weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
          expanded: expanded,
          retainsLessonRows: expanded || retracting,
        ),
      );

      if (expanded || retracting) {
        String? nextUpLessonId;
        try {
          final progress = context.read<ProgressProvider>();
          for (final lesson in unit.lessons) {
            if (!progress.isLessonCompleted(lesson.id)) {
              nextUpLessonId = lesson.id;
              break;
            }
          }
        } catch (_) {}

        for (var i = 0; i < unit.lessons.length; i++) {
          final lesson = unit.lessons[i];
          items.add(
            _LessonItem(
              sectionId: section.id,
              unit: unit,
              lesson: lesson,
              attention: status.attentionForLesson(lesson.id),
              isLast: i == unit.lessons.length - 1,
              indexInUnit: i,
              isNextUp: lesson.id == nextUpLessonId,
            ),
          );
        }
      }
    }

    final indexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++) items[i].key: i,
    };

    return [
      SliverPadding(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              final (top, bottom) = switch (item) {
                _UnitHeaderItem(retainsLessonRows: final attached) => (
                    6.0,
                    attached ? 0.0 : 6.0
                  ),
                _LessonItem(isLast: final isLast) => (0.0, isLast ? 6.0 : 0.0),
              };

              final child = switch (item) {
                _UnitHeaderItem(
                  sectionId: final sectionId,
                  unit: final unit,
                  dueLessonCount: final dueCount,
                  weakLessonCount: final weakCount,
                  expanded: final expanded,
                ) =>
                  _buildUnitCard(
                    context,
                    sectionId: sectionId,
                    unit: unit,
                    dueCount: dueCount,
                    weakCount: weakCount,
                    expanded: expanded,
                    reduceMotion: reduceMotion,
                  ),
                _LessonItem() => _buildLessonTile(item),
              };

              final padding = EdgeInsets.fromLTRB(12, top, 12, bottom);
              if (item is _LessonItem && !reduceMotion) {
                return _buildRevealSlot(item, padding: padding, tile: child);
              }
              return Padding(
                key: item.key,
                padding: padding,
                child: child,
              );
            },
            childCount: items.length,
            findChildIndexCallback: (key) => indexByKey[key],
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  Widget _buildUnitCard(
    BuildContext context, {
    required String sectionId,
    required Unit unit,
    required int dueCount,
    required int weakCount,
    required bool expanded,
    required bool reduceMotion,
  }) {
    return Selector<ProgressProvider, int>(
      selector: (_, progress) {
        var completed = 0;
        for (final lesson in unit.lessons) {
          if (progress.isLessonCompleted(lesson.id)) completed++;
        }
        return completed;
      },
      builder: (context, completedCount, _) => UnitCard(
        unit: unit,
        completedCount: completedCount,
        dueLessonCount: dueCount,
        weakLessonCount: weakCount,
        expanded: expanded,
        reduceMotion: reduceMotion,
        onHeaderTap: () => _toggleUnit(
          sectionId: sectionId,
          unitId: unit.id,
          expanded: expanded,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }

  Widget _buildLessonTile(_LessonItem item) {
    final lesson = item.lesson;
    final previousLessonId = item.indexInUnit > 0
        ? item.unit.lessons[item.indexInUnit - 1].id
        : null;

    return Selector<ProgressProvider,
        ({bool completed, bool perfect, bool previousCompleted})>(
      selector: (_, progress) => (
        completed: progress.isLessonCompleted(lesson.id),
        perfect: progress.isLessonPerfect(lesson.id),
        previousCompleted:
            previousLessonId != null && progress.isLessonCompleted(previousLessonId),
      ),
      builder: (context, value, _) => LessonRowShell(
        isFirst: item.indexInUnit == 0,
        isLast: item.isLast,
        tile: LessonTile(
          lesson: lesson,
          isCompleted: value.completed,
          isPerfect: value.perfect,
          isNextUp: item.isNextUp && !value.completed,
          attention: item.attention,
          isFirst: item.indexInUnit == 0,
          isLast: item.isLast,
          previousCompleted: value.previousCompleted,
          onTap: (tileContext) => _navigateToLesson(tileContext, lesson),
        ),
      ),
    );
  }

  /// 课程行的「帘式揭示」slot：[SizeTransition] 包住整行（含边距），行
  /// 占位高度随因子从 0 连续增长到自然高度，下方单元卡由布局推动平滑
  /// 下移；行内容保持自然尺寸，仅被裁剪揭示。逐行交错由
  /// [TurnaMotion.stagger] 封顶起点，任意课数都在同一时长窗口内完成。
  ///
  /// 透明度因子比尺寸提前收尾（[TurnaMotion.stagger] 的 `span`）：部分
  /// 不透明期间每行每帧都要 saveLayer，把淡入压进揭示前段子窗口，动画
  /// 后段行达到完全不透明后直接绘制、不再离屏合成。
  Widget _buildRevealSlot(
    _LessonItem item, {
    required EdgeInsets padding,
    required Widget tile,
  }) {
    final reveal = _revealByUnit[_unitKey(item.sectionId, item.unit.id)];
    if (reveal == null) {
      return Padding(key: item.key, padding: padding, child: tile);
    }
    final sizeFactor = reveal.drive(
      CurveTween(curve: TurnaMotion.stagger(item.indexInUnit)),
    );
    final opacityFactor = reveal.drive(
      CurveTween(
        curve: TurnaMotion.stagger(item.indexInUnit, span: 0.6),
      ),
    );
    return SizeTransition(
      key: item.key,
      sizeFactor: sizeFactor,
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: padding,
        child: FadeTransition(
          key: ValueKey<String>('lesson-reveal-${item.lesson.id}'),
          opacity: opacityFactor,
          child: AnimatedBuilder(
            animation: sizeFactor,
            builder: (context, child) => ExcludeSemantics(
              // 揭示未完成（含收回途中）的行不进入语义树。
              excluding: sizeFactor.value < 1,
              child: child,
            ),
            child: tile,
          ),
        ),
      ),
    );
  }

  _StatusProjection _resolveStatusProjection(
    BuildContext context,
    Section section,
  ) {
    Set<String> dueWordIds = const {};
    List<MistakeEntry> mistakeEntries = const [];
    Set<String> weakWordIds = const {};
    final dueLessonIds = <String>{};
    final weakLessonIds = <String>{};

    try {
      // select 必须每次 build 都执行以保住 provider 依赖注册，随后才允许
      // 走缓存短路。
      dueWordIds = context.select((SrsProvider p) => p.dueWordIdSet);
      mistakeEntries = context.select((MistakeProvider p) => p.entries);

      final cached = _projectionCache;
      if (cached != null &&
          identical(_projectionSection, section) &&
          identical(_projectionDueWords, dueWordIds) &&
          identical(_projectionMistakeEntries, mistakeEntries)) {
        return cached;
      }

      weakWordIds = WeakWordQuizAssembler.aggregateWeakWords(mistakeEntries)
          .map((word) => word.wordId)
          .toSet();

      if (getIt.isRegistered<LessonLinkStore>()) {
        final store = getIt<LessonLinkStore>();
        for (final wordId in dueWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) dueLessonIds.add(link.lessonId);
        }
        for (final wordId in weakWordIds) {
          final link = store.linkFor(wordId);
          if (link != null) weakLessonIds.add(link.lessonId);
        }
      }
    } catch (_) {
      // Lightweight widget tests and recovery surfaces may intentionally omit
      // review providers. The course remains usable without attention badges.
    }

    final lessonToUnit = <String, String>{};
    for (final unit in section.units) {
      for (final lesson in unit.lessons) {
        lessonToUnit[lesson.id] = unit.id;
      }
    }

    final dueCountByUnit = <String, int>{};
    final weakCountByUnit = <String, int>{};
    for (final lessonId in dueLessonIds) {
      final unitId = lessonToUnit[lessonId];
      if (unitId != null) {
        dueCountByUnit.update(unitId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    for (final lessonId in weakLessonIds) {
      final unitId = lessonToUnit[lessonId];
      if (unitId != null) {
        weakCountByUnit.update(unitId, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final projection = _StatusProjection(
      dueLessonIds: dueLessonIds,
      weakLessonIds: weakLessonIds,
      dueCountByUnit: dueCountByUnit,
      weakCountByUnit: weakCountByUnit,
    );
    _projectionCache = projection;
    _projectionSection = section;
    _projectionDueWords = dueWordIds;
    _projectionMistakeEntries = mistakeEntries;
    return projection;
  }

  static String _unitKey(String sectionId, String unitId) =>
      '$sectionId/$unitId';

  AnimationController _revealFor(String sectionId, String unitId) {
    final key = _unitKey(sectionId, unitId);
    return _revealByUnit.putIfAbsent(key, () {
      final controller = AnimationController(
        vsync: this,
        duration: TurnaMotion.base,
      );
      controller.addStatusListener((status) {
        // reverse() 归零以 dismissed 收尾：行高此时已为 0，下一帧移除
        // 不产生视觉跳变。forward 完成是 completed，与此路径无关。
        if (status != AnimationStatus.dismissed) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _collapsingUnitKeys.remove(key));
        });
      });
      return controller;
    });
  }

  void _toggleUnit({
    required String sectionId,
    required String unitId,
    required bool expanded,
    required bool reduceMotion,
  }) {
    final key = _unitKey(sectionId, unitId);

    void retract(String id) {
      if (reduceMotion) {
        _revealFor(sectionId, id).value = 0;
      } else {
        _collapsingUnitKeys.add(_unitKey(sectionId, id));
        _revealFor(sectionId, id).reverse();
      }
    }

    setState(() {
      if (expanded) {
        _expandedUnitBySection[sectionId] = null;
        retract(unitId);
        return;
      }

      final previousUnitId = _expandedUnitBySection[sectionId];
      if (previousUnitId != null && previousUnitId != unitId) {
        retract(previousUnitId);
      }
      _expandedUnitBySection[sectionId] = unitId;
      _collapsingUnitKeys.remove(key);

      final reveal = _revealFor(sectionId, unitId);
      if (reduceMotion) {
        reveal.value = 1;
      } else if (reveal.isAnimating) {
        // 收回途中重开：从当前收回处接续展开，避免跳变。
        reveal.forward();
      } else {
        reveal.forward(from: 0);
      }
    });
  }

  void _navigateToLesson(BuildContext tileContext, Lesson lesson) {
    // 原生默认路由转场进入课程页（平台自适应，全局统一策略）。
    tileContext.router.push(NewLessonRoute(lessonId: lesson.id));
  }

  Widget _buildErrorMessage(
    BuildContext context, {
    required String title,
    required Object? error,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: TurnaTheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 64,
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.coursesNoUnitsAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseSnapshot {
  final bool hasSections;
  final bool isLoaded;
  final String? currentSectionId;
  final Section? section;
  final SectionLoadState loadState;
  final Object? error;

  const _CourseSnapshot({
    required this.hasSections,
    required this.isLoaded,
    required this.currentSectionId,
    required this.section,
    required this.loadState,
    required this.error,
  });

  factory _CourseSnapshot.from(CourseProvider provider) {
    final currentSectionId = provider.currentSectionId;
    final loadState = currentSectionId == null
        ? SectionLoadState.initial
        : provider.sectionLoadState(currentSectionId);
    return _CourseSnapshot(
      hasSections: provider.sections.isNotEmpty,
      isLoaded: provider.isLoaded,
      currentSectionId: currentSectionId,
      section: provider.currentSection,
      loadState: loadState,
      error: currentSectionId == null
          ? null
          : provider.sectionLoadError(currentSectionId),
    );
  }

  static bool shouldRebuild(
    _CourseSnapshot previous,
    _CourseSnapshot next,
  ) =>
      previous.hasSections != next.hasSections ||
      previous.isLoaded != next.isLoaded ||
      previous.currentSectionId != next.currentSectionId ||
      !identical(previous.section, next.section) ||
      previous.loadState != next.loadState ||
      previous.error != next.error;
}

sealed class _TreeItem {
  const _TreeItem();

  Key get key;
}

class _UnitHeaderItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;

  /// 下方是否还挂着课程行（展开中，或收起动画仍在保留行）。决定卡头
  /// 的底缘边距：有行时为 0 以保持拼卡，行全部移除后恢复分隔。
  final bool retainsLessonRows;

  const _UnitHeaderItem({
    required this.sectionId,
    required this.unit,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.retainsLessonRows,
  });

  @override
  Key get key => ValueKey<String>('unit-$sectionId-${unit.id}');
}

/// 课程项不再直接渲染为列表行——它们被注入所属单元卡的「旅程面」，
/// 仅保留在 items 列表里以维持 findChildIndexCallback 的键稳定性。
class _LessonItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final LessonAttention attention;
  final bool isLast;
  final int indexInUnit;
  final bool isNextUp;

  const _LessonItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.attention,
    required this.isLast,
    this.indexInUnit = 0,
    this.isNextUp = false,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}');
}

class _StatusProjection {
  final Set<String> dueLessonIds;
  final Set<String> weakLessonIds;
  final Map<String, int> dueCountByUnit;
  final Map<String, int> weakCountByUnit;

  const _StatusProjection({
    required this.dueLessonIds,
    required this.weakLessonIds,
    required this.dueCountByUnit,
    required this.weakCountByUnit,
  });

  LessonAttention attentionForLesson(String lessonId) {
    if (dueLessonIds.contains(lessonId)) return LessonAttention.due;
    if (weakLessonIds.contains(lessonId)) return LessonAttention.weak;
    return LessonAttention.none;
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              TurnaTheme.brandTeal.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.coursesLoadingCourses,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
