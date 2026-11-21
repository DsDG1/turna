// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// 偏好目录深页的分区标题。
class AiConfigSectionHeading extends StatelessWidget {
  const AiConfigSectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Text(title, style: AppTextStyles.sectionTitle(context)),
    );
  }
}

/// 连接状态一行（R14：状态点 + 一句文案，不再是玻璃大卡）。
class AiConfigStatusLine extends StatelessWidget {
  const AiConfigStatusLine({
    super.key,
    required this.isComplete,
    required this.presetLabel,
    required this.modelChatText,
  });

  final bool isComplete;
  final String presetLabel;
  final String modelChatText;

  @override
  Widget build(BuildContext context) {
    final accent = isComplete ? TurnaTheme.brandTeal : TurnaTheme.warning;
    // 合成单条文案：预设与模型作为整体展示，不逐字重复分区控件的取值。
    final subtitle = isComplete
        ? '$presetLabel · $modelChatText'
        : AppStrings.aiConfigStatusHintIncomplete;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete ? accent : null,
            border: isComplete ? null : Border.all(color: accent, width: 2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Text(
          isComplete
              ? AppStrings.aiConfigStatusConfigured
              : AppStrings.aiConfigStatusNotConfigured,
          style: AppTextStyles.cardTitle(context).copyWith(fontSize: 15),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable Base URL for the custom preset; read-only value row for presets.
class AiConfigBaseUrlBlock extends StatelessWidget {
  const AiConfigBaseUrlBlock({
    super.key,
    required this.isCustom,
    required this.controller,
    required this.errorText,
    required this.presetBaseUrl,
    required this.onChanged,
  });

  final bool isCustom;
  final TextEditingController controller;
  final String? errorText;
  final String presetBaseUrl;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isCustom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            decoration: aiSheetInputDecoration(
              context,
              hint: AppStrings.settingsBaseUrlHint,
            ),
            onChanged: onChanged,
          ),
          if (errorText != null) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              errorText!,
              style: AppTextStyles.captionSm(context)
                  .copyWith(color: TurnaTheme.error),
            ),
          ],
        ],
      );
    }
    // 预设地址：label 左、值右（长地址省略），不可编辑也不带 chevron。
    return Row(
      children: [
        Text(
          AppStrings.settingsBaseUrlLabel,
          style: AppTextStyles.bodyText(context)
              .copyWith(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            presetBaseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodyText(context).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: TurnaTheme.brandTeal,
            ),
          ),
        ),
      ],
    );
  }
}

/// API key input. Owns the obscure/visible toggle locally so toggling only
/// rebuilds this field. The hint is computed by the caller — the stored key
/// is never echoed into the editable content.
class AiConfigApiKeyField extends StatefulWidget {
  const AiConfigApiKeyField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<AiConfigApiKeyField> createState() => _AiConfigApiKeyFieldState();
}

class _AiConfigApiKeyFieldState extends State<AiConfigApiKeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      decoration: aiSheetInputDecoration(
        context,
        hint: widget.hint,
        suffixIcon: IconButton(
          tooltip: _obscure
              ? AppStrings.commonShowPassword
              : AppStrings.commonHidePassword,
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: TurnaTheme.textHintColor(context),
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Quick-pick chips for the preset's supported chat models.
class AiConfigModelQuickPick extends StatelessWidget {
  const AiConfigModelQuickPick({
    super.key,
    required this.models,
    required this.selectedModel,
    required this.onSelected,
  });

  final List<String> models;
  final String selectedModel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final model in models)
            TurnaFilterChip(
              label: model,
              selected: selectedModel == model,
              onSelected: (_) => onSelected(model),
            ),
        ],
      ),
    );
  }
}

/// Test-connection + save action band with the probe status readout. Owns the
/// probing/result state so the spinner only rebuilds this section.
class AiConfigConnectionTestSection extends StatefulWidget {
  const AiConfigConnectionTestSection({
    super.key,
    required this.configGetter,
    required this.onSave,
  });

