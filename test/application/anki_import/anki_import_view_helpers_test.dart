import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/official_import_error_messages.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  group('mapOfficialErrorToHuman fallback branch (doc 40 R3/F1)', () {
    test('unfinished leftover maps to system error plus must-discard', () {
      final message = mapOfficialErrorToHuman(
        const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.unfinished_blocks_new',
          debugDetails: unfinishedImportBlocksNewDetails,
        ),
      );
      expect(message, contains(AppStrings.ankiImportSystemError));
      expect(message, contains(AppStrings.ankiPendingMustDiscardBeforeNew));
    });

    test('falls back to human failure text plus error code name', () {
      final message = mapOfficialErrorToHuman(
        const OfficialAnkiException(
          code: OfficialAnkiErrorCode.internalError,
          messageKey: 'official_anki.backend_error',
        ),
      );
      expect(message, contains(AppStrings.ankiImportFailedHuman));
      expect(message, contains('internalError'));
    });

    test('no literal \$ or interpolation placeholder leaks to users', () {
      const codes = OfficialAnkiErrorCode.values;
      for (final code in codes) {
        final message = mapOfficialErrorToHuman(
          OfficialAnkiException(code: code, messageKey: 'k'),
        );
        expect(message, isNot(contains(r'${')), reason: 'code=$code');
        expect(message, isNot(contains(r'\$')), reason: 'code=$code');
      }
    });
  });
}
