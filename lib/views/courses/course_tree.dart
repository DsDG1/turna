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
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/sub_lesson_summary.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/courses/components/section_bottom_sheet.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/widgets/directory_rows.dart';

/// 课时行的复习注意标记（due = 该课有词待复习，weak = 有薄弱词）。
enum LessonAttention { none, due, weak }

String? lessonAttentionText(LessonAttention attention) => switch (attention) {
      LessonAttention.due => AppStrings.coursesLessonDueMeta,
      LessonAttention.weak => AppStrings.coursesLessonWeakMeta,
      LessonAttention.none => null,
    };

/// 学习页（课程树）——「湿地雾光」学习旅程版式（P1 定稿的紧凑稿）：
///
/// 1. **紧凑章节头**：两行可点击卡（图标井 + 章节名 + 元信息 + 细进度
///    条），点击打开章节切换底部弹层；随页滚动，不吸顶。
/// 2. **三层目录**：吸顶单元条（序号块 + 名 + k/n，展开的单元钉在顶部）
///    → 课时行（46，状态符号）→ 子课行（40，芦苇缩进线）。未展开的
///    单元只占一行摘要——目录再长也保持可扫读。
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

    return Selector<CourseProvider, _CourseSnapshot>(
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
            ? _ResumeBar(section: section)
            : null;

        return Column(
          children: [
            Expanded(child: viewport),
            if (resume != null) resume,
          ],
        );
      },
    );
  }

  Widget _buildSectionViewport(
    BuildContext context, {
    required _CourseSnapshot snapshot,
    required Section? section,
    required bool reduceMotion,
  }) {
    final Widget content = switch (snapshot.loadState) {
      SectionLoadState.initial || SectionLoadState.loading => const Center(
          child: _LoadingIndicator(),
        ),
      SectionLoadState.error => _buildErrorMessage(
          context,
          title: AppStrings.coursesCouldNotLoadSection,
          error: snapshot.error,
          onRetry: () =>
              context.read<CourseProvider>().reloadSection(section!.id),
        ),
      SectionLoadState.loaded when section == null || section.units.isEmpty =>
        const Center(child: _EmptyMessage()),
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
          child: _OfficialTreeUnavailableBanner(
            onRetry: () => context.read<CourseProvider>().reloadCourse(),
          ),
        ),
      // 紧凑章节头 + 细进度条：随页滚动，点击进章节切换弹层。
      SliverToBoxAdapter(child: _SectionHeadCard(section: section)),
    ];

    for (var u = 0; u < section.units.length; u++) {
      final unit = section.units[u];
      final expanded = expandedUnitId == unit.id;
      final retracting = !expanded &&
          _collapsingUnitKeys.contains(_unitKey(section.id, unit.id));
      final attached = expanded || retracting;

      // 展开的单元：吸顶单元条 + 旅程行；收起中的单元保留同样的结构，
      // 行高随揭示动画归零后再换成一行摘要。
      if (attached) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _UnitStripDelegate(
              sectionId: section.id,
              unit: unit,
              unitIndex: u + 1,
              dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
              weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
              expanded: expanded,
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
          context,
          section: section,
          unit: unit,
          progress: progress,
          status: status,
          reduceMotion: reduceMotion,
          nextUpNode: _nextUpNode(progress, unit),
          attached: true,
        ));
      } else {
        // 未展开单元：只占一行摘要。
        slivers.add(
          SliverToBoxAdapter(
            key: ValueKey<String>('unit-summary-${section.id}-${unit.id}'),
            child: _UnitStrip(
              unitIndex: u + 1,
              unit: unit,
              dueLessonCount: status.dueCountByUnit[unit.id] ?? 0,
              weakLessonCount: status.weakCountByUnit[unit.id] ?? 0,
              expanded: false,
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
  Widget _unitRowSliver(
    BuildContext context, {
    required Section section,
    required Unit unit,
    required ProgressProvider? progress,
    required _StatusProjection status,
    required bool reduceMotion,
    required ({String lessonId, String? subLessonId})? nextUpNode,
    required bool attached,
  }) {
    final items = <_TreeItem>[];
    final totalRows = unit.lessons.fold<int>(
      0,
      (sum, lesson) => sum + _lessonRowCount(lesson),
    );

    var rowIndex = 0;
    ({String lessonId, String? subLessonId})? previousNode;
    for (final lesson in unit.lessons) {
      final subs = _subLessonNodes(lesson);
      final attention = status.attentionForLesson(lesson.id);
      if (subs == null) {
        items.add(
          _LessonItem(
            sectionId: section.id,
            unit: unit,
            lesson: lesson,
            attention: attention,
            isLast: rowIndex == totalRows - 1,
            revealIndex: rowIndex,
            previousNode: previousNode,
            isNextUp: _isNode(nextUpNode, lesson.id, null),
          ),
        );
        previousNode = (lessonId: lesson.id, subLessonId: null);
        rowIndex++;
        continue;
      }

      items.add(
        _SubLessonGroupHeaderItem(
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
          _SubLessonItem(
            sectionId: section.id,
            unit: unit,
            lesson: lesson,
            sub: subs[s],
            subIndex: s,
            subCount: subs.length,
            isLast: rowIndex == totalRows - 1,
            revealIndex: rowIndex,
            isNextUp: _isNode(nextUpNode, lesson.id, subs[s].id),
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
              _LessonItem() => _buildLessonTile(item),
              _SubLessonGroupHeaderItem() => _buildGroupHeader(item),
              _SubLessonItem() => _buildSubLessonTile(item),
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

  Widget _buildLessonTile(_LessonItem item) {
    final lesson = item.lesson;

    return Selector<ProgressProvider,
        ({bool completed, bool previousCompleted})>(
      selector: (_, provider) => (
        completed: provider.isLessonCompleted(lesson.id),
        previousCompleted: item.previousNode != null &&
            _nodeCompleted(
              provider,
              item.previousNode!.lessonId,
              item.previousNode!.subLessonId,
            ),
      ),
      builder: (context, value, _) {
        final status = _nodeStatus(
          completed: value.completed,
          isNextUp: item.isNextUp,
          isFirst: item.previousNode == null,
          previousCompleted: value.previousCompleted,
        );
        // 复习注意态优先于「下一课」位置标记：待复习是行动信息，位置
        // 信息由状态环与底部继续条承担。
        final attentionText = lessonAttentionText(item.attention);
        final isNextUp = item.isNextUp && !value.completed;
        return DirectoryLessonRow(
          status: status,
          title: lesson.name,
          meta: attentionText ?? (isNextUp ? AppStrings.coursesNextLesson : null),
          metaEmphasized: attentionText != null || isNextUp,
          showDivider: !item.isLast,
          onTap: () => _navigateToLesson(context, lesson, null),
        );
      },
    );
  }

  Widget _buildGroupHeader(_SubLessonGroupHeaderItem item) {
    final lesson = item.lesson;
    final subIds = [for (final sub in item.subs) sub.id];

    return Selector<ProgressProvider, int>(
      selector: (_, provider) =>
          subIds.where((id) => _nodeCompleted(provider, lesson.id, id)).length,
      builder: (context, completedCount, _) => _SubLessonGroupRow(
        lesson: lesson,
        completedCount: completedCount,
        subCount: item.subs.length,
        attention: item.attention,
      ),
    );
  }

  Widget _buildSubLessonTile(_SubLessonItem item) {
    final lesson = item.lesson;

    return Selector<ProgressProvider,
        ({bool completed, bool previousCompleted})>(
      selector: (_, provider) => (
        completed: _nodeCompleted(provider, lesson.id, item.sub.id),
        previousCompleted: item.previousNode != null &&
            _nodeCompleted(
              provider,
              item.previousNode!.lessonId,
              item.previousNode!.subLessonId,
            ),
      ),
      builder: (context, value, _) {
        final status = _nodeStatus(
          completed: value.completed,
          isNextUp: item.isNextUp,
          isFirst: false,
          previousCompleted: value.previousCompleted,
        );
        // 子课行：芦苇缩进线由外层容器画，行本体走目录行族。
        return Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Color(0x6678C7B8),
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: AppSpacing.md + 2),
          child: DirectorySubLessonRow(
            status: status,
            title: item.sub.name,
            meta: item.isNextUp && !value.completed
                ? AppStrings.coursesNextLesson
                : null,
            onTap: () => _navigateToLesson(context, lesson, item.sub.id),
            showDivider: !item.isLast,
          ),
        );
      },
    );
  }

  /// 节点旅程状态：完成 / 当前（下一个）/ 可学 / 锁定。
  static DirectoryNodeStatus _nodeStatus({
    required bool completed,
    required bool isNextUp,
    required bool isFirst,
    required bool previousCompleted,
  }) {
    if (completed) return DirectoryNodeStatus.done;
    if (isNextUp) return DirectoryNodeStatus.current;
    if (isFirst || previousCompleted) return DirectoryNodeStatus.todo;
    return DirectoryNodeStatus.locked;
  }

  // --- 旅程节点辅助（ADR 0064）---

  /// 多子课的课返回其 L1 子课摘要；拆组门槛 ≥2 与播放侧
  /// `LessonViewModel._targetedSubLessonSession` 保持一致（1 节的课播放
  /// 本就是单段，不拆）。
  static List<SubLessonSummary>? _subLessonNodes(Lesson lesson) {
    final subs = lesson.subLessonSummaries;
    return subs.length >= 2 ? subs : null;
  }

  static int _lessonRowCount(Lesson lesson) {
    final subs = _subLessonNodes(lesson);
    return subs == null ? 1 : subs.length + 1;
  }

  static bool _isNode(
    ({String lessonId, String? subLessonId})? node,
    String lessonId,
    String? subLessonId,
  ) =>
      node != null &&
      node.lessonId == lessonId &&
      node.subLessonId == subLessonId;

  /// 单元内第一个未完成的可玩节点（节点粒度）。无 progress 时返回首
  /// 节点——与旧的「无进度从第一课开始」行为一致。
  static ({String lessonId, String? subLessonId})? _nextUpNode(
    ProgressProvider? progress,
    Unit unit,
  ) {
    for (final lesson in unit.lessons) {
      final subs = _subLessonNodes(lesson);
      if (subs == null) {
        if (progress == null || !_nodeCompleted(progress, lesson.id, null)) {
          return (lessonId: lesson.id, subLessonId: null);
        }
        continue;
      }
      for (final sub in subs) {
        if (progress == null || !_nodeCompleted(progress, lesson.id, sub.id)) {
          return (lessonId: lesson.id, subLessonId: sub.id);
        }
      }
    }
    return null;
  }

  /// 整个章节的第一个未完成节点（继续条的目标）。无 progress 时返回
  /// 首单元首节点。
  static ({Unit unit, Lesson lesson, SubLessonSummary? sub})?
      _sectionNextUpNode(ProgressProvider? progress, Section section) {
    for (final unit in section.units) {
      final node = _nextUpNode(progress, unit);
      if (node == null) continue;
      for (final lesson in unit.lessons) {
        if (lesson.id != node.lessonId) continue;
        SubLessonSummary? sub;
        if (node.subLessonId != null) {
          for (final candidate in lesson.subLessonSummaries) {
            if (candidate.id == node.subLessonId) sub = candidate;
          }
        }
        return (unit: unit, lesson: lesson, sub: sub);
      }
    }
    return null;
  }

  /// 节点完成态。整课完成（含早于子课节点追踪的旧记录）⇒ 其全部子课
  /// 节点视为完成；平面节点只看整课记录。
  static bool _nodeCompleted(
    ProgressProvider progress,
    String lessonId,
    String? subLessonId,
  ) {
    if (progress.isLessonCompleted(lessonId)) return true;
    return subLessonId != null &&
        progress.isSubLessonCompleted(lessonId, subLessonId);
  }

  /// 课程行的「帘式揭示」slot：[SizeTransition] 包住整行，行占位高度随
  /// 因子从 0 连续增长到自然高度；逐行交错由 [TurnaMotion.stagger] 封顶
  /// 起点，任意课数都在同一时长窗口内完成。
  ///
  /// 透明度因子比尺寸提前收尾（[TurnaMotion.stagger] 的 `span`）：部分
  /// 不透明期间每行每帧都要 saveLayer，把淡入压进揭示前段子窗口，动画
  /// 后段行达到完全不透明后直接绘制、不再离屏合成。
  Widget _buildRevealSlot(
    _TreeItem item, {
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

  _StatusProjection _resolveStatusProjection(
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

    final projection = _StatusProjection(
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

  static String _unitKey(String sectionId, String unitId) =>
      _journeyUnitKey(sectionId, unitId);

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

/// 紧凑章节头：图标井 + 章节名 + 元信息 + 细进度条；点击进章节切换。
class _SectionHeadCard extends StatelessWidget {
  const _SectionHeadCard({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    final colors = SectionVisuals.colorsFor(section.id);

    return Selector<ProgressProvider, double>(
      selector: (_, progress) {
        var total = 0;
        var completed = 0;
        for (final unit in section.units) {
          for (final lesson in unit.lessons) {
            total++;
            if (progress.isLessonCompleted(lesson.id)) completed++;
          }
        }
        return total == 0 ? 0 : completed / total;
      },
      builder: (context, progressValue, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          AppSpacing.sm - 2,
          AppSpacing.pageMargin,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showSectionBottomSheet(context),
                borderRadius: TurnaTheme.cardBorderRadius,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: TurnaTheme.flatPaperDecoration(
                    context,
                    borderRadius: TurnaTheme.cardBorderRadius,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius:
                              BorderRadius.circular(TurnaTheme.radiusMedium),
                        ),
                        child: Icon(
                          SectionVisuals.iconFor(section.id),
                          size: 18,
                          color: colors.foreground,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.sectionTitle(context)
                                  .copyWith(fontSize: 18, height: 1.2),
                            ),
                            if ((section.level ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SectionLevelLabel(section.level),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 1),
            // 细进度条：章节整体完成度。
            Semantics(
              label: AppStrings.coursesSectionProgressSemantic(
                (progressValue * 100).round(),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 3,
                  backgroundColor: TurnaTheme.dividerBg(context),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    TurnaTheme.brandTeal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 吸顶单元条的 SliverPersistentHeader 适配。
class _UnitStripDelegate extends SliverPersistentHeaderDelegate {
  _UnitStripDelegate({
    required this.sectionId,
    required this.unit,
    required this.unitIndex,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.onToggle,
  });

  final String sectionId;
  final Unit unit;
  final int unitIndex;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final VoidCallback onToggle;

  static const double height = 46;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _UnitStrip(
      unitIndex: unitIndex,
      unit: unit,
      dueLessonCount: dueLessonCount,
      weakLessonCount: weakLessonCount,
      expanded: expanded,
      onToggle: onToggle,
      pinned: true,
    );
  }

  @override
  bool shouldRebuild(covariant _UnitStripDelegate old) =>
      old.sectionId != sectionId ||
      old.unit != unit ||
      old.unitIndex != unitIndex ||
      old.expanded != expanded ||
      old.dueLessonCount != dueLessonCount ||
      old.weakLessonCount != weakLessonCount;
}

/// 单元条：序号块 + 名 + k/n + 注意点 + 展开指示。展开单元钉在目录
/// 顶部（[pinned] 底色画布色 + 底发丝线），未展开单元就是目录里的一行
/// 摘要。
class _UnitStrip extends StatelessWidget {
  const _UnitStrip({
    required this.unitIndex,
    required this.unit,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.onToggle,
    this.pinned = false,
  });

  final int unitIndex;
  final Unit unit;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final VoidCallback onToggle;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final hasAttention = dueLessonCount > 0 || weakLessonCount > 0;
    final attentionColor =
        dueLessonCount > 0 ? TurnaTheme.warning : TurnaTheme.brandSky;

    // 完成计数响应课级进度记录——目录里每个单元条的 k/n 都要跟着走，
    // 不能只在整树重建时算一遍。
    return Selector<ProgressProvider, int>(
      selector: (_, progress) => countCompletedLessons(progress, unit),
      builder: (context, completedCount, _) => Material(
        color: pinned ? TurnaTheme.scaffoldBg(context) : Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
            ),
          ),
          child: Semantics(
            // 单元条语义契约：名字 + k/n 进度 + 展开态 + 点按（屏幕阅读器
            // 靠它辨目录结构）。子树文字被排除，朗读稿只有这一份。
            label: '${unit.name}，$completedCount/${unit.lessons.length}',
            button: true,
            expanded: expanded,
            onTap: onToggle,
            excludeSemantics: true,
            child: InkWell(
              onTap: onToggle,
              child: SizedBox(
                height: _UnitStripDelegate.height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageMargin,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$unitIndex',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: TurnaTheme.brandTeal,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          unit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyText(context).copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (hasAttention) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: attentionColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '$completedCount/${unit.lessons.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: TurnaTheme.textSecondaryColor(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 多子课的课的组头行（ADR 0064）：课级归属与进度，不可点——进入与重玩
/// 都点子课行。
class _SubLessonGroupRow extends StatelessWidget {
  const _SubLessonGroupRow({
    required this.lesson,
    required this.completedCount,
    required this.subCount,
    required this.attention,
  });

  final Lesson lesson;
  final int completedCount;
  final int subCount;
  final LessonAttention attention;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              lesson.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyText(context).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
          ),
          if (attention != LessonAttention.none) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              lessonAttentionText(attention) ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: attention == LessonAttention.due
                    ? TurnaTheme.warning
                    : TurnaTheme.brandSky,
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$completedCount/$subCount',
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部常驻继续条：下一个可学节点 + 单一主行动。列表再长，继续学习
/// 始终可达（P1 紧凑稿评审确认）。
class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    return Selector<ProgressProvider,
        ({String lessonId, String? subLessonId, String name})?>(
      selector: (_, progress) {
        final next = _CourseTreeState._sectionNextUpNode(progress, section);
        if (next == null) return null;
        return (
          lessonId: next.lesson.id,
          subLessonId: next.sub?.id,
          name: next.sub?.name ?? next.lesson.name,
        );
      },
      builder: (context, next, _) {
        if (next == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
            top: AppSpacing.sm + 2,
            // 外层 HomePage 已把底部导航的 overlay 余量注入 MediaQuery。
            bottom: AppSpacing.xs + MediaQuery.paddingOf(context).bottom,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.router.push(
                NewLessonRoute(
                  lessonId: next.lessonId,
                  subLessonId: next.subLessonId,
                ),
              ),
              borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md - 1),
                decoration: BoxDecoration(
                  color: TurnaTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
                  border: Border.all(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.40),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: TurnaTheme.brandNavy.withValues(alpha: 0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: TurnaTheme.brandTeal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_right_alt_rounded,
                        size: 20,
                        color: TurnaTheme.textOnPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.coursesResumeCap,
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                              color: TurnaTheme.brandTeal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            next.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyText(context).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.router.push(CourseManagementRoute()),
            child: Text(AppStrings.courseManagementTitle),
          ),
        ],
      ),
    );
  }
}

class _OfficialTreeUnavailableBanner extends StatelessWidget {
  const _OfficialTreeUnavailableBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TurnaTheme.warningSurface(context),
          borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
          border: Border.all(color: TurnaTheme.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: TurnaTheme.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.coursesOfficialTreeUnavailable,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(AppStrings.commonRetry),
            ),
          ],
        ),
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

/// 单元内已完成课数（progress 缺席时为 0）。单元条与章节头共用。
int countCompletedLessons(ProgressProvider? progress, Unit unit) {
  if (progress == null) return 0;
  var completed = 0;
  for (final lesson in unit.lessons) {
    if (progress.isLessonCompleted(lesson.id)) completed++;
  }
  return completed;
}

/// 揭示控制器与旅程行共用的 section/unit 键：State 的静态包装与 item
/// 类（顶层）都从这里取。
String _journeyUnitKey(String sectionId, String unitId) => '$sectionId/$unitId';

sealed class _TreeItem {
  const _TreeItem();

  Key get key;

  /// 揭示动画控制器键（section/unit）。
  String get revealControllerKey;

  /// 揭示交错序号（单元内的旅程行序）。
  int get revealIndex;

  /// 揭示渐变键的稳定尾巴（平面课 = 课 id；沿用 `lesson-reveal-*` 键
  /// 契约，测试按它找 FadeTransition）。
  String get revealTag;
}

/// 旅程线上的可玩节点引用：平面课（subLessonId 为 null）或多子课组内
/// 的一节子课。
typedef _JourneyNode = ({String lessonId, String? subLessonId});

class _LessonItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final LessonAttention attention;
  final bool isLast;
  @override
  final int revealIndex;
  final bool isNextUp;

  /// 旅程线上紧邻的前一节点（跨组时为上一组最后一节子课），驱动解锁
  /// 判定；单元首行为 null。
  final _JourneyNode? previousNode;

  const _LessonItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.attention,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
    this.isNextUp = false,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}');

  @override
  String get revealControllerKey => _journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => lesson.id;
}

/// 多子课的课的组头行（ADR 0064）：课级归属标识，不可点——进入与重玩
/// 都点子课行。
class _SubLessonGroupHeaderItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final List<SubLessonSummary> subs;
  final LessonAttention attention;

  /// 恒为 false：组内必有子课行，组头永不收底。
  final bool isLast;
  @override
  final int revealIndex;
  final _JourneyNode? previousNode;

  const _SubLessonGroupHeaderItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.subs,
    required this.attention,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
  });

  @override
  Key get key => ValueKey<String>('lessongroup-$sectionId-${lesson.id}');

  @override
  String get revealControllerKey => _journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => 'group-${lesson.id}';
}

/// 一节子课的行：点击进入只玩这一节的独立会话（ADR 0064）。
class _SubLessonItem extends _TreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final SubLessonSummary sub;
  final int subIndex;
  final int subCount;
  final bool isLast;
  @override
  final int revealIndex;
  final bool isNextUp;
  final _JourneyNode? previousNode;

  const _SubLessonItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.sub,
    required this.subIndex,
    required this.subCount,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
    this.isNextUp = false,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}-${sub.id}');

  @override
  String get revealControllerKey => _journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => '${lesson.id}-${sub.id}';
}

class _StatusProjection {
  final Set<String> dueLessonIds;
  final Set<String> weakLessonIds;
  final Map<String, int> dueCountByUnit;
  final Map<String, int> weakCountByUnit;
  final bool officialTreeUnavailable;

  const _StatusProjection({
    required this.dueLessonIds,
    required this.weakLessonIds,
    required this.dueCountByUnit,
    required this.weakCountByUnit,
    this.officialTreeUnavailable = false,
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
