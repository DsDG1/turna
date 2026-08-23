// Flutter imports:
import 'package:flutter/material.dart';

/// Shared scroll body for every routed Settings category page.
///
/// The [pageStorageKey] is stable per route so a page's scroll offset is
/// restorable across route rebuilds — scroll preservation no longer depends
/// on keeping visited pages secretly mounted (the old `_visited` + Offstage
/// pseudo-routing this replaces).
class SettingsCategoryBody extends StatelessWidget {
  const SettingsCategoryBody({
    super.key,
    required this.pageStorageKey,
    required this.child,
  });

  final String pageStorageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: PageStorageKey<String>(pageStorageKey),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: child,
    );
  }
}
