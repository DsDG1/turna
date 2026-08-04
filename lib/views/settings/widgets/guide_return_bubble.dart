// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/guide_return_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/settings/beginner_guide_page.dart';
import 'package:turna/views/theme.dart';

/// Root-level overlay that shows a dismissible "返回新手指南" chip after the
/// user jumps away from the beginner guide via 「去体验」.
///
/// Mount once above the navigator (e.g. [MaterialApp.router] builder).
class GuideReturnBubbleOverlay extends StatelessWidget {
  const GuideReturnBubbleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = getIt<GuideReturnController>();
    // Positioned MUST be the direct Stack child (this StatelessWidget is
    // transparent). ListenableBuilder must nest *inside* Positioned — otherwise
    // Flutter throws ParentDataWidget mismatch and paints a full red screen.
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 72,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.visible) return const SizedBox.shrink();
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          return Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              opacity: 1,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: _GuideReturnBubble(
                onReturn: () => _returnToGuide(context, controller),
                onDismiss: controller.dismiss,
              ),
            ),
          );
        },
      ),
    );
  }

  void _returnToGuide(
    BuildContext context,
    GuideReturnController controller,
  ) {
    final guidePopped = controller.guidePopped;
    controller.clear();

    if (guidePopped) {
      // Guide was closed for a tab jump — reopen from Settings.
      getIt<TabRouter>().switchTo(TabDestination.settings);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const BeginnerGuidePage(),
        ),
      );
      return;
    }

    // Guide is still under the experience route — pop once.
    Navigator.of(context).maybePop();
  }
}

class _GuideReturnBubble extends StatelessWidget {
  final VoidCallback onReturn;
  final VoidCallback onDismiss;

  const _GuideReturnBubble({
    required this.onReturn,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? TurnaTheme.brandNavy.withValues(alpha: 0.96)
        : TurnaTheme.brandTeal;
    const fg = Colors.white;

    return Material(
      color: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          boxShadow: TurnaTheme.softShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(999),
                ),
                onTap: onReturn,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 18, color: fg),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          AppStrings.beginnerGuideReturnBubble,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Vertical hairline between return and dismiss.
            Container(
              width: 1,
              height: 22,
              color: fg.withValues(alpha: 0.28),
            ),
            Tooltip(
              message: AppStrings.beginnerGuideReturnDismissTooltip,
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(999),
                ),
                onTap: onDismiss,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Icon(Icons.close_rounded, size: 18, color: fg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