  /// Effective draft (typed key overrides stored) — probed, never persisted.
  final AiEngineConfig Function() configGetter;
  final VoidCallback onSave;

  @override
  State<AiConfigConnectionTestSection> createState() =>
      AiConfigConnectionTestSectionState();
}

class AiConfigConnectionTestSectionState
    extends State<AiConfigConnectionTestSection> {
  bool _probing = false;
  ({bool ok, int latencyMs, String errorCategory})? _probeResult;

  /// Drop the last probe outcome (config underneath changed).
  void clearResult() {
    if (mounted) setState(() => _probeResult = null);
  }

  Future<void> _testConnection() async {
    final draft = widget.configGetter();
    if (!draft.isComplete) return;
    setState(() => _probing = true);
    try {
      final result = await getIt<AiEngine>().probeConnection(draft);
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (
          ok: result.ok,
          latencyMs: result.latencyMs,
          errorCategory: result.ok ? '' : _classifyProbeError(result.error),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeResult = (
          ok: false,
          latencyMs: 0,
          errorCategory: _classifyProbeError(error.toString()),
        );
      });
    }
  }

  String _classifyProbeError(String message) {
    final m = message.toLowerCase();
    if (m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('deadline')) {
      return AppStrings.aiConfigProbeTimeout;
    }
    if (m.contains('failed host') ||
        m.contains('dns') ||
        m.contains('no address') ||
        m.contains('connection refused')) {
      return AppStrings.aiConfigProbeNetwork;
    }
    if (m.contains('handshake') ||
        m.contains('certificate') ||
        m.contains('tls')) {
      return AppStrings.aiConfigProbeTls;
    }
    if (m.contains('401') ||
        m.contains('403') ||
        m.contains('unauthorized') ||
        m.contains('invalid api key') ||
        m.contains('authentication')) {
      return AppStrings.aiConfigProbeAuth;
    }
    if (m.contains('429') || m.contains('rate limit') || m.contains('quota')) {
      return AppStrings.aiConfigProbeRateLimit;
    }
    if (m.contains('404') || (m.contains('model') && m.contains('not'))) {
      return AppStrings.aiConfigProbeModel;
    }
    if (m.contains('json') || m.contains('format') || m.contains('decode')) {
      return AppStrings.aiConfigProbeFormat;
    }
    return AppStrings.aiConfigProbeUnknown;
  }

  @override
  Widget build(BuildContext context) {
    return SessionActionBand(
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
          if (_probeResult != null) ...[
            _probeStatusRow(context),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    style: aiSheetSecondaryButtonStyle(),
                    onPressed: _probing || !widget.configGetter().isComplete
                        ? null
                        : _testConnection,
                    icon: _probing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: Text(AppStrings.aiHubToolsTestConnection),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SessionPrimaryAction(
                  label: AppStrings.aiConfigSave,
                  onPressed: widget.onSave,
                  trailingIcon: Icons.save_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _probeStatusRow(BuildContext context) {
    final ok = _probeResult!.ok;
    final accent = ok ? TurnaTheme.brandTeal : TurnaTheme.error;
    final text = ok
        ? AppStrings.aiHubToolsTestConnectionOk(_probeResult!.latencyMs)
        : '${AppStrings.aiHubToolsTestConnectionFail}（${_probeResult!.errorCategory}）';
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
          size: 18,
          color: accent,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.captionSm(context).copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (!ok)
          // Copy the (sanitized) endpoint so the user can debug externally.
          IconButton(
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: AppStrings.aiConfigCopyEndpoint,
            icon: Icon(
              Icons.copy_rounded,
              size: 16,
              color: TurnaTheme.textHintColor(context),
            ),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: widget.configGetter().chatCompletionsUrl),
              );
            },
          ),
      ],
    );
  }
}

