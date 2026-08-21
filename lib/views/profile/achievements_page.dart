// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/widgets/achievements.dart';
import 'package:turna/views/theme.dart';

/// Full-page achievements list (profile page links here with an unlocked
/// count summary instead of inlining the list).
@RoutePage()
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.profileAchievementsTitle),
        backgroundColor: TurnaTheme.scaffoldBg(context),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 8,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: const Achievements(showAll: true),
      ),
    );
  }
}
