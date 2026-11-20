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
import 'package:turna/core/motion.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/courses/components/course_tree_models.dart';
import 'package:turna/views/courses/components/course_tree_rows.dart';
import 'package:turna/views/widgets/turna_geometry.dart';

export 'package:turna/views/courses/components/course_tree_models.dart'
    show LessonAttention, lessonAttentionText, countCompletedLessons;

/// 学习页（课程树）——「湿地雾光」学习旅程版式（P1 定稿的紧凑稿）：
///
/// 1. **轻量章节进度带**：几何图标 + 章节名 + 元信息 + 细进度条，
///    点击打开章节切换底部弹层；随页滚动，不吸顶。
/// 2. **三层目录**：吸顶单元条（序号块 + 名 + k/n，展开的单元钉在顶部）
///    → 课时行（46，状态符号）→ 子课行（40，芦苇缩进线）。未展开的
///    单元以留白分隔的一行摘要呈现——目录再长也保持可扫读。
/// 3. **底部常驻继续条**：列表再长，「继续学习」与当前位置始终可达。
///
/// 数据管线不变：章节懒加载、due/weak 投影、每节独立的手风琴状态、
/// 帘式揭示动画、PageStorage 滚动位置全部保留。行族走 P2 的
/// [DirectoryLessonRow] / [DirectorySubLessonRow]（行不是卡：排版 + 发丝线）。
class CourseTree extends StatefulWidget {
  const CourseTree({super.key});

  @override
  State<CourseTree> createState() => _CourseTreeState();
}

class _CourseTreeState extends State<CourseTree> with TickerProviderStateMixin {
  /// Defensive section loads already scheduled for the next frame.
  final Set<String> _scheduledEnsure = {};

  /// Accordion state is kept per section, so changing sections does not make
  /// the learner lose the place they were working from.
  final Map<String, String?> _expandedUnitBySection = {};
  final Set<String> _userToggledSections = {};
  final Map<String, GlobalKey> _unitHeaderKeys = {};

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
  CourseTreeStatusProjection? _projectionCache;
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

