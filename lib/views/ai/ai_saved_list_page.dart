// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/ai/components/ai_generated_notice.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/search_field.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 收藏的讲解 —— 阅读目录模式（R14）：[DirectoryEntryRow] 词条行（标题 +
/// 摘录 + 元信息），发丝线分隔；正文走全局弹层。搜索换 [TurnaSearchField]
/// （250ms 防抖内建）。
@RoutePage()
class AiSavedListPage extends StatefulWidget {
  const AiSavedListPage({super.key});

  @override
  State<AiSavedListPage> createState() => _AiSavedListPageState();
}

class _AiSavedListPageState extends State<AiSavedListPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.aiSavedListTitle,
          style: AppTextStyles.cardTitle(context).copyWith(fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.sm,
                AppSpacing.pageMargin,
                AppSpacing.md,
              ),
              child: TurnaSearchField(
                hint: AppStrings.aiSavedSearchHint,
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                onDebouncedChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: Consumer<AiSavedExplanationsStore>(
                builder: (context, store, _) {
                  final items = store.search(_query);
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          AppStrings.aiSavedListEmpty,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyText(context).copyWith(
                            fontSize: 15,
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageMargin,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return DirectoryEntryRow(
                        title: e.title,
                        subtitle: e.body,
                        meta:
                            '${AppStrings.aiSavedSourceLabel(e.source)} · ${DateFormat.yMMMd().add_Hm().format(e.createdAt.toLocal())}',
                        showDivider: i < items.length - 1,
                        onTap: () => _openDetail(context, e),
                        trailing: IconButton(
                          tooltip: AppStrings.aiSavedDelete,
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              _deleteWithUndo(context, store, e),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    AiSavedExplanationsStore store,
    SavedExplanation item,
  ) async {
    await store.delete(item.id);
    if (!context.mounted) return;
    TurnaSnackBar.show(
      context,
      AppStrings.aiSavedDeleted,
      action: SnackBarAction(
        label: AppStrings.commonUndo,
        onPressed: () {
          unawaited(store.save(item));
        },
      ),
      duration: const Duration(seconds: 5),
    );
  }

  void _openDetail(BuildContext context, SavedExplanation e) {
    showTurnaSheet<void>(
      context: context,
      title: e.title,
      body: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(e.body),
                // Saved explanations are model output too — copying them
                // out must not strip the label (标识办法 §10 forbids
                // hiding the notice).
                const AiGeneratedNotice(),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.aiDepthCopy,
          primary: true,
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: labelAiGenerated(e.body)),
            );
            TurnaSnackBar.maybeShow(context, AppStrings.aiDepthCopied);
          },
        ),
      ],
    );
  }
}
