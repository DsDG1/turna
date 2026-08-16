import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

class OfficialAnkiCapabilities {
  const OfficialAnkiCapabilities(this.info);

  final OfficialAnkiEngineInfo info;

  void require(String operation) {
    if (info.contractMajor != kOfficialAnkiContractMajor) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.contractVersionMismatch,
        messageKey: 'official_anki.contract_version_mismatch',
      );
    }
    if (!info.has(operation)) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.capability_missing',
        debugDetails: operation,
      );
    }
  }
}
