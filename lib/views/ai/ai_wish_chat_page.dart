// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';
import 'package:varnamala/application/ai/ai_wish_provider.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class AiWishChatPage extends StatefulWidget {
  const AiWishChatPage({Key? key}) : super(key: key);

  @override
  State<AiWishChatPage> createState() => _AiWishChatPageState();
}

class _AiWishChatPageState extends State<AiWishChatPage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Local spec inputs (mirror generator page).
  late final TextEditingController _languageCtrl;
  late final TextEditingController _sourceLanguageCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _extraCtrl;
  String _level = 'A1';
  int _unitCount = 1;
  int _lessonsPerUnit = 3;
  String _template = 'mixed';
  bool _useGenreBatch = false;

  @override
  void initState() {
    super.initState();
    _languageCtrl = TextEditingController(text: 'Turkish');
    _sourceLanguageCtrl = TextEditingController(text: 'Chinese');
    _topicCtrl = TextEditingController();
    _extraCtrl = TextEditingController();
    context.read<AiWishProvider>().reset();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _languageCtrl.dispose();
    _sourceLanguageCtrl.dispose();
    _topicCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  AiApiConfig _config() => context.read<AiCourseProvider>().config;

  AiCourseSpec _buildSpec() => AiCourseSpec(
        language: _languageCtrl.text.trim().isEmpty
            ? 'Turkish'
            : _languageCtrl.text.trim(),
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

  Future<void> _onSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    await context.read<AiWishProvider>().sendAlignment(
          config: _config(),
          spec: _buildSpec(),
          userText: text,
        );
    _scrollToBottom();
  }

  Future<void> _onFinalize() async {
    await context.read<AiWishProvider>().finalizeGeneration(
          config: _config(),
          spec: _buildSpec(),
        );
    if (!mounted) return;
    final wish = context.read<AiWishProvider>();
    if (wish.generatedJson != null) {
      final courseProvider = context.read<AiCourseProvider>();
      courseProvider.updateGeneratedJson(wish.generatedJson!);
      courseProvider.setExplanation(wish.explanation);
    }
  }

  Future<void> _onSave() async {
    final courseProvider = context.read<AiCourseProvider>();
    try {
      await courseProvider.save();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'AI 课程设计对话',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        backgroundColor: VarnamalaTheme.bottomNavBg(context),
      ),
      body: SafeArea(
        child: Consumer<AiWishProvider>(
          builder: (context, w, _) {
            final busy = w.state == AiWishState.aligning ||
                w.state == AiWishState.generating ||
                w.state == AiWishState.explaining;
            return Column(
              children: [
                _specSummary(),
                Expanded(
                  child: w.messages.isEmpty && !busy
                      ? _emptyHint()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: w.messages.length + (w.error != null ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == w.messages.length && w.error != null) {
                              return _errorBubble(w.error!);
                            }
                            final m = w.messages[i];
                            return _bubble(m.role, m.content);
                          },
                        ),
                ),
                if (w.state == AiWishState.generated) _generatedPanel(w, busy),
                if (busy) const LinearProgressIndicator(),
                _inputBar(w, busy),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _specSummary() {
    return Container(
      width: double.infinity,
      color: VarnamalaTheme.cardBg(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课程参数',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _languageCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标语言',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sourceLanguageCtrl,
                  decoration: const InputDecoration(
                    labelText: '源语言',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _topicCtrl,
            decoration: const InputDecoration(
              labelText: '主题',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _level,
                  decoration: const InputDecoration(
                    labelText: '等级',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: ['A1', 'A2', 'B1', 'B2', 'C1']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setState(() => _level = v ?? 'A1'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _unitCount,
                  decoration: const InputDecoration(
                    labelText: '单元',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) => setState(() => _unitCount = v ?? 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _lessonsPerUnit,
                  decoration: const InputDecoration(
                    labelText: '课时',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _lessonsPerUnit = v ?? 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _template,
                  decoration: const InputDecoration(
                    labelText: '模板',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: ['intro', 'practice', 'review', 'listening', 'reading', 'mastery', 'mixed']
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text('$t (${templateLabel(t)})'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _template = v ?? 'mixed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SwitchListTile(
                  title: const Text('Genre batch'),
                  value: _useGenreBatch,
                  onChanged: (v) => setState(() => _useGenreBatch = v),
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _extraCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '额外指令（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '开始与 AI 对齐课程设计吧。在下方输入你的想法，例如：\n「我想教土耳其语旅行常用词，重点是打招呼和点餐。」',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _bubble(String role, String content) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? VarnamalaTheme.primaryLight
              : VarnamalaTheme.streakChipBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          content,
          style: TextStyle(
            color: isUser ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  Widget _errorBubble(String error) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: VarnamalaTheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '错误：$error',
          style: const TextStyle(color: VarnamalaTheme.error),
        ),
      ),
    );
  }

  Widget _generatedPanel(AiWishProvider w, bool busy) {
    return Container(
      width: double.infinity,
      color: VarnamalaTheme.cardBg(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课程已生成',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (w.explanation != null && w.explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('AI 解释：${w.explanation}'),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _onSave,
                  icon: const Icon(Icons.save),
                  label: const Text('保存到课程树'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputBar(AiWishProvider w, bool busy) {
    final generated = w.state == AiWishState.generated;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !busy && !generated,
              decoration: const InputDecoration(
                hintText: '输入你的想法…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: busy || generated ? null : _onSend,
            icon: const Icon(Icons.send),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: busy || generated ? null : _onFinalize,
            child: const Text('我感觉差不多了'),
          ),
        ],
      ),
    );
  }
}