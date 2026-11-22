// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_normalizer.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Opens the interactive "审核课程大纲" bottom sheet for two-step custom course
/// generation. Returns the edited outline map on confirm, or `null` if
/// dismissed.
Future<Map<String, dynamic>?> showAiOutlineReviewSheet(
  BuildContext context, {
  required Map<String, dynamic> initialOutline,
  Future<Map<String, dynamic>> Function()? onRegenerateOutline,
}) {
  return showTurnaSheet<Map<String, dynamic>>(
    context: context,
    title: AppStrings.aiOutlineReviewTitle,
    subtitle: AppStrings.aiOutlineReviewSubtitle,
    isScrollControlled: true,
    body: AiOutlineReviewSheet(
      initialOutline: initialOutline,
      onRegenerateOutline: onRegenerateOutline,
    ),
  );
}

class AiOutlineReviewSheet extends StatefulWidget {
  const AiOutlineReviewSheet({
    super.key,
    required this.initialOutline,
    this.onRegenerateOutline,
  });

  final Map<String, dynamic> initialOutline;
  final Future<Map<String, dynamic>> Function()? onRegenerateOutline;

  @override
  State<AiOutlineReviewSheet> createState() => _AiOutlineReviewSheetState();
}

class _AiOutlineReviewSheetState extends State<AiOutlineReviewSheet> {
  static const List<(String, String)> _lessonTemplates = [
    ('intro', '认识新词'),
    ('practice', '巩固练习'),
    ('review', '复习'),
    ('reading', '阅读理解'),
    ('dialogue', '情景对话'),
    ('guide', '知识导览'),
    ('mastery', '综合测验'),
  ];

  static const int _maxLessonsPerUnit = 8;

  late Map<String, dynamic> _outline;
  final List<_EditableUnit> _units = <_EditableUnit>[];
  final List<Map<String, dynamic>> _words = <Map<String, dynamic>>[];

