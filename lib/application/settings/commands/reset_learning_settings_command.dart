// Project imports:
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/local_reminder_service.dart';

/// Resets every learning-related tunable to its factory default in one sweep:
/// TTS speed, daily reminder (+ OS schedule), FSRS retention, Anki daily
/// limits and the daily-challenge inclusion.
///
/// The sweep is **independent per step**, not transactional: the reminder is
/// applied first (and still gates the rest, because committing "off" while
/// the OS kept a schedule is the one inconsistency worth refusing), but a
/// failure afterwards is reported by step instead of silently discarding the
/// writes that already succeeded.
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

    // Reminder first, and the one step that still aborts: only after the OS
    // accepts "disabled" may the preference be committed
    // (UpdateDailyReminderCommand semantics). Disabling is a no-op — not a
    // failure — on a platform with no notification registrant, so a
    // HarmonyOS build reaches the rest of the sweep.
    try {
      await reminder.applyFromSettings(
          enabled: false, time: settings.dailyReminderTime);
    } on Object catch (error) {
      return SettingsOperationFailure(
        code: 'learningReset.reminderFailed',
        userMessage: '提醒取消失败，设置未重置。${_brief(error)}',
        retryable: true,
      );
    }

    // The remaining steps are independent local writes. One failing must not
    // discard the ones that already landed — the previous all-or-nothing try
    // block reported "部分…失败" while resetting nothing at all.
    final failures = <String>[];
    try {
      await settings.resetLearningDefaults();
    } on Object catch (error) {
      failures.add('学习偏好：${_brief(error)}');
    }
    try {
      audio.setTtsSpeed(settings.ttsSpeed);
    } on Object catch (error) {
      failures.add('朗读语速：${_brief(error)}');
    }
    try {
      await anki.resetLearningDefaults();
    } on Object catch (error) {
      failures.add('记忆卡限额：${_brief(error)}');
    }

    if (failures.isEmpty) return const SettingsOperationSuccess();
    return SettingsOperationFailure(
      code: 'learningReset.partial',
      userMessage: '部分设置重置失败，请重试。${failures.join('；')}',
      retryable: true,
    );
  }

  static String _brief(Object error) {
    final firstLine = error.toString().split('\n').first;
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }
}
