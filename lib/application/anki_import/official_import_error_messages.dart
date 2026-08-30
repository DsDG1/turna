import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/l10n/app_strings.dart';

/// Error → human message mappers for the official import flow (§10.7: no
/// duplicate error mapping left in the widget). Application-layer policy,
/// not view formatting — kept next to the controller that owns the flow.
String mapOfficialErrorToHuman(OfficialAnkiException e) {
  if (e.code == OfficialAnkiErrorCode.packageInvalid ||
      e.code == OfficialAnkiErrorCode.collectionCorrupt) {
    return AppStrings.ankiCorruptDeck;
  }
  if (e.code == OfficialAnkiErrorCode.packageNotFound ||
      e.code == OfficialAnkiErrorCode.ioError) {
    return AppStrings.ankiFileReadFailed;
  }
  if (e.code == OfficialAnkiErrorCode.unsupportedPlatform ||
      e.code == OfficialAnkiErrorCode.contractVersionMismatch) {
    return AppStrings.ankiPickFileError;
  }
  return '${AppStrings.ankiImportFailedHuman} (${e.code.name})';
}

String mapGeneralErrorToHuman(Object error) {
  if (error is FileSystemException || error is IOException) {
    return AppStrings.ankiFileReadFailed;
  }
  final msg = error.toString();
  if (msg.contains('.colpkg')) {
    return AppStrings.ankiColpkgUnsupported;
  }
  if (msg.contains('.apkg')) {
    return AppStrings.ankiPickFileError;
  }
  return AppStrings.ankiParseFailed(error);
}
