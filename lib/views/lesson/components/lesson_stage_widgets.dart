// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/course/reading_passage.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

class LessonStageBanner extends StatelessWidget {
  final String name;
  final Color accent;
  final IconData? icon;

  const LessonStageBanner({
    super.key,
    required this.name,
    required this.accent,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        // 深色下 0.04 的 accent 铺在纯黑上几乎不可见, 抬到 0.10 才读得出
        // "这是分区条, 不是内容".
        color: accent.withValues(alpha: isDark ? 0.10 : 0.05),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 17, color: accent)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 折叠态阅读卡: 只露 4 行 + "展开原文".
///
/// 之前是「外层 40% 视口高 + 卡内自带 SingleChildScrollView」—— 一屏里两个
/// 独立滚动区, 手势会抢方向, 而且原文常年吃掉 40% 的作答空间. 现在默认折叠,
/// 全文走全屏 sheet ([showReadingPassageSheet]), 题干区拿到完整视口.
class LessonReadingPassageCard extends StatelessWidget {
  final ReadingPassage passage;

  const LessonReadingPassageCard({super.key, required this.passage});

  @override
  Widget build(BuildContext context) {
    return _CollapsedPassage(
      title: passage.title,
      paragraphs: passage.paragraphs,
    );
  }
}

/// 旧格式 (纯文本) 的阅读材料, 折叠行为与 [LessonReadingPassageCard] 一致.
class LessonLegacyReadingPassage extends StatelessWidget {
  final String text;

  const LessonLegacyReadingPassage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return _CollapsedPassage(paragraphs: <String>[text]);
  }
}

class _CollapsedPassage extends StatelessWidget {
  final String? title;
  final List<String> paragraphs;

  const _CollapsedPassage({required this.paragraphs, this.title});

  @override
  Widget build(BuildContext context) {
    final body = paragraphs.join('\n\n');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 16,
                color: TurnaTheme.brandTeal,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.lessonTemplateReading,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (title != null && title!.isNotEmpty) ...[
            Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: TurnaTheme.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 4),
          _ExpandRow(
            onTap: () => showReadingPassageSheet(
              context,
              title: title,
              paragraphs: paragraphs,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandRow extends StatelessWidget {
  final VoidCallback onTap;

  const _ExpandRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppStrings.lessonReadingExpand,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.lessonReadingExpand,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: TurnaTheme.brandTeal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全屏阅读 sheet: 唯一可滚动的地方就是它, 页面本身不再嵌滚动.
Future<void> showReadingPassageSheet(
  BuildContext context, {
  String? title,
  required List<String> paragraphs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: TurnaTheme.textHint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null && title.isNotEmpty) ...[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            const SizedBox(height: 16),
          ],
          for (final paragraph in paragraphs) ...[
            Text(
              paragraph,
              style: TextStyle(
                fontSize: 16,
                height: 1.75,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
  );
}
