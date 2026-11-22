// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_controls.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Opens the per-course smart-TTS settings sheet using the unified 4px
/// [showTurnaSheet] container.
Future<void> showCourseTtsSettingsSheet(
  BuildContext context, {
  required String scope,
  required String name,
  required SettingsProvider settings,
}) {
  return showTurnaSheet<void>(
    context: context,
    title: AppStrings.courseTtsSettingsTitle,
    subtitle: name,
    body: CourseTtsSettingsSheet(scope: scope, name: name, settings: settings),
    actions: [
      TurnaSheetAction(
        label: AppStrings.dialogClose,
        primary: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// Body for a single course's smart-TTS settings: the auto-read toggle and
/// the translation/native language used as the Latin-text fallback.
class CourseTtsSettingsSheet extends StatefulWidget {
  final String scope;
  final String name;
  final SettingsProvider settings;

  const CourseTtsSettingsSheet({
    super.key,
    required this.scope,
    required this.name,
    required this.settings,
  });

  @override
  State<CourseTtsSettingsSheet> createState() => _CourseTtsSettingsSheetState();
}

class _CourseTtsSettingsSheetState extends State<CourseTtsSettingsSheet> {
  static const _nativeLangOptions = <String>[
    'en',
    'zh',
    'tr',
    'ru',
    'ar',
    'es',
    'fr',
    'de',
    'ja',
    'ko',
    'pt',
    'it',
    'vi',
    'id',
  ];

  late bool _autoRead;
  late String _nativeLang;

  @override
  void initState() {
    super.initState();
    _autoRead = widget.settings.autoReadOnTapFor(widget.scope);
    _nativeLang = widget.settings.nativeLanguageCodeFor(widget.scope);
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: TurnaTheme.borderRadius,
      borderSide: BorderSide(color: TurnaTheme.dividerBg(context)),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.sm,
        AppSpacing.pageMargin,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.courseTtsAutoReadTitle,
                      style: AppTextStyles.cardTitle(context),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AppStrings.courseTtsAutoReadSubtitle,
                      style: AppTextStyles.captionSm(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              TurnaSwitch(
                value: _autoRead,
                onChanged: (value) async {
                  setState(() => _autoRead = value);
                  await widget.settings.setAutoReadOnTapFor(
                    widget.scope,
                    value,
                  );
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(height: 1, color: TurnaTheme.dividerBg(context)),
          ),
          Text(
            AppStrings.courseTtsNativeLangTitle,
            style: AppTextStyles.cardTitle(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.courseTtsNativeLangSubtitle,
            style: AppTextStyles.captionSm(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _nativeLang,
            icon: TurnaIcon(
              TurnaIconId.chevronDown,
              size: 18,
              color: TurnaTheme.textSecondaryColor(context),
            ),
            decoration: InputDecoration(
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(
                  color: TurnaTheme.brandTeal,
                  width: 1.5,
                ),
              ),
              isDense: true,
            ),
            items: [
              for (final opt in _nativeLangOptions)
                DropdownMenuItem(
                  value: opt,
                  child: Text(
                    AppStrings.ttsNativeLanguageLabel(opt),
                    style: AppTextStyles.bodyText(context),
                  ),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _nativeLang = value);
              await widget.settings.setNativeLanguageCodeFor(
                widget.scope,
                value,
              );
            },
          ),
        ],
      ),
    );
  }
}