    return Selector<CourseProvider, CourseTreeSnapshot>(
      selector: (_, provider) => CourseTreeSnapshot.from(provider),
      shouldRebuild: CourseTreeSnapshot.shouldRebuild,
      builder: (context, snapshot, _) {
        if (!snapshot.hasSections) {
          if (snapshot.isLoaded) {
            return CourseTreeErrorMessage(
              title: AppStrings.coursesCouldNotLoadCourse,
              error: AppStrings.coursesNoSectionsFound,
              onRetry: () => context.read<CourseProvider>().reloadCourse(),
            );
          }
          return const Center(child: CourseTreeLoadingIndicator());
        }

        final currentId = snapshot.currentSectionId;
        if (currentId != null &&
            snapshot.loadState == SectionLoadState.initial) {
          _scheduleEnsureSection(context.read<CourseProvider>(), currentId);
        }

        final section = snapshot.section;

        final viewport = _buildSectionViewport(
          context,
          snapshot: snapshot,
          section: section,
          reduceMotion: reduceMotion,
        );

        // 底部常驻继续条：只在目录真正可用时出现（加载 / 错误 / 空章节
        // 不占位）。
        final resume = (snapshot.loadState == SectionLoadState.loaded &&
                section != null &&
                section.units.isNotEmpty)
            ? CourseTreeResumeBar(section: section)
            : null;

        // 页级主视觉位（R02）：半圆拱从底缘升起。
        //
        // 只包一层「视口」而不是整列——继续条本身是不透明纸面，包进去
        // 就会把拱的直径线压到条下面，半圆又退化成土丘。
        //
        // 能看见它的只有「列表收尾 → 继续条」那条带，以及单元少时那片
        // 空白：旅程行是不透明纸面（ADR 0065），会把拱整个盖住。这恰好
        // 也决定了用法——它是地面的构图，不是背景纹理。
        final archedViewport = TurnaGeometryBackdrop(
          kind: TurnaGeometryKind.arch,
          alignment: Alignment.bottomCenter,
          size: (MediaQuery.sizeOf(context).width * 1.05).clamp(260.0, 480.0),
          intensity: 0.8,
          muted: section != null && _expandedUnitBySection[section.id] != null,
          child: viewport,
        );

        return Column(
          children: [
            Expanded(child: archedViewport),
            if (resume != null) resume,
          ],
        );
      },
    );
  }

  Widget _buildSectionViewport(
    BuildContext context, {
    required CourseTreeSnapshot snapshot,
    required Section? section,
    required bool reduceMotion,
  }) {
    final Widget content = switch (snapshot.loadState) {
      SectionLoadState.initial || SectionLoadState.loading => const Center(
          child: CourseTreeLoadingIndicator(),
        ),
      SectionLoadState.error => CourseTreeErrorMessage(
          title: AppStrings.coursesCouldNotLoadSection,
          error: snapshot.error,
          onRetry: () =>
              context.read<CourseProvider>().reloadSection(section!.id),
        ),
      SectionLoadState.loaded when section == null || section.units.isEmpty =>
        const Center(child: CourseTreeEmptyMessage()),
      SectionLoadState.loaded => _buildSectionScrollView(
          context,
          section: section!,
          reduceMotion: reduceMotion,
        ),
    };

    if (reduceMotion || section == null) return content;

    return AnimatedSwitcher(
      duration: TurnaMotion.smooth,
      switchInCurve: TurnaMotion.easeOut,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey<String>('section-viewport-${section.id}'),
        child: content,
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

  CustomScrollView _buildSectionScrollView(
    BuildContext context, {
    required Section section,
    required bool reduceMotion,
  }) {
    final status = _resolveStatusProjection(context, section);
    _ensureNextUpExpanded(context, section);
    final expandedUnitId = _expandedUnitBySection[section.id];

    ProgressProvider? progress;
    try {
      progress = context.read<ProgressProvider>();
    } catch (_) {
      // Optional dependency: without progress the tree simply starts at the
      // first lesson instead of the next uncompleted one.
    }

    final slivers = <Widget>[
      if (status.officialTreeUnavailable)
        SliverToBoxAdapter(
          child: CourseTreeOfficialUnavailableBanner(
            onRetry: () => context.read<CourseProvider>().reloadCourse(),
          ),
        ),
      // 轻量章节进度带：随页滚动，点击进章节切换弹层。
      SliverToBoxAdapter(child: CourseTreeSectionHeadBand(section: section)),
    ];

    for (var u = 0; u < section.units.length; u++) {
      final unit = section.units[u];
      final expanded = expandedUnitId == unit.id;
      final retracting = !expanded &&
          _collapsingUnitKeys.contains(journeyUnitKey(section.id, unit.id));
      final attached = expanded || retracting;

      // 展开的单元：吸顶单元条 + 旅程行；收起中的单元保留同样的结构，
      // 行高随揭示动画归零后再换成一行摘要。
      if (attached) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: CourseTreeUnitStripDelegate(
              sectionId: section.id,
              unit: unit,
              unitIndex: u + 1,
              dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
              weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
              expanded: expanded,
              reduceMotion: reduceMotion,
              headerKey: _unitHeaderKeys.putIfAbsent(
                journeyUnitKey(section.id, unit.id),
                GlobalKey.new,
              ),
              onToggle: () => _toggleUnit(
                sectionId: section.id,
                unitId: unit.id,
                expanded: expanded,
                reduceMotion: reduceMotion,
              ),
            ),
          ),
        );
        slivers.add(_unitRowSliver(
          section: section,
          unit: unit,
          progress: progress,
          status: status,
          reduceMotion: reduceMotion,
          nextUpNode: courseTreeNextUpNode(progress, unit),
        ));
      } else {
        // 未展开单元：只占一行摘要。
        slivers.add(
          SliverToBoxAdapter(
            key: ValueKey<String>('unit-summary-${section.id}-${unit.id}'),
            child: CourseTreeUnitStrip(
              key: _unitHeaderKeys.putIfAbsent(
                journeyUnitKey(section.id, unit.id),
                GlobalKey.new,
              ),
              unitIndex: u + 1,
              unit: unit,
              dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
              weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
              expanded: false,
              reduceMotion: reduceMotion,
              onToggle: () => _toggleUnit(
                sectionId: section.id,
                unitId: unit.id,
                expanded: false,
                reduceMotion: reduceMotion,
              ),
            ),
          ),
        );
      }
    }

    return CustomScrollView(
      key: PageStorageKey<String>('course-tree-${section.id}'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        ...slivers,
        // 目录底部：安全区 + 底部继续条的余量（继续条在滚动视图外）。
        SliverToBoxAdapter(
          child: SizedBox(
            height: 24 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }

  /// 一个展开单元的旅程行 Sliver：按「可玩节点」扁平化（ADR 0064），多
  /// 子课的课拆成组头行 + 每子课一行；帘式揭示保留。
  Widget _unitRowSliver({
    required Section section,
    required Unit unit,
    required ProgressProvider? progress,
    required CourseTreeStatusProjection status,
    required bool reduceMotion,
    required JourneyNode? nextUpNode,
  }) {
    final items = <CourseTreeItem>[];
    final totalRows = unit.lessons.fold<int>(
      0,
      (sum, lesson) => sum + courseTreeLessonRowCount(lesson),
    );

    var rowIndex = 0;
    JourneyNode? previousNode;
    for (final lesson in unit.lessons) {
      final subs = courseTreeSubLessonNodes(lesson);
      final attention = status.attentionForLesson(lesson.id);
      if (subs == null) {
        items.add(
          CourseTreeLessonItem(
            sectionId: section.id,
            unit: unit,
            lesson: lesson,
            attention: attention,
            isLast: rowIndex == totalRows - 1,
            revealIndex: rowIndex,
            previousNode: previousNode,
            isNextUp: courseTreeIsNode(nextUpNode, lesson.id, null),
          ),
        );
        previousNode = (lessonId: lesson.id, subLessonId: null);
        rowIndex++;
        continue;
      }

      items.add(
        CourseTreeSubLessonGroupHeaderItem(
          sectionId: section.id,
          unit: unit,
          lesson: lesson,
          subs: subs,
          attention: attention,
          isLast: false,
          revealIndex: rowIndex,
          previousNode: previousNode,
        ),
      );
      rowIndex++;
      previousNode = (lessonId: lesson.id, subLessonId: null);
      for (var s = 0; s < subs.length; s++) {
        items.add(
          CourseTreeSubLessonItem(
            sectionId: section.id,
            unit: unit,
            lesson: lesson,
            sub: subs[s],
            subIndex: s,
            subCount: subs.length,
            isLast: rowIndex == totalRows - 1,
            revealIndex: rowIndex,
            isNextUp: courseTreeIsNode(nextUpNode, lesson.id, subs[s].id),
            previousNode: previousNode,
          ),
        );
        previousNode = (lessonId: lesson.id, subLessonId: subs[s].id);
        rowIndex++;
      }
    }

    final indexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++) items[i].key: i,
    };

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageMargin),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            final Widget tile = switch (item) {
              CourseTreeLessonItem() => CourseTreeLessonTile(
                  item: item,
                  onNavigate: _navigateToLesson,
                ),
              CourseTreeSubLessonGroupHeaderItem() =>
                CourseTreeGroupHeaderTile(item: item),
              CourseTreeSubLessonItem() => CourseTreeSubLessonTile(
                  item: item,
                  onNavigate: _navigateToLesson,
                ),
            };
            if (!reduceMotion) {
              return _buildRevealSlot(item, tile: tile);
            }
            return KeyedSubtree(key: item.key, child: tile);
          },
          childCount: items.length,
          findChildIndexCallback: (key) => indexByKey[key],
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  /// 课程行的「帘式揭示」slot：[SizeTransition] 包住整行，行占位高度随
  /// 因子从 0 连续增长到自然高度；逐行交错由 [TurnaMotion.stagger] 封顶
  /// 起点，任意课数都在同一时长窗口内完成。
  ///
  /// 透明度因子比尺寸提前收尾（[TurnaMotion.stagger] 的 `span`）：部分
  /// 不透明期间每行每帧都要 saveLayer，把淡入压进揭示前段子窗口，动画
  /// 后段行达到完全不透明后直接绘制、不再离屏合成。
  Widget _buildRevealSlot(
    CourseTreeItem item, {
    required Widget tile,
  }) {
    final reveal = _revealByUnit[item.revealControllerKey];
    if (reveal == null) {
      return KeyedSubtree(key: item.key, child: tile);
    }
    final sizeFactor = reveal.drive(
      CurveTween(curve: TurnaMotion.stagger(item.revealIndex)),
    );
    final opacityFactor = reveal.drive(
      CurveTween(
        curve: TurnaMotion.stagger(item.revealIndex, span: 0.6),
      ),
    );
    return SizeTransition(
      key: item.key,
      sizeFactor: sizeFactor,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        key: ValueKey<String>('lesson-reveal-${item.revealTag}'),
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
    );
  }

  CourseTreeStatusProjection _resolveStatusProjection(
    BuildContext context,
    Section section,
  ) {
    Set<String> dueWordIds = const {};
    List<MistakeEntry> mistakeEntries = const [];
    Set<String> weakWordIds = const {};
    final dueLessonIds = <String>{};
    final weakLessonIds = <String>{};
    var officialTreeUnavailable = false;

    try {
      // select 必须每次 build 都执行以保住 provider 依赖注册，随后才允许
      // 走缓存短路。
      dueWordIds = context.select((SrsProvider p) => p.dueWordIdSet);
      mistakeEntries = context.select((MistakeProvider p) => p.entries);
      officialTreeUnavailable =
          context.select((CourseProvider p) => p.officialTreeLoadError != null);

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

    final projection = CourseTreeStatusProjection(
      dueLessonIds: dueLessonIds,
      weakLessonIds: weakLessonIds,
      dueCountByUnit: dueCountByUnit,
      weakCountByUnit: weakCountByUnit,
      officialTreeUnavailable: officialTreeUnavailable,
    );
    _projectionCache = projection;
    _projectionSection = section;
    _projectionDueWords = dueWordIds;
    _projectionMistakeEntries = mistakeEntries;
    return projection;
  }

  AnimationController _revealFor(String sectionId, String unitId) {
    final key = journeyUnitKey(sectionId, unitId);
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

  void _ensureNextUpExpanded(BuildContext context, Section section) {
    if (_userToggledSections.contains(section.id)) return;
    if (_expandedUnitBySection.containsKey(section.id)) return;
    String? nextUnitId;
    try {
      final progress = context.read<ProgressProvider>();
      final anyCompleted = section.units.any(
        (unit) =>
            unit.lessons.any((lesson) => progress.isLessonCompleted(lesson.id)),
      );
      if (!anyCompleted) return;
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          if (!progress.isLessonCompleted(lesson.id)) {
            nextUnitId = unit.id;
            break;
          }
        }
        if (nextUnitId != null) break;
      }
    } catch (_) {
      // Optional dependency: without progress the tree starts collapsed.
      return;
    }
    if (nextUnitId != null) {
      _expandedUnitBySection[section.id] = nextUnitId;
    }
  }

  void _toggleUnit({
    required String sectionId,
    required String unitId,
    required bool expanded,
    required bool reduceMotion,
  }) {
    final key = journeyUnitKey(sectionId, unitId);

    void retract(String id) {
      if (reduceMotion) {
        _revealFor(sectionId, id).value = 0;
      } else {
        _collapsingUnitKeys.add(journeyUnitKey(sectionId, id));
        _revealFor(sectionId, id).reverse();
      }
    }

    setState(() {
      _userToggledSections.add(sectionId);
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

    if (!expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _expandedUnitBySection[sectionId] != unitId) return;
        final headerContext = _unitHeaderKeys[key]?.currentContext;
        if (headerContext == null || !headerContext.mounted) return;
        Scrollable.ensureVisible(
          headerContext,
          duration: TurnaMotion.scaled(TurnaMotion.smooth, reduceMotion),
          curve: TurnaMotion.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });
    }
  }

  void _navigateToLesson(
    BuildContext tileContext,
    Lesson lesson,
    String? subLessonId,
  ) {
    // 原生默认路由转场进入课程页（平台自适应，全局统一策略）。子课
    // 节点带 subLessonId 进入单子课会话（ADR 0064）。
    tileContext.router.push(
      NewLessonRoute(lessonId: lesson.id, subLessonId: subLessonId),
    );
  }
}
