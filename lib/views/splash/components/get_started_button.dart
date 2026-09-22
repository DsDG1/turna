// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/app_startup.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/theme.dart';

/// Splash screen "Get Started" button.
class GetStartedButton extends StatefulWidget {
  final BuildContext context;
  const GetStartedButton(this.context, {super.key});

  @override
  State<GetStartedButton> createState() => _GetStartedButtonState();
}

class _GetStartedButtonState extends State<GetStartedButton> {
  bool _pendingNav = false;

  @override
  Widget build(BuildContext context) {
    var loaded = true;
    var bootFailed = false;
    try {
      final course = context.watch<CourseProvider>();
      loaded = course.isLoaded;
      bootFailed = course.bootFailed;
    } catch (_) {
      loaded = true;
    }
    if (_pendingNav && loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigate(context);
      });
    }
    final radius = BorderRadius.circular(16);
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: TurnaTheme.primaryCtaDecoration(borderRadius: radius),
          child: InkWell(
            onTap: bootFailed
                ? () => continueTurnaStartup(retrySeed: true)
                : loaded
                    ? () => _handleGetStarted(context)
                    : () => setState(() => _pendingNav = true),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!loaded && !bootFailed) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TurnaTheme.textOnPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    bootFailed
                        ? AppStrings.commonRetry
                        : AppStrings.splashGetStarted,
                    style: const TextStyle(
                      color: TurnaTheme.textOnPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.arrow_forward,
                      color: TurnaTheme.textOnPrimary, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGetStarted(BuildContext context) async {
    await _navigate(context);
  }

  Future<void> _navigate(BuildContext context) async {
    final gameProvider = getIt<GameProvider>();
    await gameProvider.ensureUserGameFields();
    if (!context.mounted) return;
    context.read<GameProvider>();
    await context.router.pushAndPopUntil(
      const HomeRoute(),
      predicate: (route) => false,
    );
  }
}
