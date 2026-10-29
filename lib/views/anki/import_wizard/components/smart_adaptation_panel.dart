import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_import/adaptation/ai_card_adaptation_service.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/l10n/app_strings.dart';

/// 导入预览里的「智能适配」区（ADR 0057 §7，plan §13.1）。
///
/// 只负责展示与确认，不自己发请求也不自己写存储：`onGenerate` / `onApply` /
/// `onRestore` 由页面注入。这样这一层可以在没有引擎、没有网络的测试里验证，
/// 而「AI 失败仍能继续导入」由回调的返回值保证。
class SmartAdaptationPanel extends StatefulWidget {
  const SmartAdaptationPanel({
    super.key,
    required this.schemas,
    required this.aiConfigured,
    required this.hasPlan,
    required this.onGenerate,
    required this.onApply,
    required this.onRestore,
  });

  final List<OfficialAnkiProjectionSchema> schemas;
  final bool aiConfigured;
  final bool Function(int notetypeId) hasPlan;
  final Future<CardAdaptationResult> Function(OfficialAnkiProjectionSchema)
      onGenerate;
  final Future<bool> Function(
    OfficialAnkiProjectionSchema schema,
    CardAdaptationPlan plan,
  ) onApply;
  final void Function(OfficialAnkiProjectionSchema schema) onRestore;

  @override
  State<SmartAdaptationPanel> createState() => _SmartAdaptationPanelState();
}

class _SmartAdaptationPanelState extends State<SmartAdaptationPanel> {
  final Map<int, CardAdaptationResult> _results = <int, CardAdaptationResult>{};
  final Set<int> _busy = <int>{};

  @override
  void didUpdateWidget(covariant SmartAdaptationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schemas != widget.schemas) {
      _results.clear();
      _busy.clear();
    }
  }

  Future<void> _generate(OfficialAnkiProjectionSchema schema) async {
    if (_busy.contains(schema.notetypeId)) return;
    setState(() => _busy.add(schema.notetypeId));
    final result = await widget.onGenerate(schema);
    if (!mounted) return;
    setState(() {
      _busy.remove(schema.notetypeId);
      _results[schema.notetypeId] = result;
    });
  }

  Future<void> _apply(CardAdaptationPlan plan, int notetypeId) async {
    final schema = widget.schemas
        .where((candidate) => candidate.notetypeId == notetypeId)
        .firstOrNull;
    if (schema == null) return;
    final applied = await widget.onApply(schema, plan);
    if (!mounted) return;
    if (applied) {
      setState(() => _results.remove(notetypeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schemas.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: TurnaTheme.brandTeal),
              const SizedBox(width: 8),
              Text(
                AppStrings.ankiAdaptationTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.ankiAdaptationHint,
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
          if (!widget.aiConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                AppStrings.ankiAdaptationNotConfigured,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final schema in widget.schemas)
            _SchemaRow(
              key: ValueKey('smart-adaptation-${schema.notetypeId}'),
              schema: schema,
              busy: _busy.contains(schema.notetypeId),
              enabled: widget.aiConfigured,
              result: _results[schema.notetypeId],
              staged: widget.hasPlan(schema.notetypeId),
              onGenerate: () => _generate(schema),
              onApply: (plan) => _apply(plan, schema.notetypeId),
              onRestore: () => widget.onRestore(schema),
            ),
        ],
      ),
    );
  }
}

class _SchemaRow extends StatelessWidget {
  const _SchemaRow({
    super.key,
    required this.schema,
    required this.busy,
    required this.enabled,
    required this.result,
    required this.staged,
    required this.onGenerate,
    required this.onApply,
    required this.onRestore,
  });

