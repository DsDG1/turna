// Project imports:
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/local_reminder_service.dart';

/// Resets every learning-related tunable to its factory default in one
/// transactional sweep: TTS speed, daily reminder (+ OS schedule), FSRS
/// retention, Anki daily limits and the daily-challenge inclusion.
///
/// [notResetScopes] is the single source of truth for what this command
/// NEVER touches — the confirmation dialog copies it verbatim so the UI
/// promise and the implementation cannot drift apart.
class ResetLearningSettingsCommand {
  const ResetLearningSettingsCommand();

  /// Human-readable list of everything this reset does NOT touch. Shown
  /// verbatim in the confirmation dialog.
  static const List<String> notResetScopes = <String>[
    '学习进度与课程数据',
    '目标语言、界面语言、主题与无障碍设置',
    '音效与触觉反馈开关',
    '错题本、成就、宝石与装扮',
    'FSRS 自定义权重（如已优化）',
  ];

  Future<SettingsOperationResult> execute() async {
    final settings = getIt<SettingsProvider>();
    final audio = getIt<AudioController>();
    final reminder = getIt<LocalReminderService>();
    final anki = getIt<AnkiDeckManager>();

    try {
      // Reminder first: only after the OS schedule accepts "disabled" do we
      // commit the preference (UpdateDailyReminderCommand semantics).
      await reminder.applyFromSettings(
          enabled: false, time: settings.dailyReminderTime);
      await settings.resetLearningDefaults();
      audio.setTtsSpeed(settings.ttsSpeed);
      await anki.resetLearningDefaults();
    } on Object catch (error) {
      return SettingsOperationFailure(
        code: 'learningReset.failed',
        userMessage: '部分设置重置失败，请重试。${_brief(error)}',
        retryable: true,
      );
    }
    return const SettingsOperationSuccess();
  }

  static String _brief(Object error) {
    final firstLine = error.toString().split('\n').first;
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }
}
