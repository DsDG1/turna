// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:countup/countup.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/game_provider.dart';
import 'package:words625/views/theme.dart';
import 'package:words625/views/widgets/gems_display.dart';
import 'package:words625/views/widgets/hearts_display.dart';
import 'package:words625/views/widgets/loader.dart';
import 'package:words625/views/widgets/patreon_button.dart';

class StatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StatAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 60,
      title: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScoreCard(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            Streak(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            GemsDisplay(),
          ],
        ),
      ),
      actions: const [
        PatreonButton(),
        HeartsDisplay(),
      ],
    );
  }
}

class Streak extends StatelessWidget {
  const Streak({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFF9500), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserStreakStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return Countup(
                begin: 0,
                end: snapshot.data?.toDouble() ?? 0,
                duration: const Duration(milliseconds: 1000),
                separator: ',',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFFFF9500),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserScoreStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return Countup(
                begin: 0,
                end: snapshot.data?.toDouble() ?? 0,
                duration: const Duration(milliseconds: 1000),
                separator: ',',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFFE5A800),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}