  final TextEditingController _newTermCtrl = TextEditingController();
  final TextEditingController _newTransCtrl = TextEditingController();
  bool _showAddWord = false;
  bool _regenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOutline(widget.initialOutline);
  }

  @override
  void dispose() {
    _disposeUnits();
    _newTermCtrl.dispose();
    _newTransCtrl.dispose();
    super.dispose();
  }

  void _disposeUnits() {
    for (final unit in _units) {
      unit.dispose();
    }
    _units.clear();
  }

  void _loadOutline(Map<String, dynamic> raw) {
    _disposeUnits();
    _outline = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    _words.clear();
    final rawWords = _outline['words'] is List
        ? _outline['words'] as List
        : (_outline['resources'] is Map &&
                (_outline['resources'] as Map)['words'] is List)
            ? (_outline['resources'] as Map)['words'] as List
            : const <dynamic>[];
    for (final item in rawWords) {
      if (item is Map) {
        _words.add(Map<String, dynamic>.from(item));
      }
    }
    final rawUnits = _outline['units'];
    if (rawUnits is List) {
      for (var ui = 0; ui < rawUnits.length; ui++) {
        final rawUnit = rawUnits[ui];
        if (rawUnit is! Map) continue;
        final unitMap = Map<String, dynamic>.from(rawUnit);
        final lessons = <_EditableLesson>[];
        final rawLessons = unitMap['lessons'];
        if (rawLessons is List) {
          for (var li = 0; li < rawLessons.length; li++) {
            final rawLesson = rawLessons[li];
            if (rawLesson is! Map) continue;
            final lessonMap = Map<String, dynamic>.from(rawLesson);
            final rawTemplate = lessonMap['template']?.toString() ?? 'practice';
            final template = _lessonTemplates.any((t) => t.$1 == rawTemplate)
                ? rawTemplate
                : 'practice';
            lessons.add(
              _EditableLesson(
                raw: lessonMap,
                id: lessonMap['id']?.toString() ?? 'lesson-${ui + 1}-${li + 1}',
                nameController: TextEditingController(
                  text: lessonMap['name']?.toString() ?? '第 ${li + 1} 课',
                ),
                template: template,
              ),
            );
          }
        }
        _units.add(
          _EditableUnit(
            raw: unitMap,
            id: unitMap['id']?.toString() ?? 'unit-${ui + 1}',
            nameController: TextEditingController(
              text: unitMap['name']?.toString() ?? '第 ${ui + 1} 单元',
            ),
            lessons: lessons,
          ),
        );
      }
    }
  }

  int get _totalLessons =>
      _units.fold<int>(0, (sum, unit) => sum + unit.lessons.length);

  String _templateLabel(String template) {
    for (final (code, label) in _lessonTemplates) {
      if (code == template) return label;
    }
    return AppStrings.aiPracticeTemplatePractice;
  }

  void _addWord() {
    final term = _newTermCtrl.text.trim();
    final translation = _newTransCtrl.text.trim();
    if (term.isEmpty) return;
    final usedIds = <String>{
      for (final w in _words)
        if (w['id'] != null) w['id'].toString(),
    };
    var idx = _words.length + 1;
    var candidate = 'w-custom-$idx';
    while (usedIds.contains(candidate)) {
      idx++;
      candidate = 'w-custom-$idx';
    }
    setState(() {
      _words.add({
        'id': candidate,
        'term': term,
        'translation': translation.isEmpty ? term : translation,
      });
      _newTermCtrl.clear();
      _newTransCtrl.clear();
      _showAddWord = false;
    });
  }

  void _removeWord(int index) {
    if (index < 0 || index >= _words.length) return;
    setState(() {
      _words.removeAt(index);
    });
  }

  void _addLesson(_EditableUnit unit, int unitIndex) {
    if (unit.lessons.length >= _maxLessonsPerUnit) return;
    final usedIds = <String>{
      for (final u in _units)
        for (final l in u.lessons) l.id,
    };
    var idx = unit.lessons.length + 1;
    var id = 'lesson-u${unitIndex + 1}-$idx';
    while (usedIds.contains(id)) {
      idx++;
      id = 'lesson-u${unitIndex + 1}-$idx';
    }
    final defaultWordIds = _words
        .take(4)
        .map((w) => w['id']?.toString())
        .whereType<String>()
        .toList();
    setState(() {
      unit.lessons.add(
        _EditableLesson(
          raw: {
            'id': id,
            'name': '第 $idx 课',
            'template': 'practice',
            'targetWordIds': defaultWordIds,
            'content': AiPracticeNormalizer.emptyContentFor('practice'),
          },
          id: id,
          nameController: TextEditingController(text: '第 $idx 课'),
          template: 'practice',
        ),
      );
    });
  }

  void _removeLesson(_EditableUnit unit, int lessonIndex) {
    if (unit.lessons.length <= 1) return;
    setState(() {
      final removed = unit.lessons.removeAt(lessonIndex);
      removed.dispose();
    });
  }

  Future<void> _pickTemplate(_EditableLesson lesson) async {
    final chosen = await showTurnaSheet<String>(
      context: context,
      title: AppStrings.aiPracticeCustomTemplate,
      body: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _lessonTemplates.length; i++)
              InkWell(
                onTap: () => Navigator.of(context).pop(_lessonTemplates[i].$1),
                child: Container(
                  decoration: i < _lessonTemplates.length - 1
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: TurnaTheme.dividerBg(context),
                            ),
                          ),
                        )
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageMargin,
                    vertical: AppSpacing.md + 2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _lessonTemplates[i].$2,
                          style: AppTextStyles.bodyText(context).copyWith(
                            fontWeight:
                                _lessonTemplates[i].$1 == lesson.template
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_lessonTemplates[i].$1 == lesson.template)
                        const TurnaIcon(
                          TurnaIconId.check,
                          size: 18,
                          color: TurnaTheme.brandTeal,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => lesson.template = chosen);
    }
  }

  Future<void> _regenerate() async {
    final regen = widget.onRegenerateOutline;
    if (regen == null || _regenerating) return;
    setState(() {
      _regenerating = true;
      _error = null;
    });
    try {
      final next = await regen();
      if (!mounted) return;
      setState(() {
        _loadOutline(next);
        _regenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _regenerating = false;
        _error = '$e';
      });
    }
  }

  Map<String, dynamic> _buildEditedOutline() {
    final result = jsonDecode(jsonEncode(_outline)) as Map<String, dynamic>;
    result['words'] = [
      for (final word in _words) Map<String, dynamic>.from(word),
    ];
    if (result['resources'] is Map) {
      final resources = Map<String, dynamic>.from(result['resources'] as Map);
      resources['words'] = result['words'];
      result['resources'] = resources;
    }

    final validWordIds = <String>{
      for (final w in _words)
        if (w['id'] != null) w['id'].toString(),
    };

    final builtUnits = <Map<String, dynamic>>[];
    for (var ui = 0; ui < _units.length; ui++) {
      final unit = _units[ui];
      final unitMap = Map<String, dynamic>.from(unit.raw);
      final name = unit.nameController.text.trim();
      unitMap['id'] = unit.id;
      unitMap['name'] = name.isEmpty ? '第 ${ui + 1} 单元' : name;
      final builtLessons = <Map<String, dynamic>>[];
      for (var li = 0; li < unit.lessons.length; li++) {
        final lesson = unit.lessons[li];
        final lessonMap = Map<String, dynamic>.from(lesson.raw);
        final lessonName = lesson.nameController.text.trim();
        lessonMap['id'] = lesson.id;
        lessonMap['name'] = lessonName.isEmpty ? '第 ${li + 1} 课' : lessonName;
        lessonMap['template'] = lesson.template;
        lessonMap['content'] =
            AiPracticeNormalizer.emptyContentFor(lesson.template);
        final rawIds = lessonMap['targetWordIds'];
        if (rawIds is List) {
          lessonMap['targetWordIds'] = [
            for (final id in rawIds)
              if (id != null && validWordIds.contains(id.toString()))
                id.toString(),
          ];
        }
        builtLessons.add(lessonMap);
      }
      unitMap['lessons'] = builtLessons;
      builtUnits.add(unitMap);
    }
    result['units'] = builtUnits;
    return result;
  }

  void _confirm() {
    if (_totalLessons <= 0) return;
    Navigator.of(context).pop(_buildEditedOutline());
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.78;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWordsSection(context),
                  const SizedBox(height: AppSpacing.lg),
                  _buildUnitsSection(context),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: AppTextStyles.captionSm(context)
                          .copyWith(color: TurnaTheme.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: TurnaTheme.dividerBg(context)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.md,
              AppSpacing.pageMargin,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onRegenerateOutline != null) ...[
                  TextButton.icon(
                    onPressed: _regenerating ? null : _regenerate,
                    icon: _regenerating
                        ? const TurnaLoader.inline(size: 14)
                        : const TurnaIcon(TurnaIconId.refresh, size: 16),
                    label: Text(
                      _regenerating
                          ? AppStrings.aiPracticeGeneratingOutline
                          : AppStrings.aiOutlineRegenerate,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                SessionPrimaryAction(
                  label: AppStrings.aiOutlineConfirmGenerate(_totalLessons),
                  onPressed:
                      _regenerating || _totalLessons == 0 ? null : _confirm,
                  trailingIcon: TurnaIconId.spark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${AppStrings.aiOutlineWordsSection}（${_words.length}）',
                style: AppTextStyles.captionSm(context)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _showAddWord = !_showAddWord),
              icon: const TurnaIcon(TurnaIconId.add, size: 14),
              label: const Text('加词'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
            ),
          ],
        ),
        if (_showAddWord) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTermCtrl,
                  decoration: aiSheetInputDecoration(context, hint: '目标语词汇'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  controller: _newTransCtrl,
                  decoration: aiSheetInputDecoration(context, hint: '释义'),
                  onSubmitted: (_) => _addWord(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: _addWord,
                tooltip: '添加',
                icon: const TurnaIcon(
                  TurnaIconId.check,
                  size: 18,
                  color: TurnaTheme.brandTeal,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        if (_words.isEmpty)
          Text(
            '暂未指定核心词汇（填课时将按主题自动补全）',
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < _words.length; i++)
                InputChip(
                  label: Text(
                    _wordLabel(_words[i]),
                    style: AppTextStyles.captionSm(context),
                  ),
                  onDeleted: () => _removeWord(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
      ],
    );
  }

  String _wordLabel(Map<String, dynamic> word) {
    final term = word['term']?.toString() ?? '';
    final trans = word['translation']?.toString() ?? '';
    if (trans.isEmpty || trans == term) return term;
    return '$term · $trans';
  }

  Widget _buildUnitsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.aiOutlineUnitsSection,
          style: AppTextStyles.captionSm(context)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var ui = 0; ui < _units.length; ui++) ...[
          _buildUnitCard(context, _units[ui], ui),
          if (ui < _units.length - 1) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Widget _buildUnitCard(
    BuildContext context,
    _EditableUnit unit,
    int unitIndex,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: TurnaTheme.dividerBg(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'U${unitIndex + 1}',
                style: AppTextStyles.captionSm(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.brandTeal,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: unit.nameController,
                  style: AppTextStyles.bodyText(context)
                      .copyWith(fontWeight: FontWeight.w600),
                  decoration: aiSheetInputDecoration(context, hint: '单元标题'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var li = 0; li < unit.lessons.length; li++) ...[
            _buildLessonRow(context, unit, unit.lessons[li], li),
            if (li < unit.lessons.length - 1)
              const SizedBox(height: AppSpacing.xs + 2),
          ],
          if (unit.lessons.length < _maxLessonsPerUnit) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addLesson(unit, unitIndex),
                icon: const TurnaIcon(TurnaIconId.add, size: 14),
                label: Text(AppStrings.aiOutlineAddLesson),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLessonRow(
    BuildContext context,
    _EditableUnit unit,
    _EditableLesson lesson,
    int lessonIndex,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: lesson.nameController,
            style: AppTextStyles.bodyText(context).copyWith(fontSize: 14),
            decoration: aiSheetInputDecoration(
              context,
              hint: '第 ${lessonIndex + 1} 课',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ActionChip(
          label: Text(
            _templateLabel(lesson.template),
            style: AppTextStyles.captionSm(context),
          ),
          visualDensity: VisualDensity.compact,
          onPressed: () => _pickTemplate(lesson),
        ),
        if (unit.lessons.length > 1)
          IconButton(
            onPressed: () => _removeLesson(unit, lessonIndex),
            tooltip: AppStrings.aiPracticeDelete,
            visualDensity: VisualDensity.compact,
            icon: TurnaIcon(
              TurnaIconId.delete,
              size: 16,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
      ],
    );
  }
}

class _EditableUnit {
  _EditableUnit({
    required this.raw,
    required this.id,
    required this.nameController,
    required this.lessons,
  });

  final Map<String, dynamic> raw;
  final String id;
  final TextEditingController nameController;
  final List<_EditableLesson> lessons;

  void dispose() {
    nameController.dispose();
    for (final lesson in lessons) {
      lesson.dispose();
    }
  }
}

class _EditableLesson {
  _EditableLesson({
    required this.raw,
    required this.id,
    required this.nameController,
    required this.template,
  });

  final Map<String, dynamic> raw;
  final String id;
  final TextEditingController nameController;
  String template;

  void dispose() {
    nameController.dispose();
  }
}
