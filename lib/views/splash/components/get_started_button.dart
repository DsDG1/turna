// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

/// Splash screen "Get Started" button.
///
/// In offline mode, tapping the button initializes the local user state via
/// [GameProvider.ensureUserGameFields] and navigates straight to the home
/// route. No authentication is required.
class GetStartedButton extends StatelessWidget {
  final BuildContext context;
  const GetStartedButton(this.context, {super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: TurnaTheme.primaryCtaDecoration(borderRadius: radius),
          child: InkWell(
            onTap: () => _handleGetStarted(context),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.splashGetStarted,
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
    final gameProvider = getIt<GameProvider>();
    await gameProvider.ensureUserGameFields();

    if (!context.mounted) return;
    context.read<GameProvider>(); // ensure provider is wired into tree

    await context.router.pushAndPopUntil(
      const HomeRoute(),
      predicate: (route) => false,
    );
  }
}
