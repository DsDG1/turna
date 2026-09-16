import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/l10n/app_strings.dart';

const unfinishedImportBlocksNewDetails = 'unfinished_import_blocks_new';

bool catalogHasUnfinishedOfficialImport() {
  final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
  if (catalog == null) return false;
  return OfficialAnkiImportAttemptDao(catalog).hasUnfinished();
}

String unfinishedImportBlocksNewMessage() =>
    '${AppStrings.ankiImportSystemError}\n${AppStrings.ankiPendingMustDiscardBeforeNew}';

/// Error → human message mappers for the official import flow (§10.7: no
/// duplicate error mapping left in the widget). Application-layer policy,
/// not view formatting — kept next to the controller that owns the flow.
String mapOfficialErrorToHuman(OfficialAnkiException e) {
  // A4：只对真正的 pending 冲突给「有未完成导入」提示。以前任意
  // official 错误撞上残留未完成 attempt 都被改写成这条，commit 失败
  // 的真实原因会被掩盖。
  if (e.debugDetails == unfinishedImportBlocksNewDetails ||
      e.messageKey == 'official_anki.unfinished_blocks_new') {
    return unfinishedImportBlocksNewMessage();
  }
  if (e.code == OfficialAnkiErrorCode.packageInvalid ||
      e.code == OfficialAnkiErrorCode.collectionCorrupt) {
    return AppStrings.ankiCorruptDeck;
  }
  if (e.code == OfficialAnkiErrorCode.packageNotFound ||
      e.code == OfficialAnkiErrorCode.ioError) {
    return AppStrings.ankiFileReadFailed;
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
  return AppStrings.ankiParseFailed(error);
}
