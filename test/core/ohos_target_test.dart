// Tests for the OpenHarmony capability predicate and the degradation set built
// on it.
//
// The set is the single answer to "what does this build not ship", so the
// property that matters is that it is empty everywhere except OHOS. A build
// that started reporting degradations on Android would quietly grey out
// working features, and no widget test on this host could notice.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/ohos_target.dart';

void main() {
  test('the host SDK reports no degradations', () {
    // Runs on the Android/iOS toolchain, where `defaultTargetPlatform.name` is
    // never 'ohos'. This is the assertion that keeps the guards in the views
    // from disabling features on the platforms that do support them.
    expect(isHarmonyOsTarget, isFalse);
    expect(activeDegradations, isEmpty);
    for (final feature in OhosDegradation.values) {
      expect(isDegraded(feature), isFalse, reason: '$feature');
    }
  });

  test('the degradation set covers exactly the ADR 0047 exclusions', () {
    // If a feature is added to the enum it must be a deliberate decision, and
    // the list here is what makes that decision visible in a diff.
    //
    // Audio and text-to-speech are absent on purpose: they used to be listed
    // because `audioplayers` / `flutter_tts` have no OHOS plugin, and they are
    // now served by Turna's own ArkTS channels. Adding them back would grey out
    // working features; leaving a stale entry is the failure this list catches.
    //
    // `officialAnki` left on 2026-10-08 for the same reason, one step later:
    // ADR 0050 §6 steps 1-3 measured the engine (`runtimeOk=true reason=ready`)
    // and the shared catalog (`catalog=ok sqlite=3.49.2`) working on hardware,
    // so the entry was greying out working functionality. The missing piece
    // is the faithful renderer, which fails loudly inside the reviewer.
    expect(
      OhosDegradation.values.toSet(),
      {
        OhosDegradation.remoteBackup,
      },
    );
  });

  test('nothing greys out the Official Anki entry points any more', () {
    // The specific regression ADR 0050 §6 step 4 removed: a degradation
    // covering Official Anki would disable the import card on the companion
    // build. Asserted by name rather than by set shape alone so that
    // re-adding the entry fails here even if the list above is edited to match.
    expect(
      OhosDegradation.values.map((f) => f.name),
      isNot(contains('officialAnki')),
    );
  });

  test('the set is derived from the platform, not stored per feature', () {
    // Guards against someone replacing `isDegraded` with a hardcoded `false`
    // to make a test pass: the only input is the platform predicate.
    expect(isHarmonyOsTarget, isFalse);
    expect(
      activeDegradations.length,
      isHarmonyOsTarget ? OhosDegradation.values.length : 0,
    );
  });
}
