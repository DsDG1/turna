// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_select.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// 生成练习面板（R14：偏好目录表单模式 —— label 左、值右；全局弹层容器）。
///
/// Two modes:
///   * 按学习数据 — mistakes / weak words / difficult points, always one
///     one-lesson mastery drill;
///   * 自定义课程 — topic + units × lessons + template + design brief.
///
/// The sheet only enqueues; progress lives in the AI Hub library（一行化进度行）
/// so the learner can close this sheet and keep using the app.
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

  String get _templateLabel => switch (_template) {
        'mastery' => AppStrings.aiPracticeTemplateMastery,
        'practice' => AppStrings.aiPracticeTemplatePractice,
        'review' => AppStrings.aiPracticeTemplateReview,
        _ => AppStrings.aiPracticeTemplateMixed,
      };

  String get _sourceLabel => switch (_source) {
        AiPracticeSource.mistakes => AppStrings.aiPracticeSourceMistakes,
        AiPracticeSource.weakWords => AppStrings.aiPracticeSourceWeakWords,
        AiPracticeSource.difficult => AppStrings.aiPracticeSourceDifficult,
        AiPracticeSource.custom => AppStrings.aiPracticeSourceCustom,
      };

  @override
  Widget build(BuildContext context) {
    final complete =
        context.select((AiEngineConfigHolder h) => h.config.isComplete);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!complete) ...[
              const _ConfigWarning(),
              const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.sm),
            if (_customMode) _customForm(context) else _practiceForm(context),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: const TextStyle(
                    color: TurnaTheme.error, height: 1.4),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SessionPrimaryAction(
              label: _busy
                  ? AppStrings.aiPracticeGenerating
                  : AppStrings.aiPracticeStartGeneration,
              onPressed: complete && !_busy ? _start : null,
              trailingIcon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  /// 未配置的一行提示（不占卡）：连接入口由 AI 大厅首屏主行动承担。

  Widget _practiceForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DirectoryValueRow(
          label: AppStrings.aiPracticeSourceLabel,
          value: _sourceLabel,
          onTap: () => _pick(
            title: AppStrings.aiPracticeSourceLabel,
            options: [
              (
                AiPracticeSource.mistakes,
                AppStrings.aiPracticeSourceMistakes
              ),
              (
                AiPracticeSource.weakWords,
                AppStrings.aiPracticeSourceWeakWords
              ),
              (
                AiPracticeSource.difficult,
                AppStrings.aiPracticeSourceDifficult
              ),
            ],
            current: _source,
            onSelected: (value) => setState(() => _source = value),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeLevelLabel,
          value: _level,
          showDivider: false,
          onTap: () => _pick(
            title: AppStrings.aiPracticeLevelLabel,
            options: [for (final level in _levels) (level, level)],
            current: _level,
            onSelected: (value) => setState(() => _level = value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _estimate(context, 1 + 1),
      ],
    );
  }

  Widget _customForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _textEntry(
          label: AppStrings.aiPracticeCustomTopic,
          controller: _topicCtrl,
          hint: AppStrings.aiPracticeCustomTopicHint,
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeLevelLabel,
          value: _level,
          onTap: () => _pick(
            title: AppStrings.aiPracticeLevelLabel,
            options: [for (final level in _levels) (level, level)],
            current: _level,
            onSelected: (value) => setState(() => _level = value),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomUnits,
          value: '$_units',
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomUnits,
            options: [
              for (var i = 1; i <= 4; i++) ('$i', '$i'),
            ],
            current: '$_units',
            onSelected: (value) =>
                setState(() => _units = int.parse(value)),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomLessons,
          value: '$_lessons',
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomLessons,
            options: [
              for (var i = 1; i <= 4; i++) ('$i', '$i'),
            ],
            current: '$_lessons',
            onSelected: (value) =>
                setState(() => _lessons = int.parse(value)),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomTemplate,
          value: _templateLabel,
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomTemplate,
            options: [
              ('mastery', AppStrings.aiPracticeTemplateMastery),
              ('practice', AppStrings.aiPracticeTemplatePractice),
              ('review', AppStrings.aiPracticeTemplateReview),
              ('mixed', AppStrings.aiPracticeTemplateMixed),
            ],
            current: _template,
            onSelected: (value) => setState(() => _template = value),
          ),
        ),
        _textEntry(
          label: AppStrings.aiPracticeCustomDesignBrief,
          controller: _briefCtrl,
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomGrounded,
          control: Switch(
            value: _grounded,
            onChanged: (value) => setState(() => _grounded = value),
          ),
          showDivider: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        _estimate(context, 1 + _units * _lessons + 1),
      ],
    );
  }

  /// 文本输入行：label 在上、输入域占整行（文本域无法右置）。
  Widget _textEntry({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.captionSm(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm - 2),
          TextField(
            controller: controller,
            maxLines: 2,
            decoration: aiSheetInputDecoration(context, hint: hint),
          ),
        ],
      ),
    );
  }

  Widget _estimate(BuildContext context, int calls) => Text(
        '${AppStrings.aiPracticeEstimatedCalls(calls)} · '
        '${AppStrings.aiPracticeLessonPlan(_customMode ? _units * _lessons : 1)}',
        style: AppTextStyles.captionSm(context).copyWith(
          color: TurnaTheme.textHintColor(context),
        ),
      );

  /// 偏好目录深页式的取值：值行 → 选项弹层（全局弹层容器），点选即回填。
  Future<void> _pick<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
    required ValueChanged<T> onSelected,
  }) {
    return showTurnaSheet<T>(
      context: context,
      title: title,
      body: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              _PickOptionRow(
                label: options[i].$2,
                selected: options[i].$1 == current,
                showDivider: i < options.length - 1,
                onTap: () => Navigator.of(context).pop(options[i].$1),
              ),
          ],
        ),
      ),
    ).then((value) {
      if (value != null) onSelected(value);
    });
  }

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

/// 未配置的一行提示：警告色小字，不占卡。
class _ConfigWarning extends StatelessWidget {
  const _ConfigWarning();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: TurnaTheme.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppStrings.aiPracticeNotConfigured,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textSecondaryColor(context),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// 选项弹层里的一行：标签 + 选中打勾（轮廓表达，不靠颜色）。
class _PickOptionRow extends StatelessWidget {
  const _PickOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDivider = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyText(context).copyWith(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: TurnaTheme.brandTeal,
              ),
          ],
        ),
      ),
    );
    if (!showDivider) return row;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
        ),
      ),
      child: row,
    );
  }
}

/// Opens the generation sheet from the Hub, the library page, or the guide.
Future<void> showAiPracticeGenerateSheet(
  BuildContext context, {
  AiPracticeSource source = AiPracticeSource.mistakes,
  bool customMode = false,
}) {
  return showTurnaSheet<void>(
    context: context,
    title: AppStrings.aiPracticeGenerateTitle,
    subtitle: AppStrings.aiPracticeBackgroundHint,
    isScrollControlled: true,
    body: AiPracticeGenerateSheet(
      initialSource: source,
      initialCustomMode: customMode,
    ),
  );
}
