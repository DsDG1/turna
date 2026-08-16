import 'dart:convert';
import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

class OfficialAnkiPaths {
  OfficialAnkiPaths({
    required this.profileId,
    required this.profileRoot,
  }) {
    if (!_opaqueProfileId.hasMatch(profileId)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_profile_id',
      );
    }
  }

  static final _opaqueProfileId = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  final String profileId;
  final Directory profileRoot;

  File get collectionFile => File('${profileRoot.path}/collection.anki2');
  Directory get mediaFolder => Directory('${profileRoot.path}/collection.media');
  File get mediaDb => File('${profileRoot.path}/collection.media.db2');
  Directory get backups => Directory('${profileRoot.path}/backups');
  File get engineJson => File('${profileRoot.path}/engine.json');

  Map<String, String> openPayload({required String backendCommit}) {
    return <String, String>{
      'collection_path': collectionFile.path,
      'media_folder': mediaFolder.path,
      'media_db': mediaDb.path,
      'allowed_root': profileRoot.path,
    };
  }

  Future<void> ensureLayout() async {
    await profileRoot.create(recursive: true);
    await mediaFolder.create(recursive: true);
    await backups.create(recursive: true);
  }

  Future<void> writeEngineJson(Map<String, Object?> body) async {
    final tmp = File('${engineJson.path}.tmp');
    await tmp.writeAsString(jsonEncode(body));
    final raf = await tmp.open(mode: FileMode.append);
    await raf.flush();
    await raf.close();
    await tmp.rename(engineJson.path);
  }
}
