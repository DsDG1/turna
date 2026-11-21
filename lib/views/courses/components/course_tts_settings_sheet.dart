// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// Bottom sheet for a single course's smart-TTS settings: the auto-read
/// toggle and the translation/native language used as the Latin-text fallback.
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.courseTtsSettingsTitle} · ${widget.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.courseTtsAutoReadTitle),
              subtitle: Text(
                AppStrings.courseTtsAutoReadSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
              value: _autoRead,
              onChanged: (value) async {
                setState(() => _autoRead = value);
                await widget.settings.setAutoReadOnTapFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.courseTtsNativeLangTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              AppStrings.courseTtsNativeLangSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _nativeLang,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final opt in _nativeLangOptions)
                  DropdownMenuItem(
                    value: opt,
                    child: Text(AppStrings.ttsNativeLanguageLabel(opt)),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _nativeLang = value);
                await widget.settings
                    .setNativeLanguageCodeFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.dialogClose),
            ),
          ],
        ),
      ),
    );
  }
}
