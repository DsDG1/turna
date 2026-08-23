// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/content_authoring_moved_page.dart';

/// 内容创作退场 tombstone（Plan 3 §19.4）。
///
/// 移动端不再执行 AI 愿望课程生成；旧路由/最近任务/深链进入这里时展示
/// GUI 平台迁移说明，而不是继续提供创作功能。原实现保留在 git 历史，
/// 创作草稿数据不做任何删除。
@RoutePage()
class AiWishChatPage extends StatelessWidget {
  const AiWishChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.settingsDesignCourseAiTitle)),
      body: const ContentAuthoringMovedBody(),
    );
  }
}
