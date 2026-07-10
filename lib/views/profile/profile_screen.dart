// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/profile/widgets/learning_stats.dart';
import 'package:varnamala/views/profile/widgets/widgets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AccountWidget(),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(child: Statistics()),
        SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(child: LearningStats()),
        SliverToBoxAdapter(child: Achievements()),
        SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}