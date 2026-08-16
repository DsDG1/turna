// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Anki AGPL notice for Flutter's [LicenseRegistry].
///
/// Call before [showLicensePage]. Production About does not call this yet;
/// that hook is a release condition in
/// `native/turna_anki_core/licenses/THIRD-PARTY-NOTICES-DRAFT.md`.
const String kOfficialAnkiLicenseName = 'official Anki rslib (pinned)';

const String kOfficialAnkiSourceOfferSummary =
    'Corresponding source: this Turna commit + Anki '
    '967aa0d578fc75181e292e95326f9b58698da25c + '
    'native/turna_anki_core/patches/0001-export-progress-state.patch. '
    'See native/turna_anki_core/licenses/SOURCE-OFFER.md.';

/// Short Anki LICENSE wrapper (same text as `licenses/ANKI-LICENSE`).
const String kOfficialAnkiLicenseText = '''
Anki is licensed under the GNU Affero General Public License, version 3 or
later, with portions contributed by Anki users licensed under the BSD-3
license (see CONTRIBUTORS).

Pinned commit: 967aa0d578fc75181e292e95326f9b58698da25c
Turna uses rslib only (no Desktop Python/Qt, no official Reviewer web assets).
Turna patch: pub use progress::ProgressState;
Full wrapper: native/turna_anki_core/licenses/ANKI-LICENSE
AGPL-3.0: https://www.gnu.org/licenses/agpl-3.0.html
''';

bool _officialAnkiLicensesRegistered = false;

@visibleForTesting
void debugResetOfficialAnkiLicenses() {
  _officialAnkiLicensesRegistered = false;
}

/// Idempotent. Does not log card fields or package paths.
void registerOfficialAnkiLicenses() {
  if (_officialAnkiLicensesRegistered) {
    return;
  }
  _officialAnkiLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      <String>[kOfficialAnkiLicenseName],
      kOfficialAnkiLicenseText,
    );
  });
}

/// Production license page entry. Registers Anki AGPL before showing licenses.
void showTurnaLicensePage({
  required BuildContext context,
  String applicationName = 'Turna',
  String? applicationVersion,
}) {
  registerOfficialAnkiLicenses();
  showLicensePage(
    context: context,
    applicationName: applicationName,
    applicationVersion: applicationVersion,
  );
}
