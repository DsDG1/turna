/// Result of a best-effort media directory deletion.
///
/// A locked file (audio player, WebView) must never abort an uninstall saga,
/// so failures are collected here instead of thrown. Leftovers are expected
/// to be retried by the orphan sweep on a later app start.
class AnkiMediaDeleteReport {
  final int deletedFiles;
  final int remainingFiles;
  final List<String> remainingPaths;
  final List<String> remainingDirectories;

  const AnkiMediaDeleteReport({
    this.deletedFiles = 0,
    this.remainingFiles = 0,
    this.remainingPaths = const <String>[],
    this.remainingDirectories = const <String>[],
  });

  bool get fullyDeleted =>
      remainingFiles == 0 &&
      remainingPaths.isEmpty &&
      remainingDirectories.isEmpty;
}
