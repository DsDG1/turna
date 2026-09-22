import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/app_startup.dart';
import 'package:turna/views/splash/splash_page.dart';

void main() {
  test('splash names the seed phase until the course is loaded', () {
    expect(
      splashStartupStatusLabel(
        TurnaStartupPhase.seeding,
        courseLoaded: false,
        bootFailed: false,
      ),
      AppStrings.splashPhaseSeeding,
    );
    expect(
      splashStartupStatusLabel(
        TurnaStartupPhase.validating,
        courseLoaded: false,
        bootFailed: false,
      ),
      AppStrings.splashPhaseValidating,
    );
    expect(
      splashStartupStatusLabel(
        TurnaStartupPhase.ready,
        courseLoaded: true,
        bootFailed: false,
      ),
      isNull,
    );
    expect(
      splashStartupStatusLabel(
        TurnaStartupPhase.failed,
        courseLoaded: false,
        bootFailed: true,
      ),
      isNull,
    );
  });
}
