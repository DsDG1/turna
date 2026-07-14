// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/auth/local_user.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

class SettingsAccountTile extends StatelessWidget {
  const SettingsAccountTile({super.key});

  @override
  Widget build(BuildContext context) {
    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (context, user) {
        final displayName = user.displayName ?? 'Learner';
        final email = user.email ?? '';
        final languageProvider = context.watch<LanguageProvider>();

        return SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 28,
                      color: VarnamalaTheme.peacockTeal,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: VarnamalaTheme.textHintColor(context),
                                ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: VarnamalaTheme.peacockTeal
                                .withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(VarnamalaTheme.radiusRound),
                          ),
                          child: Text(
                            languageProvider.selectedLanguage.name.toTitleCase,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: VarnamalaTheme.peacockTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
