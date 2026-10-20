// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// Bottom sheet that starts a background practice/course generation job.
///
/// Two modes:
///   * 按学习数据 — mistakes / weak words / difficult points, always one
///     one-lesson mastery drill;
///   * 自定义课程 — topic + units × lessons + template + design brief.
///
/// The sheet only enqueues; progress lives in the AI Hub library so the learner
/// can close this sheet and keep using the app.
class AiPracticeGenerateSheet extends StatefulWidget {
  const AiPracticeGenerateSheet({
    super.key,
    this.initialSource = AiPracticeSource.mistakes,
    this.initialCustomMode = false,
  });

  final AiPracticeSource initialSource;
  final bool initialCustomMode;

  @override
  State<AiPracticeGenerateSheet> createState() =>
      _AiPracticeGenerateSheetState();
}

class _AiPracticeGenerateSheetState extends State<AiPracticeGenerateSheet> {
  static const _levels = ['A1', 'A2', 'B1', 'B2'];
  static const _templates = <String, String>{
    'mastery': '综合测验',
    'practice': '巩固练习',
    'review': '复习',
    'mixed': '混合',
  };

  late bool _customMode;
  late AiPracticeSource _source;
  String _level = 'A1';
  final TextEditingController _topicCtrl = TextEditingController();
  final TextEditingController _briefCtrl = TextEditingController();
  int _units = 1;
  int _lessons = 1;
  String _template = 'mastery';
  bool _grounded = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customMode = widget.initialCustomMode;
    _source = widget.initialSource;
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _briefCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complete =
        context.select((AiEngineConfigHolder h) => h.config.isComplete);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 12),
              if (!complete) ...[
                _configWarning(context),
                const SizedBox(height: 12),
              ],
              TurnaSegmented<bool>(
                selected: _customMode,
                onChanged: (value) => setState(() => _customMode = value),
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(AppStrings.aiPracticeModeData),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(AppStrings.aiPracticeModeCustom),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_customMode) _customForm(context) else _practiceForm(context),
              const SizedBox(height: 12),
              Text(
                AppStrings.aiPracticeBackgroundHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                      height: 1.4,
                    ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: TurnaTheme.error, height: 1.4),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: complete && !_busy ? _start : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(AppStrings.aiPracticeStartGeneration),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: TurnaTheme.brandTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.aiPracticeGenerateTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _configWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Text(
        AppStrings.aiPracticeNotConfigured,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TurnaTheme.textPrimaryColor(context),
            ),
      ),
    );
  }

  Widget _practiceForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, AppStrings.aiPracticeSourceLabel),
        const SizedBox(height: 8),
        TurnaChoiceGrid<AiPracticeSource>(
          selected: _source,
          onSelected: (value) => setState(() => _source = value),
          items: [
            (
              AiPracticeSource.mistakes,
              AppStrings.aiPracticeSourceMistakes,
              Icons.history_toggle_off_rounded
            ),
            (
              AiPracticeSource.weakWords,
              AppStrings.aiPracticeSourceWeakWords,
              Icons.quiz_rounded
            ),
            (
              AiPracticeSource.difficult,
              AppStrings.aiPracticeSourceDifficult,
              Icons.account_tree_outlined
            ),
          ],
        ),
        const SizedBox(height: 16),
        _label(context, AppStrings.aiPracticeLevelLabel),
        const SizedBox(height: 8),
        TurnaSegmented<String>(
          selected: _level,
          onChanged: (value) => setState(() => _level = value),
          segments: [
            for (final level in _levels)
              ButtonSegment(value: level, label: Text(level)),
          ],
        ),
        const SizedBox(height: 12),
        _estimate(context, 1 + 1),
      ],
    );
  }

  Widget _customForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, AppStrings.aiPracticeCustomTopic),
        const SizedBox(height: 6),
        TextField(
          controller: _topicCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: AppStrings.aiPracticeCustomTopicHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _label(context, AppStrings.aiPracticeLevelLabel),
        const SizedBox(height: 8),
        TurnaSegmented<String>(
          selected: _level,
          onChanged: (value) => setState(() => _level = value),
          segments: [
            for (final level in _levels)
              ButtonSegment(value: level, label: Text(level)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _units,
                isDense: true,
                decoration: InputDecoration(
                  labelText: AppStrings.aiPracticeCustomUnits,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var i = 1; i <= 4; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (value) => setState(() => _units = value ?? 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _lessons,
                isDense: true,
                decoration: InputDecoration(
                  labelText: AppStrings.aiPracticeCustomLessons,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var i = 1; i <= 4; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (value) => setState(() => _lessons = value ?? 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _template,
          isDense: true,
          decoration: InputDecoration(
            labelText: AppStrings.aiPracticeCustomTemplate,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final entry in _templates.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => setState(() => _template = value ?? 'mastery'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _briefCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppStrings.aiPracticeCustomDesignBrief,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppStrings.aiPracticeCustomGrounded),
          value: _grounded,
          onChanged: (value) => setState(() => _grounded = value),
        ),
        _estimate(context, 1 + _units * _lessons + 1),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      );

  Widget _estimate(BuildContext context, int calls) => Text(
        '${AppStrings.aiPracticeEstimatedCalls(calls)} · '
        '${AppStrings.aiPracticeLessonPlan(_customMode ? _units * _lessons : 1)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
      );

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queue = context.read<AiPracticeJobQueue>();
      if (_customMode) {
        if (_topicCtrl.text.trim().isEmpty) {
          setState(() {
            _busy = false;
            _error = '请先填写课程主题。';
          });
          return;
        }
        await queue.startCustomCourse(
          topic: _topicCtrl.text,
          level: _level,
          unitCount: _units,
          lessonsPerUnit: _lessons,
          template: _template,
          designBrief: _briefCtrl.text,
          grounded: _grounded,
        );
      } else {
        await queue.startPractice(source: _source, level: _level);
      }
      if (!mounted) return;
      await Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '加入队列失败：$e';
      });
    }
  }
}

/// Opens the generation sheet from the Hub, the library page, or the guide.
Future<void> showAiPracticeGenerateSheet(
  BuildContext context, {
  AiPracticeSource source = AiPracticeSource.mistakes,
  bool customMode = false,
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
    builder: (_) => AiPracticeGenerateSheet(
      initialSource: source,
      initialCustomMode: customMode,
    ),
  );
}
