// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/textbook/knowledge_merger.dart';
import 'package:varnamala/application/ai/textbook/textbook_import_provider.dart';
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
        title: const Text('AI not configured'),
        content: const Text(
            'Please fill in Base URL / API Key / Model under Settings → AI API Configuration first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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
        title: const Text('Import from Textbook'),
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
                initialValue: provider.language,
                decoration: const InputDecoration(
                  labelText: 'Target language',
                  isDense: true,
                  border: OutlineInputBorder(),
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
                initialValue: provider.sourceLanguage,
                decoration: const InputDecoration(
                  labelText: 'Source language',
                  isDense: true,
                  border: OutlineInputBorder(),
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
                initialValue: provider.level,
                decoration: const InputDecoration(
                  labelText: 'Level',
                  isDense: true,
                  border: OutlineInputBorder(),
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
          initialValue: provider.strategy,
          decoration: const InputDecoration(
            labelText: 'Import strategy',
            isDense: true,
            border: OutlineInputBorder(),
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
        return _loadingStep('Parsing file…');
      case TextbookImportStep.chapters:
        return _chaptersStep(provider);
      case TextbookImportStep.extract:
        return _loadingStep('Extracting knowledge…');
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
            'Pick a markdown or text file to import as course sections.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: provider.isBusy ? null : provider.pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Pick file'),
          ),
          if (provider.fileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Selected: ${provider.fileName}'),
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
          'Review chapters',
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
                  '${r.chapter.markdown.length} chars',
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
          'Review extracted knowledge',
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
                          'Error: ${r.error}',
                          style: const TextStyle(color: VarnamalaTheme.error),
                        ),
                      if (k != null) ...[
                        Text('Words: ${k.words.length}'),
                        Text('Expressions: ${k.expressions.length}'),
                        Text('Grammar: ${k.grammarPoints.length}'),
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
          const Text('Import complete!'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.router.maybePop(),
            child: const Text('Done'),
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
          'Error: ${provider.error}',
          style: const TextStyle(color: VarnamalaTheme.error),
        ),
      );
    }

    switch (provider.step) {
      case TextbookImportStep.chapters:
        return FilledButton.icon(
          onPressed: provider.isBusy ? null : _onExtract,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Extract knowledge'),
        );
      case TextbookImportStep.review:
        return FilledButton.icon(
          onPressed: provider.isBusy ? null : _onImport,
          icon: const Icon(Icons.save),
          label: const Text('Import sections'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
