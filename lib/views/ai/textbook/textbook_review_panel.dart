// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/textbook/textbook_import_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Tabbed knowledge review: words / expressions / grammar with search + edit.
class TextbookReviewPanel extends StatefulWidget {
  final TextbookImportProvider provider;

  const TextbookReviewPanel({super.key, required this.provider});

  @override
  State<TextbookReviewPanel> createState() => _TextbookReviewPanelState();
}

class _TextbookReviewPanelState extends State<TextbookReviewPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.aiTextbookReviewKnowledge,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _CountChip(
              label: AppStrings.aiTextbookTabWords,
              count: p.totalWordCount,
            ),
            const SizedBox(width: 6),
            _CountChip(
              label: AppStrings.aiTextbookTabExpressions,
              count: p.totalExpressionCount,
            ),
            const SizedBox(width: 6),
            _CountChip(
              label: AppStrings.aiTextbookTabGrammar,
              count: p.totalGrammarCount,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: AppStrings.aiTextbookReviewSearchHint,
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onChanged: p.setReviewQuery,
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabs,
          labelColor: TurnaTheme.peacockTeal,
          unselectedLabelColor: TurnaTheme.textHintColor(context),
          indicatorColor: TurnaTheme.peacockTeal,
          tabs: [
            Tab(text: '${AppStrings.aiTextbookTabWords} (${p.totalWordCount})'),
            Tab(
                text:
                    '${AppStrings.aiTextbookTabExpressions} (${p.totalExpressionCount})'),
            Tab(
                text:
                    '${AppStrings.aiTextbookTabGrammar} (${p.totalGrammarCount})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ResourceList(provider: p, kind: ResourceKind.word),
              _ResourceList(provider: p, kind: ResourceKind.expression),
              _ResourceList(provider: p, kind: ResourceKind.grammar),
            ],
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;

  const _CountChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.peacockTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Text(
        '$label $count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: TurnaTheme.peacockTeal,
        ),
      ),
    );
  }
}

class _ResourceList extends StatelessWidget {
  final TextbookImportProvider provider;
  final ResourceKind kind;

  const _ResourceList({required this.provider, required this.kind});

  @override
  Widget build(BuildContext context) {
    final items = provider.flattenedResources(kind);
    if (items.isEmpty) {
      return Center(
        child: Text(
          AppStrings.aiTextbookReviewEmpty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: TurnaTheme.dividerBg(context),
      ),
      itemBuilder: (context, i) {
        final item = items[i];
        final chapterTitle = provider.results[item.chapterIndex].chapter.title;
        return ListTile(
          dense: true,
          title: Text(
            item.primary.isEmpty ? '—' : item.primary,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              if (item.secondary.isNotEmpty) item.secondary,
              chapterTitle,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: AppStrings.aiTextbookDeleteResource,
            onPressed: () => provider.removeResource(
              kind: item.kind,
              chapterIndex: item.chapterIndex,
              itemIndex: item.itemIndex,
            ),
          ),
          onTap: () => _edit(context, item),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, EditableResource item) async {
    final primaryCtrl = TextEditingController(text: item.primary);
    final secondaryCtrl = TextEditingController(text: item.secondary);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.aiTextbookEditResource,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: primaryCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTextbookPrimaryField,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: secondaryCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTextbookSecondaryField,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppStrings.commonSave),
              ),
            ],
          ),
        );
      },
    );
    if (saved == true) {
      provider.updateResource(
        kind: item.kind,
        chapterIndex: item.chapterIndex,
        itemIndex: item.itemIndex,
        primary: primaryCtrl.text.trim(),
        secondary: secondaryCtrl.text.trim(),
      );
    }
    primaryCtrl.dispose();
    secondaryCtrl.dispose();
  }
}