  final OfficialAnkiProjectionSchema schema;
  final bool busy;
  final bool enabled;
  final CardAdaptationResult? result;
  final bool staged;
  final VoidCallback onGenerate;
  final Future<void> Function(CardAdaptationPlan plan) onApply;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final accepted = result is CardAdaptationAccepted
        ? result as CardAdaptationAccepted
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            schema.name.isEmpty ? '${schema.notetypeId}' : schema.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TurnaTheme.textPrimaryColor(context),
            ),
          ),
          if (staged)
            Text(
              AppStrings.ankiAdaptationStaged,
              style: const TextStyle(
                fontSize: 12,
                color: TurnaTheme.success,
              ),
            ),
          if (result == null && !staged)
            TextButton(
              key: ValueKey('adaptation-generate-${schema.notetypeId}'),
              onPressed: enabled && !busy ? onGenerate : null,
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppStrings.ankiAdaptationGenerate),
            ),
          if (result != null) ..._resultWidgets(context, accepted),
          if (staged)
            TextButton(
              key: ValueKey('adaptation-restore-${schema.notetypeId}'),
              onPressed: onRestore,
              child: Text(AppStrings.ankiAdaptationRestore),
            ),
        ],
      ),
    );
  }

  List<Widget> _resultWidgets(
    BuildContext context,
    CardAdaptationAccepted? accepted,
  ) {
    final result = this.result;
    if (accepted != null) {
      return <Widget>[
        Text(
          AppStrings.ankiAdaptationPlanLabel(
            accepted.plan.planId,
            accepted.plan.revision,
          ),
          style: TextStyle(
            fontSize: 12,
            color: TurnaTheme.textSecondaryColor(context),
          ),
        ),
        TextButton(
          key: ValueKey('adaptation-apply-${schema.notetypeId}'),
          onPressed: () => onApply(accepted.plan),
          child: Text(AppStrings.ankiAdaptationApply),
        ),
      ];
    }
    if (result is CardAdaptationUnavailable) {
      return <Widget>[
        Text(
          result.reason == 'transport'
              ? AppStrings.ankiAdaptationTransport
              : AppStrings.ankiAdaptationUnavailable,
          style: const TextStyle(fontSize: 12, color: TurnaTheme.textHint),
        ),
      ];
    }
    if (result is CardAdaptationRejected) {
      final message = switch (result.code) {
        'truncated' => AppStrings.ankiAdaptationTruncated,
        _ => AppStrings.ankiAdaptationRejected,
      };
      // 具体原因比「校验未通过」有用：列出前两条本地拒绝的理由。
      final details = [
        for (final issue in result.issues.take(2)) _issueLabel(issue),
      ];
      return <Widget>[
        Text(
          message,
          style: const TextStyle(fontSize: 12, color: TurnaTheme.error),
        ),
        if (details.isNotEmpty)
          Text(
            details.join('；'),
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
      ];
    }
    return const <Widget>[];
  }
}

String _issueLabel(AdaptationIssue issue) {
  // 文案统一收在 AppStrings（字符串表是术语门禁的扫描面，散落在组件里
  // 的中文字面量改口径时容易漏）。
  return switch (issue) {
    AdaptationIssue.schemaVersion => AppStrings.ankiAdaptationIssueSchemaVersion,
    AdaptationIssue.scopeSource => AppStrings.ankiAdaptationIssueScopeSource,
    AdaptationIssue.scopeNotetype => AppStrings.ankiAdaptationIssueScopeNotetype,
    AdaptationIssue.scopeTemplate => AppStrings.ankiAdaptationIssueScopeTemplate,
    AdaptationIssue.unknownBlockKind =>
      AppStrings.ankiAdaptationIssueUnknownBlockKind,
    AdaptationIssue.unknownSelection =>
      AppStrings.ankiAdaptationIssueUnknownSelection,
    AdaptationIssue.fieldOutOfRange =>
      AppStrings.ankiAdaptationIssueFieldOutOfRange,
    AdaptationIssue.unknownExercise =>
      AppStrings.ankiAdaptationIssueUnknownExercise,
    AdaptationIssue.unknownDefaultExercise =>
      AppStrings.ankiAdaptationIssueUnknownDefaultExercise,
    AdaptationIssue.unknownBindingRole =>
      AppStrings.ankiAdaptationIssueUnknownBindingRole,
    AdaptationIssue.unknownFallback => AppStrings.ankiAdaptationIssueUnknownFallback,
    AdaptationIssue.emptyFront => AppStrings.ankiAdaptationIssueEmptyFront,
    AdaptationIssue.answerOnFront => AppStrings.ankiAdaptationIssueAnswerOnFront,
    AdaptationIssue.backOnlyFieldOnFront =>
      AppStrings.ankiAdaptationIssueBackOnlyFieldOnFront,
    AdaptationIssue.allSamplesUnsupported =>
      AppStrings.ankiAdaptationIssueAllSamplesUnsupported,
  };
}
