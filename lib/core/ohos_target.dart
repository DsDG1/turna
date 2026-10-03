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
