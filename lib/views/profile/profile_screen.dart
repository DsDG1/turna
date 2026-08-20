// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/home/components/profile_app_bar.dart';
import 'package:turna/views/profile/widgets/learning_stats.dart';
import 'package:turna/views/profile/widgets/widgets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AccountWidget(
              onShare: () => ProfileAppBar.openShareSheet(context),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: Statistics()),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: ProfileQuickActions()),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        const SliverToBoxAdapter(child: LearningStats()),
        const SliverToBoxAdapter(child: Achievements()),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}
