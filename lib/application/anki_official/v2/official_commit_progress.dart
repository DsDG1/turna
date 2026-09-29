/// Phases of a v2 commit that run after the native package import returns.
/// The wizard maps these to copy; this file stays free of UI strings.
enum OfficialCommitPhase {
  indexing,
  arrangingTree,
  writingTree,
  locking,
}

/// [current] / [total] are note, card, or row counts for that phase.
/// Either may be null when the phase has no known total yet.
typedef OfficialCommitProgress = void Function(
  OfficialCommitPhase phase,
  int? current,
  int? total,
);
