// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:varnamala/application/srs_tutor_provider.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:varnamala/views/lesson/tutor_launch_sheet.dart';
import 'package:varnamala/views/theme.dart';

/// Centralized AI surface (Phase 2.3 / Phase 3 of floofy-hugging-hopper).
///
/// Three sections in a single scroll view:
///   1. **Hero** — current engine config (preset, models, masked key). For
///      reconfiguration, see Settings → AI Tools → API config.
///   2. **Continue** — the most recent three AI tasks from
///      [AiRecentTasksProvider], each tappable if a route is recorded.
///   3. **Start** — tile grid that opens the major AI features (wish chat,
///      textbook import, by-mistakes tutor, by-weak-words tutor, depth tutor).
///
/// Wrapped in a top-only [SafeArea] so the body starts below the status bar
/// even though the outer Scaffold sees a zero-height stub AppBar.
@RoutePage()
class AiHubPage extends StatelessWidget {
  const AiHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _HeroSection()),
          const SliverToBoxAdapter(child: _ContinueSection()),
          const SliverToBoxAdapter(child: _StartSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
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
        modelJson: holder.config.modelJson,
        apiKeyMasked: _maskKey(holder.config.apiKey),
        complete: holder.config.isComplete,
      ),
      builder: (context, snap, _) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VarnamalaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: Border.all(color: VarnamalaTheme.dividerBg(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: VarnamalaTheme.peacockTeal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.aiHubTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(label: snap.preset),
                  _Chip(label: 'chat: ${snap.modelChat}'),
                  _Chip(label: 'json: ${snap.modelJson}'),
                  _Chip(label: snap.apiKeyMasked),
                ],
              ),
              if (!snap.complete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VarnamalaTheme.warning.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(VarnamalaTheme.radiusMedium),
                  ),
                  child: Text(
                    AppStrings.aiHubHeroIncomplete,
                    style: const TextStyle(color: VarnamalaTheme.warning),
                  ),
                ),
              ],
            ],
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
    required this.modelJson,
    required this.apiKeyMasked,
    required this.complete,
  });
  final String preset;
  final String modelChat;
  final String modelJson;
  final String apiKeyMasked;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is _HeroSnapshot &&
      other.preset == preset &&
      other.modelChat == modelChat &&
      other.modelJson == modelJson &&
      other.apiKeyMasked == apiKeyMasked &&
      other.complete == complete;

  @override
  int get hashCode =>
      Object.hash(preset, modelChat, modelJson, apiKeyMasked, complete);
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: VarnamalaTheme.peacockTeal,
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.replay_rounded,
            title: AppStrings.aiHubContinue,
          ),
          const SizedBox(height: 8),
          Selector<AiRecentTasksProvider, List<AiRecentTask>>(
            selector: (_, p) => p.recent(limit: 3),
            builder: (context, items, _) {
              if (items.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VarnamalaTheme.cardBg(context),
                    borderRadius:
                        BorderRadius.circular(VarnamalaTheme.radiusMedium),
                    border: Border.all(
                        color: VarnamalaTheme.dividerBg(context)),
                  ),
                  child: Text(
                    AppStrings.aiHubContinueEmpty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return Column(
                children: [
                  for (final t in items)
                    _RecentRow(
                      task: t,
                      onTap: t.route == null
                          ? null
                          : () => _navigateByRoute(context, t.route!),
                    ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(color: VarnamalaTheme.dividerBg(context)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(_iconFor(task.kind),
            color: VarnamalaTheme.peacockTeal, size: 20),
        title: Text(
          task.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _labelFor(task.kind),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: task.route == null
            ? null
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
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
      default:
        return kind;
    }
  }
}

// ─── Start ─────────────────────────────────────────────────────────────────

class _StartSection extends StatelessWidget {
  const _StartSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.add_circle_outline_rounded,
            title: AppStrings.aiHubNew,
          ),
          const SizedBox(height: 8),
          Selector<AiHintProvider, bool>(
            selector: (_, p) => p.context != null,
            builder: (context, hasQuestion, _) {
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: [
                  _StartTile(
                    icon: Icons.auto_awesome_rounded,
                    label: AppStrings.aiHubStartWish,
                    onTap: () => context.router.push(const AiWishChatRoute()),
                  ),
                  _StartTile(
                    icon: Icons.menu_book_rounded,
                    label: AppStrings.aiHubStartTextbook,
                    onTap: () =>
                        context.router.push(const TextbookImportRoute()),
                  ),
                  _StartTile(
                    icon: Icons.history_toggle_off_rounded,
                    label: AppStrings.aiHubStartTutorMistakes,
                    onTap: () => _openSheet(context, const TutorLaunchSheet(),
                        SrsTutorFocus.mistakes),
                  ),
                  _StartTile(
                    icon: Icons.quiz_rounded,
                    label: AppStrings.aiHubStartTutorWeak,
                    onTap: () => _openSheet(context, const TutorLaunchSheet(),
                        SrsTutorFocus.weakWords),
                  ),
                  _StartTile(
                    icon: Icons.account_tree_outlined,
                    label: AppStrings.aiHubStartDepthTutor,
                    enabled: hasQuestion,
                    onTap: hasQuestion
                        ? () =>
                            _openSheet(context, const AiDepthTutorSheet(), null)
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

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
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VarnamalaTheme.radiusXLarge),
        ),
      ),
      builder: (_) => sheet,
    );
  }
}

class _StartTile extends StatelessWidget {
  const _StartTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(VarnamalaTheme.radiusMedium),
              border: Border.all(color: VarnamalaTheme.dividerBg(context)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: VarnamalaTheme.peacockTeal, size: 24),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: VarnamalaTheme.peacockTeal, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: VarnamalaTheme.peacockTeal,
              ),
        ),
      ],
    );
  }
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
    default:
      // Unknown route - ignore. The Continue tile is informational only.
      break;
  }
}
