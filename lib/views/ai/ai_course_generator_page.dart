// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class AiCourseGeneratorPage extends StatefulWidget {
  const AiCourseGeneratorPage({Key? key}) : super(key: key);

  @override
  State<AiCourseGeneratorPage> createState() => _AiCourseGeneratorPageState();
}

class _AiCourseGeneratorPageState extends State<AiCourseGeneratorPage> {
  final _topicKey = GlobalKey<FormFieldState<String>>();
  final _extraKey = GlobalKey<FormFieldState<String>>();

  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _languageCtrl;
  late final TextEditingController _sourceLanguageCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _extraCtrl;
  late final TextEditingController _jsonCtrl;

  String _level = 'A1';
  int _unitCount = 1;
  int _lessonsPerUnit = 3;
  String _template = 'mixed';
  bool _useGenreBatch = false;
  bool _wishMode = false;

  static const _templateOptions = <String>[
    'intro',
    'practice',
    'review',
    'listening',
    'reading',
    'mastery',
    'mixed',
  ];

  @override
  void initState() {
    super.initState();
    final p = context.read<AiCourseProvider>();
    _baseUrlCtrl = TextEditingController(text: p.config.baseUrl);
    _apiKeyCtrl = TextEditingController(text: p.config.apiKey);
    _modelCtrl = TextEditingController(text: p.config.model);
    _languageCtrl = TextEditingController(text: 'Turkish');
    _sourceLanguageCtrl = TextEditingController(text: 'Chinese');
    _topicCtrl = TextEditingController();
    _extraCtrl = TextEditingController();
    _jsonCtrl = TextEditingController(text: p.generatedJson ?? '');
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _languageCtrl.dispose();
    _sourceLanguageCtrl.dispose();
    _topicCtrl.dispose();
    _extraCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _syncConfigToProvider() {
    context.read<AiCourseProvider>().updateConfig(
          baseUrl: _baseUrlCtrl.text.trim(),
          apiKey: _apiKeyCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
        );
  }

  AiCourseSpec _buildSpec() {
    return AiCourseSpec(
      language:
          _languageCtrl.text.trim().isEmpty ? 'Turkish' : _languageCtrl.text.trim(),
      sourceLanguage: _sourceLanguageCtrl.text.trim().isEmpty
          ? 'Chinese'
          : _sourceLanguageCtrl.text.trim(),
      topic: _topicCtrl.text.trim(),
      level: _level,
      unitCount: _unitCount,
      lessonsPerUnit: _lessonsPerUnit,
      template: _template,
      useGenreBatch: _useGenreBatch,
      extraInstructions: _extraCtrl.text.trim(),
    );
  }

  Future<void> _onGenerate() async {
    _syncConfigToProvider();
    if (_topicCtrl.text.trim().isEmpty) return;
    final spec = _buildSpec();
    await context.read<AiCourseProvider>().generate(spec);
    if (!mounted) return;
    final p = context.read<AiCourseProvider>();
    if (p.generatedJson != null) {
      _jsonCtrl.text = p.generatedJson!;
    }
  }

  Future<void> _onSave() async {
    final p = context.read<AiCourseProvider>();
    p.updateGeneratedJson(_jsonCtrl.text);
    try {
      await p.save();
      if (!mounted) return;
      await context.read<CourseProvider>().reloadCourse();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course saved to database.')),
      );
      context.router.maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'AI Course Generator',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        backgroundColor: VarnamalaTheme.bottomNavBg(context),
      ),
      body: Consumer<AiCourseProvider>(
        builder: (context, p, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _modeSwitch(p),
              const SizedBox(height: 16),
              _configSection(p),
              const SizedBox(height: 16),
              if (_wishMode) _wishEntry(p) else _specSection(p),
              const SizedBox(height: 16),
              _resultSection(p),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _modeSwitch(AiCourseProvider p) {
    return Card(
      color: VarnamalaTheme.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              '模式',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('普通模式')),
                  ButtonSegment(value: true, label: Text('许愿模式')),
                ],
                selected: {_wishMode},
                onSelectionChanged: (s) => setState(() => _wishMode = s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wishEntry(AiCourseProvider p) {
    return Card(
      color: VarnamalaTheme.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '许愿模式（Beta）',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              '通过多轮对话与 AI 对齐课程设计意图，再生成最终课程。'
              '请先在下方填写课程参数（语言/主题/等级/模板等），然后进入对话。',
            ),
            const SizedBox(height: 12),
            _specFields(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.router.push(const AiWishChatRoute()),
                icon: const Icon(Icons.chat),
                label: const Text('前往许愿对话'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configSection(AiCourseProvider p) {
    return Card(
      color: VarnamalaTheme.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API Configuration (not saved on exit)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'gpt-4o-mini',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _specSection(AiCourseProvider p) {
    final busy = p.state == AiCourseState.generating ||
        p.state == AiCourseState.saving;
    return Card(
      color: VarnamalaTheme.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Course Specs',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            _specFields(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _template,
                    decoration: const InputDecoration(
                      labelText: 'Template',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _templateOptions
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text('$t (${templateLabel(t)})'),
                            ))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _template = v ?? 'mixed'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Genre batch'),
                    value: _useGenreBatch,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _useGenreBatch = v),
                    dense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _onGenerate,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(p.state == AiCourseState.generating
                    ? 'Generating…'
                    : 'Generate Course'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _specFields() {
    final busy = context.read<AiCourseProvider>().state ==
            AiCourseState.generating ||
        context.read<AiCourseProvider>().state == AiCourseState.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _languageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Target language',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sourceLanguageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Source language',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: _topicKey,
          controller: _topicCtrl,
          decoration: const InputDecoration(
            labelText: 'Topic / theme',
            hintText: 'e.g. Travel vocabulary, Past tense, Food & drink',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _level,
                decoration: const InputDecoration(
                  labelText: 'Level',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: ['A1', 'A2', 'B1', 'B2', 'C1']
                    .map((l) => DropdownMenuItem(
                          value: l,
                          child: Text(l),
                        ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() => _level = v ?? 'A1'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _unitCount,
                decoration: const InputDecoration(
                  labelText: 'Units',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [1, 2, 3, 4, 5]
                    .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n'),
                        ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() => _unitCount = v ?? 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _lessonsPerUnit,
                decoration: const InputDecoration(
                  labelText: 'Lessons/unit',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [1, 2, 3, 4, 5]
                    .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n'),
                        ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() => _lessonsPerUnit = v ?? 3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: _extraKey,
          controller: _extraCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Extra instructions (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _resultSection(AiCourseProvider p) {
    if (p.state == AiCourseState.generating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (p.state == AiCourseState.error && p.error != null) {
      return Card(
        color: VarnamalaTheme.cardBg(context),
        child: ListTile(
          leading:
              const Icon(Icons.error_outline, color: VarnamalaTheme.error),
          title: const Text('Generation failed'),
          subtitle: Text(p.error!),
        ),
      );
    }
    if (p.generatedJson == null && _jsonCtrl.text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      color: VarnamalaTheme.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Generated JSON (editable)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _jsonCtrl.text = p.generatedJson ?? _jsonCtrl.text;
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
            if (p.explanation != null && p.explanation!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.streakChipBg(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 解释',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(p.explanation!),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: TextField(
                controller: _jsonCtrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: p.state == AiCourseState.saving
                        ? null
                        : _onSave,
                    icon: p.state == AiCourseState.saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(p.state == AiCourseState.saving
                        ? 'Saving…'
                        : 'Save to Course Tree'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}