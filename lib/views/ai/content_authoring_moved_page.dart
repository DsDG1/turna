// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/application/settings/external_link_registry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// 内容创作退场 tombstone（Plan 3 §19.4）。
///
/// 移动端不再提供课程生成、教材导入和结构编辑；创作统一走 GUI 平台，
/// 移动端继续负责学习与复习。旧入口/最近任务/深链落在这里时：
///   * GUI 地址已配置 → 可打开（ExternalLinkRegistry 的 https 校验 + 失败
///     复制兜底）；
///   * GUI 地址未配置 → 按钮禁用并明确说明，不构造任何猜测性链接。
/// 用户已产生的创作草稿不会被删除（数据保留决策见计划 §19.4）。
class ContentAuthoringMovedBody extends StatelessWidget {
  const ContentAuthoringMovedBody({super.key});

  @override
  Widget build(BuildContext context) {
    const registry = ExternalLinkRegistry();
    final gui = registry.describe(ExternalLinkId.guiPlatform);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.move_up_rounded,
                size: 44, color: TurnaTheme.brandTeal),
            const SizedBox(height: 14),
            Text(
              AppStrings.authoringMovedTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.authoringMovedBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: gui.enabled
                        ? () =>
                            openExternalLink(context, ExternalLinkId.guiPlatform)
                        : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(AppStrings.authoringMovedOpenGui),
                  ),
                ),
              ],
            ),
            if (!gui.enabled) ...[
              const SizedBox(height: 8),
              Text(
                AppStrings.authoringMovedGuiUnconfigured,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                      height: 1.4,
                    ),
              ),
            ] else
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: gui.uri.toString()),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppStrings.externalLinkCopyAddress)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text(AppStrings.externalLinkCopyAddress),
              ),
            const SizedBox(height: 12),
            Text(
              AppStrings.authoringMovedDraftsKept,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
