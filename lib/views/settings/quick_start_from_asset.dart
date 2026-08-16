// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// 读取 `assets/quick_start.md` 并按 `## ` 切分章节,渲染为简单卡片列表。
///
/// 用作 About 页"使用指南"Tab 的内容来源。
class QuickStartFromAsset extends StatelessWidget {
  final String assetPath;

  /// 是否在顶部显示一个"使用指南"小标题(仅在独立展示时使用)。
  final bool showTitle;

  const QuickStartFromAsset({
    super.key,
    this.assetPath = 'assets/quick_start.md',
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: TurnaTheme.brandTeal,
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Text(
              AppStrings.quickStartLoadFallback,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          );
        }
        final sections = parseQuickStartMarkdown(snapshot.data!);
        if (sections.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Text(
              AppStrings.quickStartLoadFallback,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              _SectionHeader(text: AppStrings.aboutTabQuickStart),
              const SizedBox(height: 10),
            ],
            for (var i = 0; i < sections.length; i++) ...[
              _QuickStartSection(section: sections[i]),
              if (i < sections.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// 单节 quick start 内容。
class QuickStartSection {
  final String number;
  final String title;
  final List<String> paragraphs;

  const QuickStartSection({
    required this.number,
    required this.title,
    required this.paragraphs,
  });
}

/// 把 `assets/quick_start.md` 文本解析为 [QuickStartSection] 列表。
///
/// 解析规则:
/// - `#` / `##` 跳过(标题与分隔符)。
/// - `## N. TITLE` 视为新节;`N` 为编号,`TITLE` 为标题。
/// - 空行 / `---` 跳过。
/// - 段落:连续非空行组成一段,段内若有 `- ` 前缀则改为 bullet 列表。
/// - `>` 引用块:前缀剥离,作为段落。
List<QuickStartSection> parseQuickStartMarkdown(String markdown) {
  final sections = <QuickStartSection>[];
  String? currentNumber;
  String? currentTitle;
  final paragraphs = <String>[];
  final currentLines = <String>[];

  void flush() {
    if (currentNumber != null) {
      if (currentLines.isNotEmpty) {
        paragraphs.add(currentLines.join('\n'));
        currentLines.clear();
      }
      sections.add(
        QuickStartSection(
          number: currentNumber!,
          title: currentTitle ?? '',
          paragraphs: List.unmodifiable(paragraphs),
        ),
      );
    }
    currentNumber = null;
    currentTitle = null;
    paragraphs.clear();
  }

  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) {
      if (currentLines.isNotEmpty) {
        paragraphs.add(currentLines.join('\n'));
        currentLines.clear();
      }
      continue;
    }
    if (line.startsWith('---')) continue;
    if (line.startsWith('# ')) continue;
    if (line.startsWith('## ')) {
      flush();
      final header = line.substring(3).trim();
      final spaceIdx = header.indexOf(' ');
      if (spaceIdx >= 0) {
        currentNumber = header.substring(0, spaceIdx).trim();
        currentTitle = header.substring(spaceIdx + 1).trim();
      } else {
        currentNumber = header;
        currentTitle = '';
      }
      continue;
    }
    if (currentNumber == null) continue;
    final cleaned = line.startsWith('> ') ? line.substring(2) : line;
    currentLines.add(cleaned);
  }
  flush();
  return sections;
}

class _QuickStartSection extends StatelessWidget {
  final QuickStartSection section;

  const _QuickStartSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Text(
                  section.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTeal,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Short bar + title, matching the About page's `_SectionHeader` rhythm.
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}
