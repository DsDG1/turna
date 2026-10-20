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
/// - **officialAnki** — two separate gaps, and only one of them is the reason
///   this entry exists:
///   1. The shared catalog (`OfficialAnkiDatabase`) is a `sqlite3` FFI database
///      and the platform ships no `libsqlite3.so`, so it cannot be opened.
///   2. The engine itself is **not** blocked — its SQLite is `bundled` and
///      statically linked into `libturna_anki.so`, verified on device (ADR 0046).
///      What is missing is packaging, the catalog override, and the ArkTS
///      reviewer. ADR 0050 authorises all of them; this entry is removed by the
///      wiring batch, not before.
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
/// `officialAnki` was removed on the same grounds, one step later: ADR 0050
/// §6 steps 1–3 made the engine and the shared catalog both work on hardware
/// (`runtimeOk=true reason=ready`, `catalog=ok sqlite=3.49.2`), so a
/// degradation that disables the import entry point now disables working
/// functionality. What is still missing is the faithful renderer, and that
/// fails loudly inside the reviewer rather than by hiding the entry point —
/// see `OfficialAnkiReviewerView`.
///
/// Declared as one set rather than a boolean per feature so the UI has a single
/// place to ask, and so adding a degradation is a one-line change here instead
/// of a hunt through the views.
enum OhosDegradation {
  remoteBackup,
}

/// Degradations that apply to the running build. Empty everywhere but OHOS.
Set<OhosDegradation> get activeDegradations => isHarmonyOsTarget
    ? OhosDegradation.values.toSet()
    : const <OhosDegradation>{};

/// Whether [feature] is unavailable on this build. Prefer this over
/// [isHarmonyOsTarget] at call sites: it keeps the reason next to the
/// consequence, so a reader sees *why* an affordance is disabled rather than
/// having to go and look up which platform this is.
bool isDegraded(OhosDegradation feature) =>
    activeDegradations.contains(feature);
