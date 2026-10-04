// Package imports:
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

/// Whether this build targets the OpenHarmony companion app.
///
/// Matched **by name, not by enum value**: `TargetPlatform.ohos` only exists
/// in the OHOS engine fork, and `pubspec.yaml` applies its `dependency_overrides`
/// unconditionally — an override cannot be conditioned on the platform. So a
/// host-side build compiles this exact file without `TargetPlatform.ohos`, and
/// the constant would be a compile error. `.name` is a plain string on every
/// SDK; `'ohos'` simply never matches on Android/iOS. The same constraint is
/// what forced the vendor-side ports in `third_party/flutter/`.
///
/// Every OHOS capability check goes through here. The alternative — each
/// caller writing its own `defaultTargetPlatform` comparison — is exactly how a
/// companion build ends up half-wired: one site checks and the next does not.
bool get isHarmonyOsTarget => defaultTargetPlatform.name == 'ohos';

/// Features the OpenHarmony companion build does not ship.
///
/// Scoped out by ADR 0047: the build covers course, SRS, review, dictionary and
/// settings/backup, and explicitly excludes the faithful Official Anki reviewer
/// and remote (WebDAV) backup.
///
/// The exclusions are not stylistic. Each one is a capability the platform
/// genuinely lacks, and each was verified on device rather than assumed:
///
/// - **officialAnki** — the shared catalog is a `sqlite3` FFI database and OHOS
///   ships no `libsqlite3.so`, so the engine cannot be opened at all.
/// - **remoteBackup** — no WebDAV client on the platform. The service is
///   registered unconditionally, so without an explicit check the settings page
///   offers a complete, working-looking WebDAV form that fails on submit.
///
/// Audio and text-to-speech are deliberately **not** listed here any more. Both
/// used to be, on the grounds that `audioplayers` and `flutter_tts` ship no OHOS
/// plugin. They are now served by Turna's own ArkTS channels (`AudioPlugin.ets`
/// and `TtsPlugin.ets`), so continuing to report them as degraded would disable
/// a feature that works — and would hide a real regression behind a "known
/// limitation" label.
///
/// Declared as one set rather than a boolean per feature so the UI has a single
/// place to ask, and so adding a degradation is a one-line change here instead
/// of a hunt through the views.
enum OhosDegradation {
  officialAnki,
  remoteBackup,
}

/// Degradations that apply to the running build. Empty everywhere but OHOS.
Set<OhosDegradation> get activeDegradations =>
    isHarmonyOsTarget ? OhosDegradation.values.toSet() : const <OhosDegradation>{};

/// Whether [feature] is unavailable on this build. Prefer this over
/// [isHarmonyOsTarget] at call sites: it keeps the reason next to the
/// consequence, so a reader sees *why* an affordance is disabled rather than
/// having to go and look up which platform this is.
bool isDegraded(OhosDegradation feature) =>
    activeDegradations.contains(feature);
