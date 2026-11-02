import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

String? ttsFailureMessage(TtsSpeakResult result) {
  if (result.source != TtsSpeakSource.failed) return null;
  return switch (result.failureReason) {
    TtsFailureReason.voiceMissing => AppStrings.ttsFailureVoiceMissing,
    TtsFailureReason.engineUnavailable => AppStrings.ttsFailureEngineUnavailable,
    TtsFailureReason.synthesisFailed => AppStrings.ttsFailureSynthesis,
    TtsFailureReason.timeout => AppStrings.ttsFailureTimeout,
    TtsFailureReason.emptyText => AppStrings.ttsFailureEmptyText,
    TtsFailureReason.unknown || null => AppStrings.ttsFailureUnknown,
  };
}

void showTtsFailureFeedback(BuildContext context, TtsSpeakResult result) {
  final message = ttsFailureMessage(result);
  if (message == null || !context.mounted) return;
  final opensSettings = result.failureReason == TtsFailureReason.voiceMissing ||
      result.failureReason == TtsFailureReason.engineUnavailable;
  TurnaSnackBar.maybeShow(
    context,
    message,
    duration: const Duration(seconds: 4),
    action: opensSettings
        ? SnackBarAction(
            label: AppStrings.ttsOpenSettingsAction,
            onPressed: () => unawaited(
              getIt<TtsAvailabilityChecker>().openSystemTtsSettings(),
            ),
          )
        : null,
  );
}
