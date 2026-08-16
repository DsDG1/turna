// Dart imports:
import 'dart:typed_data';

// Project imports:
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';

typedef OfficialAnkiLibraryOpener = Object Function(String name);

class OfficialAnkiSpikeFfi {
  OfficialAnkiSpikeFfi._();

  static void debugResetCache() {}

  static OfficialAnkiSpikeFfi open({
    bool? isAndroid,
    OfficialAnkiLibraryOpener? openLibrary,
  }) {
    throw const OfficialAnkiSpikeError(
      code: OfficialAnkiSpikeErrorCode.unsupportedPlatform,
      message: 'official Anki native core is only loaded on Android',
    );
  }

  Uint8List takeBuffer(Object result) => Uint8List(0);

  int readAbiVersion() => 0;

  Object createEngine() => 0;

  Object closeEngine(int handle) => 0;

  int resultStatus(Object result) => OfficialAnkiSpikeNativeStatus.backendPanic;
}

OfficialAnkiSpikeError mapOfficialAnkiLoadError(Object error) {
  return OfficialAnkiSpikeError(
    code: OfficialAnkiSpikeErrorCode.unknown,
    message: error.toString(),
  );
}
