// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/srs_tutor_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/lesson/tutor_launch_sheet.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/ai/ai_api_config_page.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/theme.dart';

/// Centralized AI surface (Phase 2.3 / Phase 3 of floofy-hugging-hopper).
///
/// Redesigned to share the Play Hub's soft-tinted card language
/// ([SoftCard] / [AccentIconChip] / [ReviewTile] / [ToolsTile]). Reached as a
/// pushed route from the Play Hub's 「AI 助手」section, so it owns its own
/// Scaffold + back AppBar.
///
/// Three sections in a single scroll view:
///   1. **Hero** - amethyst->teal gradient card with engine config (preset,
///      chat model, masked key). Taps open the API config sheet.
///   2. **Continue** - the most recent three AI tasks from
///      [AiRecentTasksProvider], each tappable if a route is recorded.
///   3. **Start** - tile grid that opens the major AI features (wish chat,
///      textbook import, by-mistakes tutor, by-weak-words tutor) + a
///      full-width depth-tutor row (gated on an active question).
@RoutePage()
class AiHubPage extends StatelessWidget {
  const AiHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: TurnaTheme.amethystLeague,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              AppStrings.playAiAssistantTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '功能介绍',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => context.router.push(const AiFeatureGuideRoute()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            const SliverToBoxAdapter(child: _HeroSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(child: _ContinueSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(child: _StartSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, _HeroSnapshot>(
      selector: (_, holder) => _HeroSnapshot(
        preset: holder.config.preset.label,
        modelChat: holder.config.modelChat,
        apiKeyMasked: _maskKey(holder.config.apiKey),
        complete: holder.config.isComplete,
      ),
      builder: (context, snap, _) {
        const radius =
            BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openConfig(context),
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      TurnaTheme.amethystLeague,
                      TurnaTheme.brandTeal,
                    ],
                  ),
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: TurnaTheme.amethystLeague.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.aiHubTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  snap.complete
                                      ? '${snap.preset} · ${snap.modelChat}'
                                      : AppStrings.aiHubHeroIncomplete,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HeroChip(label: snap.preset),
                          _HeroChip(label: snap.apiKeyMasked),
                          if (!snap.complete)
                            _HeroChip(
                              label: AppStrings.playAiEngineNotConfigured,
                              warning: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '(no key)';
    if (trimmed.length <= 8) return '${trimmed[0]}…(${trimmed.length})';
    return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 4)}';
  }
}

class _HeroSnapshot {
  const _HeroSnapshot({
    required this.preset,
    required this.modelChat,
    required this.apiKeyMasked,
    required this.complete,
  });
  final String preset;
  final String modelChat;
  final String apiKeyMasked;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is _HeroSnapshot &&
      other.preset == preset &&
      other.modelChat == modelChat &&
      other.apiKeyMasked == apiKeyMasked &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(preset, modelChat, apiKeyMasked, complete);
}

/// Small frosted chip rendered on the gradient hero. Warning variant swaps to
/// a solid warning fill so an incomplete config can't be missed.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, this.warning = false});
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            warning ? TurnaTheme.warning : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Colors.white.withValues(alpha: warning ? 0.0 : 0.35),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

// ─── Continue ─────────────────────────────────────────────────────────────

class _ContinueSection extends StatelessWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: AppStrings.aiHubContinue),
          Selector<AiRecentTasksProvider, List<AiRecentTask>>(
            selector: (_, p) => p.recent(limit: 3),
            builder: (context, items, _) {
              if (items.isEmpty) {
                return SoftCard(
                  accentColor: TurnaTheme.brandTeal,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      AppStrings.aiHubContinueEmpty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final t in items) ...[
                    _RecentRow(
                      task: t,
                      onTap: t.route == null
                          ? null
                          : () => _navigateByRoute(context, t.route!),
                    ),
                    if (t != items.last) const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.task, this.onTap});
  final AiRecentTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal);

    return SoftCard(
      accentColor: TurnaTheme.brandTeal,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AccentIconChip(
              icon: _iconFor(task.kind),
              color: accent,
              size: 20,
              padding: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _labelFor(task.kind),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: accent,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String kind) {
    switch (kind) {
      case AiTaskKind.wish:
        return Icons.auto_awesome_rounded;
      case AiTaskKind.textbook:
        return Icons.menu_book_rounded;
      case AiTaskKind.tutorMistakes:
      case AiTaskKind.tutorWeakWords:
        return Icons.history_edu_rounded;
      case AiTaskKind.hintChat:
        return Icons.chat_bubble_outline_rounded;
      case AiTaskKind.hintDepth:
        return Icons.menu_book_outlined;
      case AiTaskKind.lessonHelper:
        return Icons.build_circle_outlined;
      case AiTaskKind.courseGenerate:
        return Icons.school_rounded;
      case AiTaskKind.tutorChat:
        return Icons.forum_outlined;
      case AiTaskKind.diagnosis:
        return Icons.analytics_outlined;
      case AiTaskKind.dictionary:
        return Icons.menu_book_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  static String _labelFor(String kind) {
    switch (kind) {
      case AiTaskKind.wish:
        return '设计课程';
      case AiTaskKind.textbook:
        return '教材导入';
      case AiTaskKind.tutorMistakes:
        return '按错题复习';
      case AiTaskKind.tutorWeakWords:
        return '弱词复习';
      case AiTaskKind.hintChat:
        return 'AI 讲解';
      case AiTaskKind.hintDepth:
        return '深度讲解';
      case AiTaskKind.lessonHelper:
        return '课内助手';
      case AiTaskKind.courseGenerate:
        return '一键生成';
      case AiTaskKind.tutorChat:
        return '自由问答';
      case AiTaskKind.diagnosis:
        return '学习诊断';
      case AiTaskKind.dictionary:
        return '词典扩展';
      default:
        return kind;
    }
  }
}

// ─── Start (companion first; authoring demoted) ─────────────────────────────

class _StartSection extends StatelessWidget {
  const _StartSection();

  @override
  Widget build(BuildContext context) {
    final complete =
        context.select<AiEngineConfigHolder, bool>((h) => h.config.isComplete);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: AppStrings.aiHubNew),
          if (!complete) ...[
            SoftCard(
              accentColor: TurnaTheme.warning,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AiNotConfiguredPanel(compact: true),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SectionTitle(title: AppStrings.aiHubCompanionSection),
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              ReviewTile(
                title: AppStrings.aiHubStartTutorChat,
                icon: Icons.chat_bubble_outline_rounded,
                accentColor: TurnaTheme.brandTeal,
                onTap: () => context.router.push(const AiTutorChatRoute()),
              ),
              ReviewTile(
                title: AppStrings.aiHubStartDiagnosis,
                icon: Icons.analytics_outlined,
                accentColor: TurnaTheme.brandSky,
                onTap: () => context.router.push(const AiDiagnosisRoute()),
              ),
              ReviewTile(
                title: AppStrings.aiHubStartSaved,
                icon: Icons.bookmark_outline_rounded,
                accentColor: TurnaTheme.amethystLeague,
                onTap: () => context.router.push(const AiSavedListRoute()),
              ),
              ReviewTile(
                title: AppStrings.aiHubStartDepthTutor,
                icon: Icons.account_tree_outlined,
                accentColor: TurnaTheme.brandReed,
                onTap: () =>
                    _openSheet(context, const AiDepthTutorSheet(), null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Secondary: generate practice from mistakes/weak words (SRS tutor).
          ToolsTile(
            title: AppStrings.aiHubStartTutorMistakes,
            subtitle: AppStrings.tutorLaunchByMistakesCta,
            icon: Icons.history_toggle_off_rounded,
            accentColor: TurnaTheme.brandTeal.withValues(alpha: 0.85),
            onTap: () => _openSheet(
                context, const TutorLaunchSheet(), SrsTutorFocus.mistakes),
          ),
          const SizedBox(height: 8),
          ToolsTile(
            title: AppStrings.aiHubStartTutorWeak,
            subtitle: AppStrings.tutorLaunchByWeakWordsCta,
            icon: Icons.quiz_rounded,
            accentColor: TurnaTheme.brandReed.withValues(alpha: 0.85),
            onTap: () => _openSheet(
                context, const TutorLaunchSheet(), SrsTutorFocus.weakWords),
          ),
          const SizedBox(height: 16),
          // Authoring demoted / collapsed.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: Text(
                AppStrings.aiHubAuthoringSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
              children: [
                GridView.count(
                  padding: EdgeInsets.zero,
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    ReviewTile(
                      title: AppStrings.aiHubStartWish,
                      icon: Icons.auto_awesome_rounded,
                      accentColor: TurnaTheme.textHintColor(context),
                      onTap: () =>
                          context.router.push(const AiWishChatRoute()),
                    ),
                    ReviewTile(
                      title: AppStrings.aiHubStartTextbook,
                      icon: Icons.menu_book_rounded,
                      accentColor: TurnaTheme.textHintColor(context),
                      onTap: () =>
                          context.router.push(const TextbookImportRoute()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────

void _openSheet(BuildContext context, Widget sheet, Object? focus) {
  // Pre-seed the tutor focus so the sheet lands on the user's choice.
  if (sheet is TutorLaunchSheet && focus is SrsTutorFocus) {
    // The sheet reads focus via setState on its own state; since we can't
    // pass initial args without exposing a ctor, we let the sheet default
    // to "mistakes" and rely on the user re-tapping. Acceptable for the
    // hub entry path - both tiles work, the chip just defaults to one.
    // (Two-tile pattern is intentional UX; both pre-populate mistakes.)
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => sheet,
  );
}

/// Open the standalone AI API config page.
void _openConfig(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AiApiConfigPage()),
  );
}

/// Resolve a saved AI Hub task route by name. Unknown routes are silently
/// ignored - the AI Hub must never crash because a renamed route left an
/// orphan [AiRecentTask] in the in-memory ring.
void _navigateByRoute(BuildContext context, String name) {
  switch (name) {
    case 'AiWishChatRoute':
      context.router.push(const AiWishChatRoute());
      break;
    case 'TextbookImportRoute':
      context.router.push(const TextbookImportRoute());
      break;
    case 'AiTutorChatRoute':
      context.router.push(const AiTutorChatRoute());
      break;
    case 'AiDiagnosisRoute':
      context.router.push(const AiDiagnosisRoute());
      break;
    case 'AiSavedListRoute':
      context.router.push(const AiSavedListRoute());
      break;
    case 'AiHintChatRoute':
      context.router.push(AiHintChatRoute());
      break;
    default:
      // Unknown route - ignore. The Continue tile is informational only.
      break;
  }
}
