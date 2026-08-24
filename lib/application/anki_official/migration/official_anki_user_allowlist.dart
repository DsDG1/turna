import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';

const _userAllowlistedHashes = <String>{
  // D4 first source: isolated 1-card written hash (p5d-d4-src.apkg).
  'd7cdafb74537722ea9ba07762c5b56c4845c2b687142f3ac52102497ae15ca07',
};

bool isUserAllowlistedSource({
  String? importId,
  String? sourceHash,
}) {
  if (isFixturePilotSource(importId: importId, sourceHash: sourceHash)) {
    return true;
  }
  if (sourceHash != null &&
      _userAllowlistedHashes.contains(sourceHash.toLowerCase())) {
    return true;
  }
  return false;
}

Set<String> userAllowlistedHashesForDocs() => _userAllowlistedHashes;
