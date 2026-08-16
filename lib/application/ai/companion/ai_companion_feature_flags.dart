/// One place to gate companion rollouts without scattering booleans through
/// pages and providers. Defaults are on for the completed local-first stack;
/// remote configuration can replace this immutable object later.
class AiCompanionFeatureFlags {
  const AiCompanionFeatureFlags({
    this.durableSessions = true,
    this.evidenceProfile = true,
    this.hintLadder = true,
    this.todayPlan = true,
    this.courseCitations = true,
    this.learningNotes = true,
    this.offlineRetrieval = true,
    this.roleplayRecap = true,
  });

  final bool durableSessions;
  final bool evidenceProfile;
  final bool hintLadder;
  final bool todayPlan;
  final bool courseCitations;
  final bool learningNotes;
  final bool offlineRetrieval;
  final bool roleplayRecap;
}
