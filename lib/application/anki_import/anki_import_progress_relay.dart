import 'package:turna/application/anki_import/anki_import_official_flow.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/v2/official_commit_progress.dart';
import 'package:turna/l10n/app_strings.dart';

/// Local phase labels for the import wizard. Native polling is suppressed
/// while one of these labels is on screen.
class AnkiImportProgressRelay {
  AnkiImportProgressRelay({
    required this.readState,
    required this.emit,
  });

  final AnkiImportWizardState Function() readState;
  final void Function(AnkiImportWizardState state) emit;

  bool _suppress = false;

  bool get suppressed => _suppress;

  void reset() => _suppress = false;

  void showArranging() {
    _suppress = true;
    final current = readState();
    if (current is! AnkiImportParsing) return;
    emit(current.copyWith(
      stage: AppStrings.ankiProgressRecognize,
      clearProgress: true,
    ));
  }

  void onCommit(OfficialCommitPhase phase, int? current, int? total) {
    final label = switch (phase) {
      OfficialCommitPhase.indexing => AppStrings.ankiProgressIndexing,
      OfficialCommitPhase.arrangingTree => AppStrings.ankiProgressArrangeTree,
      OfficialCommitPhase.writingTree => AppStrings.ankiProgressCourse,
      OfficialCommitPhase.locking => AppStrings.ankiProgressLocking,
    };
    showCommit(label, current: current, total: total);
  }

  void showCommit(String label, {int? current, int? total}) {
    _suppress = true;
    final state = readState();
    if (state is! AnkiImportCommitting) return;
    final count = ankiImportCountLabel(current, total);
    emit(state.copyWith(
      message: label,
      stage: count,
      clearStage: count == null,
      progressCurrent: current,
      progressTotal: total,
      clearProgress: true,
    ));
  }
}