/// Destructive actions: clear stored key / restore default config.
class AiConfigDangerRow extends StatelessWidget {
  const AiConfigDangerRow({
    super.key,
    required this.onClear,
    required this.onRestore,
  });

  final VoidCallback onClear;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: onClear,
          style: TextButton.styleFrom(
            foregroundColor: TurnaTheme.error,
          ),
          icon: const Icon(Icons.key_off_outlined, size: 18),
          label: Text(AppStrings.aiConfigClearKeyButton),
        ),
        TextButton.icon(
          onPressed: onRestore,
          icon: const Icon(Icons.restore_rounded, size: 18),
          label: Text(AppStrings.aiConfigRestoreDefaultsButton),
        ),
      ],
    );
  }
}

/// Footer note about local-only key storage.
class AiConfigFooterHint extends StatelessWidget {
  const AiConfigFooterHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 13,
          color: TurnaTheme.textHintColor(context),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            AppStrings.settingsAiApiConfigNotSaved,
            style: AppTextStyles.captionSm(context).copyWith(
              fontSize: 12,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Surfaces credential-storage facts the user needs: session-only platforms
/// (key lost on restart), failed migrations (plaintext kept + retry hint), and
/// — the common case — confirmation that the key is encrypted on device and
/// survives a restart.
class AiConfigCredentialSafetyNotice extends StatelessWidget {
  const AiConfigCredentialSafetyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder,
        (AiKeyStorageKind, AiCredentialMigrationStatus, bool)>(
      selector: (_, holder) => (
        holder.keyStorageKind,
        holder.migrationStatus,
        holder.config.apiKey.isNotEmpty,
      ),
      builder: (context, state, _) {
        final (kind, migration, hasKey) = state;
        final isFailure = migration == AiCredentialMigrationStatus.failed;
        final isSession = kind == AiKeyStorageKind.sessionOnly;
        final isPersisted = kind == AiKeyStorageKind.secure && hasKey;
        if (!isFailure && !isSession && !isPersisted) {
          return const SizedBox.shrink();
        }

        final IconData icon;
        final Color accent;
        final String message;
        if (isFailure) {
          icon = Icons.shield_outlined;
          accent = TurnaTheme.error;
          message = AppStrings.aiConfigMigrationPendingNotice;
        } else if (isSession) {
          icon = Icons.shield_outlined;
          accent = TurnaTheme.warning;
          message = AppStrings.aiConfigSessionKeyNotice;
        } else {
          icon = Icons.verified_user_outlined;
          accent = TurnaTheme.brandSky;
          message = AppStrings.aiConfigKeyPersistedNotice;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                  height: 1.4,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 接口与责任边界说明（分区标题 + 三行说明，不包卡）。
///
/// 三句话缺一不可：① 这个页面只接 OpenAI 兼容协议，别的协议填进来必然失败；
/// ② 请求从本机直达用户自己填的服务商，应用不做中转；③ 内容由服务商生成与
/// 处理，准确性/合规/计费归服务商。用户在这里填的是自己的密钥，这三条属于
/// 填写现场必须给出的信息，不能只写在隐私政策里。
class AiConfigEndpointScopeNotice extends StatelessWidget {
  const AiConfigEndpointScopeNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AiConfigSectionHeading(AppStrings.aiConfigScopeTitle),
        _ScopeLine(
          icon: Icons.terminal_rounded,
          text: AppStrings.aiConfigScopeProtocol,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ScopeLine(
          icon: Icons.cloud_upload_outlined,
          text: AppStrings.aiConfigScopeDataFlow,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ScopeLine(
          icon: Icons.gavel_rounded,
          text: AppStrings.aiConfigScopeLiability,
        ),
      ],
    );
  }
}

class _ScopeLine extends StatelessWidget {
  const _ScopeLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 15,
            color: TurnaTheme.accentOnCard(context, TurnaTheme.brandSky),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.captionSm(context)
                .copyWith(height: 1.45, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
