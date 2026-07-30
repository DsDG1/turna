// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/ai/textbook/knowledge_merger.dart';
import 'package:varnamala/application/ai/textbook/textbook_import_provider.dart';
import 'package:varnamala/application/ai/textbook/textbook_presets.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/ai/textbook/textbook_conflict_preview.dart';
import 'package:varnamala/views/ai/textbook/textbook_review_panel.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class TextbookImportPage extends StatefulWidget {
  const TextbookImportPage({Key? key}) : super(key: key);

  @override
  State<TextbookImportPage> createState() => _TextbookImportPageState();
}

class _TextbookImportPageState extends State<TextbookImportPage> {
  @override
  void initState() {
    super.initState();
    // Defer: reset() notifies listeners, which is illegal while the router is
    // still building this page's ancestors (setState during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TextbookImportProvider>().reset();
    });
  }

  Future<void> _onExtract() async {
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      await _showAiConfigPrompt();
      return;
    }
    await context.read<TextbookImportProvider>().extractAll(config);
  }

  Future<void> _onImport() async {
    final provider = context.read<TextbookImportProvider>();
    final courseProvider = context.read<AiCourseProvider>();
    await provider.importSections(courseProvider);
  }

  Future<void> _showAiConfigPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.aiNotConfiguredTitle),
        content: Text(AppStrings.aiTextbookNotConfiguredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.commonOk),
          ),
        ],
      ),
    );
  }

  String _strategyLabel(ImportStrategy s) => switch (s) {
        ImportStrategy.merge => AppStrings.aiTextbookStrategyMerge,
        ImportStrategy.skipExisting => AppStrings.aiTextbookStrategySkip,
        ImportStrategy.forceReplace => AppStrings.aiTextbookStrategyReplace,
        ImportStrategy.appendAsNew => AppStrings.aiTextbookStrategyAppend,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.aiTextbookImportTitle),
        backgroundColor: VarnamalaTheme.bottomNavBg(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer<TextbookImportProvider>(
            builder: (context, provider, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (provider.step != TextbookImportStep.importDone &&
                      provider.step != TextbookImportStep.extract &&
                      provider.step != TextbookImportStep.parse)
                    _settingsRow(provider),
                  if (provider.step != TextbookImportStep.importDone &&
                      provider.step != TextbookImportStep.extract &&
                      provider.step != TextbookImportStep.parse)
                    const SizedBox(height: 12),
                  Expanded(child: _stepBody(provider)),
                  _bottomActions(provider),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _settingsRow(TextbookImportProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: provider.language,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTextbookTargetLanguageLabel,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: ['Turkish', 'English', 'Spanish']
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text(l,
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    )
                    .toList(),
                onChanged: (v) => provider.updateSettings(language: v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: provider.sourceLanguage,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTextbookSourceLanguageLabel,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: ['Chinese', 'English']
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text(l,
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    )
                    .toList(),
                onChanged: (v) => provider.updateSettings(sourceLanguage: v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: provider.level,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTextbookLevelLabel,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: ['A1', 'A2', 'B1', 'B2']
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text(l,
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                    )
                    .toList(),
                onChanged: (v) => provider.updateSettings(level: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: provider.preset.name,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppStrings.aiTextbookPresetLabel,
            isDense: true,
            helperText: provider.preset.description,
            helperMaxLines: 2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          items: textbookPresetNames
              .map((name) {
                final p = presetFor(name);
                return DropdownMenuItem(
                  value: name,
                  child: Text(p.label,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                );
              })
              .toList(),
          onChanged: (v) {
            if (v != null) provider.updateSettings(preset: presetFor(v));
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ImportStrategy>(
          value: provider.strategy,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppStrings.aiTextbookImportStrategyLabel,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          items: ImportStrategy.values
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    _strategyLabel(s),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => provider.updateSettings(strategy: v),
        ),
      ],
    );
  }

  Widget _stepBody(TextbookImportProvider provider) {
    switch (provider.step) {
      case TextbookImportStep.pick:
        return _pickStep(provider);
      case TextbookImportStep.parse:
        return _loadingStep(AppStrings.aiTextbookParsing);
      case TextbookImportStep.chapters:
        return _chaptersStep(provider);
      case TextbookImportStep.extract:
        return _loadingStep(AppStrings.aiTextbookExtracting);
      case TextbookImportStep.review:
        return TextbookReviewPanel(provider: provider);
      case TextbookImportStep.conflict:
        return TextbookConflictPreview(provider: provider);
      case TextbookImportStep.importDone:
        return _doneStep(provider);
    }
  }

  Widget _pickStep(TextbookImportProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppStrings.aiTextbookPickPrompt,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: provider.isBusy ? null : provider.pickFile,
            icon: const Icon(Icons.file_open),
            label: Text(AppStrings.aiTextbookPickFile),
          ),
          if (provider.fileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(AppStrings.aiTextbookSelected(provider.fileName)),
          ],
        ],
      ),
    );
  }

  Widget _loadingStep(String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: VarnamalaTheme.peacockTeal),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }

  Widget _chaptersStep(TextbookImportProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.aiTextbookReviewChapters,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: provider.results.length,
            itemBuilder: (context, i) {
              final r = provider.results[i];
              return CheckboxListTile(
                value: r.keep,
                onChanged: (v) => provider.setChapterKept(i, v ?? true),
                title: Text(r.chapter.title),
                subtitle: Text(
                  AppStrings.aiTextbookChapterChars(r.chapter.markdown.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _doneStep(TextbookImportProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle,
              color: VarnamalaTheme.success, size: 64),
          const SizedBox(height: 16),
          Text(AppStrings.aiTextbookImportComplete),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.router.maybePop(),
            child: Text(AppStrings.commonDone),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions(TextbookImportProvider provider) {
    if (provider.error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: VarnamalaTheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        ),
        child: Text(
          AppStrings.aiTextbookErrorFooter(provider.error!),
          style: const TextStyle(color: VarnamalaTheme.error),
        ),
      );
    }

    switch (provider.step) {
      case TextbookImportStep.chapters:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.icon(
            onPressed: provider.isBusy ? null : _onExtract,
            icon: const Icon(Icons.auto_awesome),
            label: Text(AppStrings.aiTextbookExtractKnowledge),
          ),
        );
      case TextbookImportStep.review:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.icon(
            onPressed:
                provider.isBusy ? null : () => provider.prepareConflictPreview(),
            icon: const Icon(Icons.preview_outlined),
            label: Text(AppStrings.aiTextbookContinueToConflict),
          ),
        );
      case TextbookImportStep.conflict:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      provider.isBusy ? null : provider.backToReview,
                  child: Text(AppStrings.aiTextbookBackToReview),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: provider.isBusy ? null : _onImport,
                  icon: const Icon(Icons.save),
                  label: Text(AppStrings.aiTextbookConfirmImport),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
