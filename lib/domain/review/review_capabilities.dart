/// Capabilities supported by a review source/ledger.
///
/// If a capability is false, the UI must hide or disable the corresponding action
/// rather than failing silently or falling back to an unrelated database.
class ReviewCapabilities {
  final bool canSchedule;
  final bool canUndo;
  final bool canSuspend;
  final bool canBrowse;
  final bool canUninstall;
  final bool canRenderOriginalTemplate;

  const ReviewCapabilities({
    this.canSchedule = true,
    this.canUndo = true,
    this.canSuspend = true,
    this.canBrowse = true,
    this.canUninstall = true,
    this.canRenderOriginalTemplate = false,
  });

  /// Standard course vocab capabilities.
  static const standardCourse = ReviewCapabilities(
    canSchedule: true,
    canUndo: true,
    canSuspend: true,
    canBrowse: false,
    canUninstall: false,
    canRenderOriginalTemplate: false,
  );

  /// Legacy Anki deck capabilities.
  static const legacyAnki = ReviewCapabilities(
    canSchedule: true,
    canUndo: true,
    canSuspend: true,
    canBrowse: true,
    canUninstall: true,
    canRenderOriginalTemplate: true,
  );

  /// Official Anki deck capabilities.
  static const officialAnki = ReviewCapabilities(
    canSchedule: true,
    canUndo: true,
    canSuspend: true,
    // Official management repositories are not wired into the public hub yet.
    // Keep these actions unavailable instead of falling through to Legacy DAO.
    canBrowse: false,
    canUninstall: false,
    canRenderOriginalTemplate: true,
  );
}
