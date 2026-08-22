// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/domain/achievements/achievement_unlock_result.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/profile/achievements/achievement_unlock_banner.dart';

/// Completion-page feedback consumer: watches the unified achievement
/// service and, once unseen live unlocks exist, drains a small batch into an
/// inline banner. Draining marks tiers as seen, so each unlock surfaces
/// exactly once (plan §7.5 / P5).
///
/// Mounted inside lesson / review completion screens — a page disposal can
/// never lose the queue because `seen` is persisted per tier id. Renders
/// nothing when no service is available (e.g. dialog unit tests).
class AchievementFeedbackBanner extends StatefulWidget {
  /// Optional "查看成就" navigation hook; when null the banner shows no
  /// action (e.g. inside dialogs that pop right after).
  final VoidCallback? onViewAll;

  const AchievementFeedbackBanner({super.key, this.onViewAll});

  @override
  State<AchievementFeedbackBanner> createState() =>
      _AchievementFeedbackBannerState();
}

class _AchievementFeedbackBannerState extends State<AchievementFeedbackBanner> {
  List<AchievementUnlockResult> _batch = const [];
  AchievementService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve once per dependency change: prefer the widget-tree provider,
    // fall back to the DI singleton, degrade to nothing otherwise.
    final resolved = _resolveService();
    if (!identical(resolved, _service)) {
      _service?.removeListener(_onServiceChanged);
      _service = resolved;
      _service?.addListener(_onServiceChanged);
      final service = resolved;
      if (service != null) _drain(service);
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    super.dispose();
  }

  AchievementService? _resolveService() {
    try {
      return context.read<AchievementService>();
    } catch (_) {
      // No provider above this node (dialog unit tests); try DI.
    }
    if (getIt.isRegistered<AchievementService>()) {
      try {
        return getIt<AchievementService>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _onServiceChanged() {
    if (!mounted) return;
    // New unlocks arriving while this page is visible (late evaluation
    // finishing after the completion UI rendered) get surfaced too.
    final service = _service;
    if (service != null && _batch.isEmpty) {
      _drain(service);
    }
  }

  Future<void> _drain(AchievementService service) async {
    if (!service.hasUnseenUnlocks) return;
    final batch = await service.takeFeedbackBatch();
    if (!mounted || batch.isEmpty) return;
    setState(() => _batch = batch);
  }

  @override
  Widget build(BuildContext context) {
    if (_batch.isEmpty) return const SizedBox.shrink();
    return AchievementUnlockBanner(
      unlocks: _batch,
      onViewAll: widget.onViewAll,
    );
  }
}
