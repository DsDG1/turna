// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_prompt_catalog.dart';
import 'package:turna/application/ai/ai_prompt_overrides.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 打开「系统提示词」面板。
///
/// 这是只读正文 + 追加自定义的查看器，不是编辑器：默认文本永远不可删改，
/// 用户只能在自己那一段里加要求（原因见 [applyOverride]）。
Future<void> showAiPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const AiPromptSheet(),
  );
}

/// AI 助手 → 系统提示词：看清默认设置，并追加自己的要求。
class AiPromptSheet extends StatefulWidget {
  const AiPromptSheet({super.key, this.initialFeature});

  /// 指定初始功能；为空则从第一个功能（自由问答）开始。
  final AiPromptFeature? initialFeature;

  @override
  State<AiPromptSheet> createState() => _AiPromptSheetState();
}

class _AiPromptSheetState extends State<AiPromptSheet> {
  late AiPromptOverridesStore _store;
  late AiPromptFeature _feature;
  late final TextEditingController _overrideCtrl;

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _store = AiPromptOverridesStore.resolve();
    _feature = widget.initialFeature ?? AiPromptFeature.values.first;
    _overrideCtrl = TextEditingController(text: _store.textFor(_feature));
  }

  @override
  void dispose() {
    _overrideCtrl.dispose();
    super.dispose();
  }

  void _select(AiPromptFeature feature) {
    if (feature == _feature) return;
    // 切功能前先落库，避免把 A 的编辑内容带进 B。
    if (_dirty) _save(silent: true);
    setState(() {
      _feature = feature;
      _dirty = false;
      _overrideCtrl.text = _store.textFor(feature);
    });
  }

  void _save({bool silent = false}) {
    _store.setText(_feature, _overrideCtrl.text);
    setState(() => _dirty = false);
    if (!silent) {
      TurnaSnackBar.maybeShow(context, AppStrings.aiPromptSaved);
    }
  }

  void _reset() {
    _overrideCtrl.text = '';
    _store.clear(_feature);
    setState(() => _dirty = false);
    TurnaSnackBar.maybeShow(context, AppStrings.aiPromptResetDone);
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageProvider>().displayName;
    final prefs = AiExplainPrefsStore.resolve(
      allowEphemeral: true,
    ).snapshot;
    final prompt = AiPromptCatalog.preview(
      feature: _feature,
      language: language,
      prefs: prefs,
      override: _store.textFor(_feature),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 4),
              Text(
                AppStrings.aiPromptSheetIntro,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 12),
              _featureChips(context),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _promptView(context, prompt),
                    const SizedBox(height: 16),
                    _editor(context),
                    const SizedBox(height: 12),
                    _actions(context),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.aiPromptSheetFooter,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
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
        const Icon(Icons.code_rounded, color: TurnaTheme.brandTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.aiPromptSheetTitle,
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

  Widget _featureChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in AiPromptFeature.values)
          _FeatureChip(
            label: f.label,
            selected: f == _feature,
            customised: _store.isOverridden(f),
            onTap: () => _select(f),
          ),
      ],
    );
  }

  Widget _promptView(BuildContext context, String prompt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.aiPromptSheetEffective(_feature.usage),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                      height: 1.4,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: prompt));
                TurnaSnackBar.maybeShow(context, AppStrings.aiPromptCopied);
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: Text(AppStrings.aiPromptCopy),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TurnaTheme.tintLight,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(color: TurnaTheme.glassBorder(context)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              prompt,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final text = _overrideCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.aiPromptCustomTitle,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textPrimaryColor(context),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.aiPromptCustomHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                height: 1.4,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _overrideCtrl,
          minLines: 3,
          maxLines: 6,
          maxLength: kAiPromptOverrideMaxChars,
          onChanged: (_) => setState(() => _dirty = true),
          decoration: InputDecoration(
            hintText: AppStrings.aiPromptCustomPlaceholder,
            filled: true,
            fillColor: TurnaTheme.tintLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
          ),
        ),
        if (text.isEmpty)
          Text(
            AppStrings.aiPromptUsingDefault,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _dirty ? () => _save() : null,
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.brandTeal,
            ),
            child: Text(AppStrings.aiPromptSave),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed:
              _store.isOverridden(_feature) || _overrideCtrl.text.isNotEmpty
                  ? _reset
                  : null,
          child: Text(AppStrings.aiPromptResetDefault),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.label,
    required this.selected,
    required this.customised,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool customised;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal);
    return Material(
      color: selected
          ? TurnaTheme.softTint(context, TurnaTheme.brandTeal)
          : TurnaTheme.tintLight,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            border: Border.all(
              color: selected ? accent : TurnaTheme.glassBorder(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? accent
                          : TurnaTheme.textSecondaryColor(context),
                    ),
              ),
              // 已自定义打点：用户切走再回来能看出哪个功能被改过。
              if (customised) ...[
                const SizedBox(width: 5),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: TurnaTheme.anatolianClay,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
