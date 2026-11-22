// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_target_language_resolver.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_course_presets.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_outline_review_sheet.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_select.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// 生成练习面板（R14：偏好目录表单模式 —— label 左、值右；全局弹层容器）。
///
/// Two modes:
///   * 按学习数据 — mistakes / weak words / difficult points, always one
///     one-lesson drill;
///   * 自定义课程 — presets, target/source language, 1–10 units × 1–8 lessons,
///     density tiers, all 8 templates, preferred interaction types, focus items,
///     design brief, optional explanation, and optional two-step outline review.
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
  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  static const _commonLanguages = <(String, String)>[
    ('tr', 'Turkish'),
    ('en', 'English'),
    ('ja', 'Japanese'),
    ('fr', 'French'),
    ('de', 'German'),
    ('es', 'Spanish'),
    ('ko', 'Korean'),
  ];

  static const _interactionTypeChoices = <(String, String)>[
    ('showWord', '词汇卡片'),
    ('multipleChoice', '单项选择'),
    ('multiSelect', '多项选择'),
    ('fillBlank', '语境填空'),
    ('reorderSentence', '句子排序'),
    ('translateSentence', '句子翻译'),
    ('readingMcq', '阅读选择'),
    ('readingTrueFalse', '阅读判断'),
    ('readingShortAnswer', '阅读简答'),
  ];

  late bool _customMode;
  late AiPracticeSource _source;
  String _level = 'A1';
  final TextEditingController _topicCtrl = TextEditingController();
  final TextEditingController _briefCtrl = TextEditingController();
  final TextEditingController _focusCtrl = TextEditingController();
  int _units = 1;
  int _lessons = 2;
  int _itemsPerLesson = 10;
  String _template = 'mixed';
  String _targetLangCode = 'tr';
  String _targetLangName = 'Turkish';
  String? _activeCourseLangCode;
  String _sourceLanguageMode = 'Chinese';
  String? _presetId;
  final Set<String> _preferredTypes = <String>{};
  bool _grounded = true;
  bool _explanationRequested = false;
  bool _showAdvanced = false;
  bool _busy = false;
  bool _previewingOutline = false;
  String? _error;
  AiCancelToken? _outlineCancelToken;

  @override
  void initState() {
    super.initState();
    _customMode = widget.initialCustomMode;
    _source = widget.initialSource;
    _initTargetLanguage();
  }

  void _initTargetLanguage() {
    AiTargetLanguage? fromScope;
    try {
      final scope = context.read<CourseProvider>().scope;
      fromScope = AiTargetLanguageResolver.fromCourseScope(scope);
    } catch (_) {
      // Optional in isolated widget tests.
    }
    if (fromScope != null && !fromScope.isGeneric) {
      _targetLangCode = fromScope.code ?? 'tr';
      _targetLangName = fromScope.displayName ?? 'Turkish';
      _activeCourseLangCode = _targetLangCode;
      return;
    }
    try {
      final lp = context.read<LanguageProvider>();
      _targetLangCode = lp.selectedLanguageCode;
      _targetLangName = lp.displayName;
      _activeCourseLangCode = fromScope == null ? _targetLangCode : null;
      if (fromScope != null && fromScope.isGeneric) {
        _grounded = false;
      }
      return;
    } catch (_) {
      // Optional in isolated widget tests.
    }
  }

  @override
  void dispose() {
    _outlineCancelToken?.cancel();
    _topicCtrl.dispose();
    _briefCtrl.dispose();
    _focusCtrl.dispose();
    super.dispose();
  }

  String get _templateLabel => switch (_template) {
        'intro' => AppStrings.aiPracticeTemplateIntro,
        'mastery' => AppStrings.aiPracticeTemplateMastery,
        'practice' => AppStrings.aiPracticeTemplatePractice,
        'review' => AppStrings.aiPracticeTemplateReview,
        'reading' => AppStrings.aiPracticeTemplateReading,
        'dialogue' => AppStrings.aiPracticeTemplateDialogue,
        'guide' => AppStrings.aiPracticeTemplateGuide,
        _ => AppStrings.aiPracticeTemplateMixed,
      };

  String get _densityLabel => switch (_itemsPerLesson) {
        <= 6 => AppStrings.aiPracticeDensityLight,
        >= 14 => AppStrings.aiPracticeDensityIntensive,
        _ => AppStrings.aiPracticeDensityStandard,
      };

  String get _sourceLangLabel => switch (_sourceLanguageMode) {
        'English' => AppStrings.aiPracticeSourceLangEn,
        'Target' => AppStrings.aiPracticeSourceLangTarget,
        _ => AppStrings.aiPracticeSourceLangZh,
      };

  String get _effectiveSourceLanguage => switch (_sourceLanguageMode) {
        'English' => 'English',
        'Target' => _targetLangName,
        _ => 'Chinese',
      };

  String get _sourceLabel => switch (_source) {
        AiPracticeSource.mistakes => AppStrings.aiPracticeSourceMistakes,
        AiPracticeSource.weakWords => AppStrings.aiPracticeSourceWeakWords,
        AiPracticeSource.difficult => AppStrings.aiPracticeSourceDifficult,
        AiPracticeSource.custom => AppStrings.aiPracticeSourceCustom,
      };

  void _applyPreset(AiCoursePreset preset) {
    setState(() {
      if (_presetId == preset.id) {
        _presetId = null;
        return;
      }
      _presetId = preset.id;
      _template = preset.template;
      _units = preset.unitCount;
      _lessons = preset.lessonsPerUnit;
      _itemsPerLesson = preset.itemsPerLesson;
      _preferredTypes
        ..clear()
        ..addAll(preset.preferredInteractionTypes);
      _briefCtrl.text = preset.designBrief;
    });
  }

  List<(String, String)> _targetLanguageOptions() {
    final seen = <String>{};
    final out = <(String, String)>[];
    for (final lang in LanguageRegistry.instance.languages) {
      if (seen.add(lang.code)) {
        out.add((lang.code, lang.displayName));
      }
    }
    for (final (code, name) in _commonLanguages) {
      if (seen.add(code)) {
        out.add((code, name));
      }
    }
    if (!seen.contains(_targetLangCode)) {
      out.insert(0, (_targetLangCode, _targetLangName));
    }
    return out;
  }

  Future<void> _pickTargetLanguage() async {
    final options = _targetLanguageOptions();
    final customCtrl = TextEditingController();
    try {
      final result = await showTurnaSheet<(String, String)>(
        context: context,
        title: AppStrings.aiPracticeCustomTargetLanguage,
        isScrollControlled: true,
        body: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < options.length; i++)
                    _PickOptionRow(
                      label: options[i].$2,
                      selected: options[i].$1 == _targetLangCode,
                      showDivider: true,
                      onTap: () => Navigator.of(context).pop(options[i]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageMargin,
                      AppSpacing.md,
                      AppSpacing.pageMargin,
                      AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customCtrl,
                            decoration: aiSheetInputDecoration(
                              context,
                              hint: AppStrings.aiLanguageCustomInputHint,
                            ),
                            onSubmitted: (raw) {
                              final trimmed = raw.trim();
                              if (trimmed.isNotEmpty) {
                                Navigator.of(context).pop((trimmed, trimmed));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: () {
                            final trimmed = customCtrl.text.trim();
                            if (trimmed.isNotEmpty) {
                              Navigator.of(context).pop((trimmed, trimmed));
                            }
                          },
                          child: Text(AppStrings.commonApply),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _targetLangCode = result.$1;
          _targetLangName = result.$2;
          if (_activeCourseLangCode != null &&
              _targetLangCode != _activeCourseLangCode) {
            _grounded = false;
          }
        });
      }
    } finally {
      customCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = context.select(
      (AiEngineConfigHolder h) => h.config.isComplete,
    );
    final isBusy = _busy || _previewingOutline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageMargin),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
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
                  style: const TextStyle(color: TurnaTheme.error, height: 1.4),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_customMode) ...[
                OutlinedButton.icon(
                  onPressed:
                      complete && !isBusy ? _previewAndEditOutline : null,
                  icon: _previewingOutline
                      ? const TurnaLoader.inline(size: 14)
                      : const TurnaIcon(TurnaIconId.list, size: 16),
                  label: Text(
                    _previewingOutline
                        ? AppStrings.aiPracticeGeneratingOutline
                        : AppStrings.aiPracticePreviewOutline,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              SessionPrimaryAction(
                label: _busy
                    ? AppStrings.aiPracticeGenerating
                    : AppStrings.aiPracticeStartGeneration,
                onPressed: complete && !isBusy ? _start : null,
                trailingIcon: TurnaIconId.spark,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

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
              (AiPracticeSource.mistakes, AppStrings.aiPracticeSourceMistakes),
              (
                AiPracticeSource.weakWords,
                AppStrings.aiPracticeSourceWeakWords,
              ),
              (
                AiPracticeSource.difficult,
                AppStrings.aiPracticeSourceDifficult,
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
    final totalLessons = _units * _lessons;
    final calls = 1 + totalLessons + (_explanationRequested ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _presetsStrip(context),
        _textEntry(
          label: AppStrings.aiPracticeCustomTopic,
          controller: _topicCtrl,
          hint: AppStrings.aiPracticeCustomTopicHint,
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomTargetLanguage,
          value: _targetLangName,
          onTap: _pickTargetLanguage,
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomSourceLanguage,
          value: _sourceLangLabel,
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomSourceLanguage,
            options: [
              ('Chinese', AppStrings.aiPracticeSourceLangZh),
              ('English', AppStrings.aiPracticeSourceLangEn),
              ('Target', AppStrings.aiPracticeSourceLangTarget),
            ],
            current: _sourceLanguageMode,
            onSelected: (value) => setState(() => _sourceLanguageMode = value),
          ),
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
            options: [for (var i = 1; i <= 10; i++) ('$i', '$i')],
            current: '$_units',
            onSelected: (value) => setState(() => _units = int.parse(value)),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomLessons,
          value: '$_lessons',
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomLessons,
            options: [for (var i = 1; i <= 8; i++) ('$i', '$i')],
            current: '$_lessons',
            onSelected: (value) => setState(() => _lessons = int.parse(value)),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeItemsPerLesson,
          value: _densityLabel,
          onTap: () => _pick(
            title: AppStrings.aiPracticeItemsPerLesson,
            options: [
              (6, AppStrings.aiPracticeDensityLight),
              (10, AppStrings.aiPracticeDensityStandard),
              (15, AppStrings.aiPracticeDensityIntensive),
            ],
            current: _itemsPerLesson <= 6
                ? 6
                : _itemsPerLesson >= 14
                    ? 15
                    : 10,
            onSelected: (value) => setState(() => _itemsPerLesson = value),
          ),
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeCustomTemplate,
          value: _templateLabel,
          onTap: () => _pick(
            title: AppStrings.aiPracticeCustomTemplate,
            options: [
              ('mixed', AppStrings.aiPracticeTemplateMixed),
              ('intro', AppStrings.aiPracticeTemplateIntro),
              ('practice', AppStrings.aiPracticeTemplatePractice),
              ('review', AppStrings.aiPracticeTemplateReview),
              ('reading', AppStrings.aiPracticeTemplateReading),
              ('dialogue', AppStrings.aiPracticeTemplateDialogue),
              ('guide', AppStrings.aiPracticeTemplateGuide),
              ('mastery', AppStrings.aiPracticeTemplateMastery),
            ],
            current: _template,
            onSelected: (value) => setState(() => _template = value),
          ),
        ),
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.aiPracticeAdvancedToggle,
                    style: AppTextStyles.bodyText(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ),
                TurnaIcon(
                  _showAdvanced
                      ? TurnaIconId.chevronUp
                      : TurnaIconId.chevronDown,
                  size: 16,
                  color: TurnaTheme.brandTeal,
                ),
              ],
            ),
          ),
        ),
        if (_showAdvanced) _advancedSection(context),
        if (totalLessons > 12) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.aiPracticeLargeCourseHint,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.brandTeal,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _estimate(context, calls),
      ],
    );
  }

  Widget _presetsStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.aiPracticePresetsLabel,
            style: AppTextStyles.captionSm(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in AiCoursePresets.all)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(
                        preset.label,
                        style: AppTextStyles.captionSm(context),
                      ),
                      selected: _presetId == preset.id,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _applyPreset(preset),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.aiPracticePreferredTypes,
                style: AppTextStyles.captionSm(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (code, label) in _interactionTypeChoices)
                    FilterChip(
                      label: Text(
                        label,
                        style: AppTextStyles.captionSm(context),
                      ),
                      selected: _preferredTypes.contains(code),
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _preferredTypes.add(code);
                          } else {
                            _preferredTypes.remove(code);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        _textEntry(
          label: AppStrings.aiPracticeFocusItems,
          controller: _focusCtrl,
          hint: AppStrings.aiPracticeFocusItemsHint,
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
        ),
        DirectoryValueRow(
          label: AppStrings.aiPracticeExplainToggle,
          control: Switch(
            value: _explanationRequested,
            onChanged: (value) => setState(() => _explanationRequested = value),
          ),
          showDivider: false,
        ),
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
            style: AppTextStyles.captionSm(context)
                .copyWith(fontWeight: FontWeight.w600),
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
        style: AppTextStyles.captionSm(context)
            .copyWith(color: TurnaTheme.textHintColor(context)),
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
      isScrollControlled: true,
      body: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
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
        ),
      ),
    ).then((value) {
      if (value != null) onSelected(value);
    });
  }

  Future<void> _previewAndEditOutline() async {
    if (_topicCtrl.text.trim().isEmpty) {
      setState(() => _error = AppStrings.aiPracticeTopicRequired);
      return;
    }
    setState(() {
      _previewingOutline = true;
      _error = null;
    });
    final queue = context.read<AiPracticeJobQueue>();
    final token = AiCancelToken();
    _outlineCancelToken = token;

    Future<Map<String, dynamic>> fetchOutline() {
      return queue.generateOutlineForCustomCourse(
        topic: _topicCtrl.text,
        level: _level,
        unitCount: _units,
        lessonsPerUnit: _lessons,
        template: _template,
        languageCode: _targetLangCode,
        languageName: _targetLangName,
        sourceLanguage: _effectiveSourceLanguage,
        itemsPerLesson: _itemsPerLesson,
        preferredInteractionTypes: _preferredTypes.toList(growable: false),
        focusItems: _focusCtrl.text,
        presetId: _presetId,
        designBrief: _briefCtrl.text,
        grounded: _grounded,
        cancelToken: token,
      );
    }

    try {
      final outline = await fetchOutline();
      if (!mounted) return;
      setState(() => _previewingOutline = false);
      final approved = await showAiOutlineReviewSheet(
        context,
        initialOutline: outline,
        onRegenerateOutline: fetchOutline,
      );
      if (approved == null || !mounted) return;
      await _enqueueCustomCourse(approvedOutline: approved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewingOutline = false;
        _error = AppStrings.aiPracticeEnqueueFailed(e);
      });
    } finally {
      if (identical(_outlineCancelToken, token)) {
        _outlineCancelToken = null;
      }
    }
  }

  Future<void> _enqueueCustomCourse({
    Map<String, dynamic>? approvedOutline,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queue = context.read<AiPracticeJobQueue>();
      await queue.startCustomCourse(
        topic: _topicCtrl.text,
        level: _level,
        unitCount: _units,
        lessonsPerUnit: _lessons,
        template: _template,
        languageCode: _targetLangCode,
        languageName: _targetLangName,
        sourceLanguage: _effectiveSourceLanguage,
        itemsPerLesson: _itemsPerLesson,
        preferredInteractionTypes: _preferredTypes.toList(growable: false),
        focusItems: _focusCtrl.text,
        presetId: _presetId,
        designBrief: _briefCtrl.text,
        grounded: _grounded,
        explanationRequested: _explanationRequested,
        approvedOutline: approvedOutline,
      );
      if (!mounted) return;
      await Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.aiPracticeEnqueueFailed(e);
      });
    }
  }

  Future<void> _start() async {
    if (_customMode) {
      if (_topicCtrl.text.trim().isEmpty) {
        setState(() => _error = AppStrings.aiPracticeTopicRequired);
        return;
      }
      await _enqueueCustomCourse();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queue = context.read<AiPracticeJobQueue>();
      await queue.startPractice(source: _source, level: _level);
      if (!mounted) return;
      await Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.aiPracticeEnqueueFailed(e);
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
        const TurnaIcon(
          TurnaIconId.warning,
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              const TurnaIcon(
                TurnaIconId.check,
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
