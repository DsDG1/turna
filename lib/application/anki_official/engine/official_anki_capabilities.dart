import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

class OfficialAnkiCapabilities {
  const OfficialAnkiCapabilities(this.info);

  final OfficialAnkiEngineInfo info;

  void require(String operation) {
    // Major mismatch already fails closed at envelope decode
    // (OfficialAnkiEnvelopeResponse.fromJson, doc 39 P2 single gate).
    if (!info.has(operation)) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.capability_missing',
        debugDetails: operation,
      );
    }
  }
}
