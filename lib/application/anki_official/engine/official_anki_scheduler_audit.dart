/// Runtime counters for official vs Turna write ownership.
///
/// Static grep is not a substitute. Tests and UI paths increment these.
class OfficialAnkiSchedulerAudit {
  OfficialAnkiSchedulerAudit._();

  static var officialSchedulerAnswers = 0;
  static var officialSchedulerUndo = 0;
  static var officialSchedulerRedo = 0;
  static var turnaSrsWritesFromOfficialPath = 0;
  static var legacyCallsFromOfficialPath = 0;
  static var courseProjectionWritesDuringReview = 0;

  static void reset() {
    officialSchedulerAnswers = 0;
    officialSchedulerUndo = 0;
    officialSchedulerRedo = 0;
    turnaSrsWritesFromOfficialPath = 0;
    legacyCallsFromOfficialPath = 0;
    courseProjectionWritesDuringReview = 0;
  }

  static Map<String, int> snapshot() => <String, int>{
        'officialSchedulerAnswers': officialSchedulerAnswers,
        'officialSchedulerUndo': officialSchedulerUndo,
        'officialSchedulerRedo': officialSchedulerRedo,
        'turnaSrsWritesFromOfficialPath': turnaSrsWritesFromOfficialPath,
        'legacyCallsFromOfficialPath': legacyCallsFromOfficialPath,
        'courseProjectionWritesDuringReview':
            courseProjectionWritesDuringReview,
      };
}
