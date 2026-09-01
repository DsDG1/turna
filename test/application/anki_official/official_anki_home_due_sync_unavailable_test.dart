import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';

void main() {
  OfficialAnkiException error(OfficialAnkiErrorCode code) {
    return OfficialAnkiException(
      code: code,
      messageKey: 'official_anki.test',
    );
  }

  test('engine-state failures are marked unavailable instead of rethrown', () {
    expect(
      OfficialAnkiHomeDueSync.marksUnavailableWithoutRethrow(
        error(OfficialAnkiErrorCode.invalidState),
      ),
      isTrue,
    );
    expect(
      OfficialAnkiHomeDueSync.marksUnavailableWithoutRethrow(
        error(OfficialAnkiErrorCode.schedulerBusy),
      ),
      isTrue,
    );
    expect(
      OfficialAnkiHomeDueSync.marksUnavailableWithoutRethrow(
        error(OfficialAnkiErrorCode.collectionLocked),
      ),
      isTrue,
    );
  });

  test('pageTokenStale stays retryable and is not swallowed as unavailable', () {
    expect(
      OfficialAnkiHomeDueSync.marksUnavailableWithoutRethrow(
        error(OfficialAnkiErrorCode.pageTokenStale),
      ),
      isFalse,
    );
  });
}
