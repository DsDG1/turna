// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:words625/views/profile/widgets/widgets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AccountWidget(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        const SliverToBoxAdapter(child: Statistics()),
        const SliverToBoxAdapter(child: Achievements()),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}