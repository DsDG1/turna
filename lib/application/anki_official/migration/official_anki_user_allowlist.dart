import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';

const _userAllowlistedHashes = <String>{
};

bool isUserAllowlistedSource({
  String? importId,
  String? sourceHash,
}) {
  if (isFixturePilotSource(importId: importId, sourceHash: sourceHash)) {
    return true;
  }
  if (sourceHash != null && _userAllowlistedHashes.contains(sourceHash.toLowerCase())) {
    return true;
  }
  return false;
}

Set<String> userAllowlistedHashesForDocs() => _userAllowlistedHashes;
