// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/textbook/knowledge_merger.dart';
import 'package:varnamala/application/ai/textbook/textbook_import_provider.dart';
import 'package:varnamala/l10n/app_localizations.dart';
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
    context.read<TextbookImportProvider>().reset();
  }

  Future<void> _onExtract() async {
    final config = context.read<AiCourseProvider>().config;
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
        title: Text(AppLocalizations.of(context)!.aiNotConfiguredTitle),
        content: Text(
            AppLocalizations.of(context)!.aiTextbookNotConfiguredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.commonOk),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.aiTextbookImportTitle),
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
                  _settingsRow(provider),
                  const SizedBox(height: 16),
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
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.aiTextbookTargetLanguageLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: ['Turkish', 'English', 'Spanish']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => provider.updateSettings(language: v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: provider.sourceLanguage,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.aiTextbookSourceLanguageLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: ['Chinese', 'English']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => provider.updateSettings(sourceLanguage: v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: provider.level,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.aiTextbookLevelLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: ['A1', 'A2', 'B1', 'B2']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => provider.updateSettings(level: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ImportStrategy>(
          value: provider.strategy,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.aiTextbookImportStrategyLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: ImportStrategy.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.name),
                  ))
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
        return _loadingStep(AppLocalizations.of(context)!.aiTextbookParsing);
      case TextbookImportStep.chapters:
        return _chaptersStep(provider);
      case TextbookImportStep.extract:
        return _loadingStep(AppLocalizations.of(context)!.aiTextbookExtracting);
      case TextbookImportStep.review:
        return _reviewStep(provider);
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
            AppLocalizations.of(context)!.aiTextbookPickPrompt,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: provider.isBusy ? null : provider.pickFile,
            icon: const Icon(Icons.file_open),
            label: Text(AppLocalizations.of(context)!.aiTextbookPickFile),
          ),
          if (provider.fileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.aiTextbookSelected(provider.fileName)),
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
          AppLocalizations.of(context)!.aiTextbookReviewChapters,
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
                  AppLocalizations.of(context)!.aiTextbookChapterChars(r.chapter.markdown.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _reviewStep(TextbookImportProvider provider) {
    final kept = provider.results.where((r) => r.keep).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.aiTextbookReviewKnowledge,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: kept.length,
            itemBuilder: (context, i) {
              final r = kept[i];
              final k = r.knowledge;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.chapter.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (r.error != null)
                        Text(
                          AppLocalizations.of(context)!.aiTextbookErrorFooter(r.error!),
                          style: const TextStyle(color: VarnamalaTheme.error),
                        ),
                      if (k != null) ...[
                        Text(AppLocalizations.of(context)!.aiTextbookWords(k.words.length)),
                        Text(AppLocalizations.of(context)!.aiTextbookExpressions(k.expressions.length)),
                        Text(AppLocalizations.of(context)!.aiTextbookGrammar(k.grammarPoints.length)),
                      ],
                    ],
                  ),
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
          Text(AppLocalizations.of(context)!.aiTextbookImportComplete),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.router.maybePop(),
            child: Text(AppLocalizations.of(context)!.commonDone),
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
          AppLocalizations.of(context)!.aiTextbookErrorFooter(provider.error!),
          style: const TextStyle(color: VarnamalaTheme.error),
        ),
      );
    }

    switch (provider.step) {
      case TextbookImportStep.chapters:
        return FilledButton.icon(
          onPressed: provider.isBusy ? null : _onExtract,
          icon: const Icon(Icons.auto_awesome),
          label: Text(AppLocalizations.of(context)!.aiTextbookExtractKnowledge),
        );
      case TextbookImportStep.review:
        return FilledButton.icon(
          onPressed: provider.isBusy ? null : _onImport,
          icon: const Icon(Icons.save),
          label: Text(AppLocalizations.of(context)!.aiTextbookImportSections),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
