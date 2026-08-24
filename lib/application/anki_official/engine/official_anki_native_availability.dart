import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'official_anki_native_transport.dart';/// Process-wide answer to "is `libturna_anki.so` actually loadable here?".
///
/// The cutover flags default **on**, so routing decisions claim the official
/// engine on Android even when the library is not packaged (wrong-ABI APK,
/// broken release build). Degrading only makes sense when we know the library
/// is physically absent, so the probe dlopens it once and caches the result.
/// Sources already recorded as official never degrade — their data lives in
/// the official collection and has no legacy fallback; those paths stay
/// fail-closed with a diagnostic.
class OfficialAnkiNativeAvailability {
  OfficialAnkiNativeAvailability._();

  static bool? _cached;

  /// Test seam: force the probe result. Production never sets this.
  static bool? debugOverride;

  static bool get current {
    final overridden = debugOverride;
    if (overridden != null) return overridden;
    return _cached ??= _probe();
  }

  static bool _probe() {
    if (Platform.isIOS || Platform.isWindows) return false;
    final resolved = Platform.isAndroid ? 'libturna_anki.so' : null;
    final path = resolved ?? resolveOfficialAnkiLibraryPath();
    if (path == null) {
      _reportUnavailable('no library path resolved');
      return false;
    }
    try {
      final lib = DynamicLibrary.open(path);
      lib.lookup<NativeFunction<Uint32 Function()>>('turna_anki_abi_version');
      return true;
    } on ArgumentError catch (error) {
      _reportUnavailable('$path: $error');
      return false;
    }
  }

  static void _reportUnavailable(String detail) {
    debugPrint(
      '[OfficialAnki] libturna_anki.so not loadable ($detail); '
      'routing new imports/unrecorded sources to the legacy stack',
    );
  }

  /// Resets the cache so the next [current] re-probes. Tests only.
  static void resetForTests() => _cached = null;
}
