// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

/// Splash screen "Get Started" button.
///
/// In offline mode, tapping the button initializes the local user state via
/// [GameProvider.ensureUserGameFields] and navigates straight to the home
/// route. No authentication is required.
class GetStartedButton extends StatelessWidget {
  final BuildContext context;
  const GetStartedButton(this.context, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9,
      child: ElevatedButton(
        onPressed: () => _handleGetStarted(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: VarnamalaTheme.textOnPrimary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppStrings.splashGetStarted,
              style: const TextStyle(
                color: VarnamalaTheme.textOnPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward, color: VarnamalaTheme.textOnPrimary, size: 18),
          ],
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