// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:chiclet/chiclet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/game_provider.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/routing/routing.gr.dart';
import 'package:words625/views/theme.dart';

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
    return ChicletAnimatedButton(
      width: MediaQuery.of(context).size.width * 0.9,
      onPressed: () => _handleGetStarted(context),
      buttonType: ChicletButtonTypes.roundedRectangle,
      backgroundColor: primaryColor,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'GET STARTED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 16),
          Icon(Icons.arrow_forward, color: Colors.white, size: 18),
        ],
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