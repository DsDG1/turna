// Tests for the platform split in the voice / TTS copy.
//
// The companion build has no preferred engine, no store, and no downloadable
// voice packs — the device publishes the voice list it has, and on the verified
// hardware that list has no Turkish entry. So the copy that reaches the user
// there must talk about device voices only, and every action button must be
// one the build can actually carry out.
//
// The branches themselves cannot be executed on this host: `isHarmonyOsTarget`
// compares `defaultTargetPlatform.name` to 'ohos', and `TargetPlatform.ohos`
// only exists in the OHOS engine fork, so no override can make the host report
// it (see `lib/core/ohos_target.dart`). The assertions below are therefore a
// mix of pure-function checks on the strings, which do run everywhere, and
// source scans for the branch structure, which is the same technique the W5
// batch used for a fix whose timing could not be arranged in a widget test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  group('voice list rendering', () {
    test('an empty list renders as an explicit "none"', () {
      // The list is empty on every non-companion platform, and on the companion
      // whenever the engine never started. Rendering "available: " with nothing
      // after it would read as a bug to the user, so the empty case is text.
      expect(AppStrings.voiceListLabel(const <String>[]), '无');
    });

    test('a single voice is rendered as-is', () {
      expect(AppStrings.voiceListLabel(const <String>['zh-CN']), 'zh-CN');
    });

    test('several voices are joined, not comma-concatenated', () {
      // The separator is a full-width ideographic comma to match the rest of
      // the Chinese copy; a plain ',' would read as part of a BCP-47 tag list
      // and be easy to misparse as a locale.
      expect(
        AppStrings.voiceListLabel(const <String>['zh-CN', 'en-US']),
        'zh-CN、en-US',
      );
    });
  });

  group('companion copy carries no store semantics', () {
    // These are the strings the companion build actually shows. A Google, store
    // or "install this pack" mention here is unreachable and misleading on that
    // platform, and the reachable copy is the only warning the user gets that
    // their language has no device voice.
    test('the settings strings name no engine, store or pack', () {
      for (final voice in const <String>['zh-CN', 'en-US']) {
        final copy = <String>[
          AppStrings.settingsOhosTtsReady(voice),
          AppStrings.settingsOhosTtsVoiceMissing('土耳其语', voice),
          AppStrings.settingsOhosTtsNoVoice(voice),
        ];
        for (final line in copy) {
          expect(line, isNot(contains('Google')));
          expect(line, isNot(contains('Play')));
          expect(line, isNot(contains('商店')));
        }
      }
    });

    test('the splash strings name no engine, store or pack', () {
      final copy = <String>[
        AppStrings.splashOhosVoiceMissingTitle('土耳其语'),
        AppStrings.splashOhosVoiceMissingBody('土耳其语', 'zh-CN、en-US'),
        AppStrings.splashOhosNoVoiceTitle,
        AppStrings.splashOhosNoVoiceBody('zh-CN、en-US'),
        AppStrings.splashAcknowledge,
      ];
      for (final line in copy) {
        expect(line, isNot(contains('Google')));
        expect(line, isNot(contains('Play')));
        expect(line, isNot(contains('商店')));
      }
    });

    test('the companion copy promises what the build can still deliver', () {
      // Course-bundled recordings do play on the companion build — that path is
      // plain file playback and needs no system voice. Dropping that sentence
      // would leave the user thinking the whole app went silent.
      expect(
        AppStrings.settingsOhosTtsVoiceMissing('土耳其语', 'zh-CN'),
        contains('课程自带录音不受影响'),
      );
      expect(
        AppStrings.splashOhosVoiceMissingBody('土耳其语', 'zh-CN'),
        contains('课程自带的录音仍可正常播放'),
      );
    });
  });

  group('the settings preview speaks what its entry promises', () {
    test('the label is built from the word that is spoken', () {
      // The two were written separately for a while: an OHOS device run pinned
      // the utterance to a Chinese phrase and left the entry saying "Merhaba",
      // so the preview taught the user the button lies.
      expect(
        AppStrings.settingsPlaySample,
        contains(AppStrings.settingsPlaySampleWord),
      );
    });

    test('the sample carries no hardcoded language override', () {
      final source =
          File('lib/views/settings/widgets/settings_sound_section.dart')
              .readAsStringSync();
      final start = source.indexOf('Future<void> _playSample()');
      final end = source.indexOf('void _showMessage(');
      // Both markers first: an empty slice would pass every "must not contain"
      // below without checking anything.
      expect(start, greaterThanOrEqualTo(0),
          reason: 'the preview method is missing entirely');
      expect(end, greaterThan(start),
          reason: 'the preview method no longer precedes _showMessage');

      final body = source.substring(start, end);
      // A `languageCode:` passed here outranks the course language. The one a
      // device run left behind was pinned to `zh-CN`, which made the Android
      // preview speak Chinese even on a device with a working Turkish voice.
      expect(body, isNot(contains('languageCode:')));
      expect(body, isNot(contains('zh-CN')));
      expect(body, contains('AppStrings.settingsPlaySampleWord'));
    });
  });

  group('actions the companion build cannot carry out stay hidden', () {
    test('the sound section gates the store action on the platform', () {
      final source =
          File('lib/views/settings/widgets/settings_sound_section.dart')
              .readAsStringSync();

      expect(
        source,
        matches(
          RegExp(
            r'if \(!isHarmonyOsTarget\)\s*\.\.\.\[[\s\S]{0,600}?'
            r'openGoogleTtsInstallPage',
          ),
        ),
        reason: 'the Play Store listing is unreachable on the companion build; '
            'its menu entry has to sit behind a platform guard',
      );
      // One call site, so the guard cannot cover a second un-guarded one.
      expect('openGoogleTtsInstallPage'.allMatches(source).length, 1);
    });

    test('the sound section reports device voices on the companion build', () {
      final source =
          File('lib/views/settings/widgets/settings_sound_section.dart')
              .readAsStringSync();

      expect(
        source,
        contains('if (isHarmonyOsTarget) {'),
        reason: 'the subtitle is the only place the user learns which voices '
            'the device has; without the branch it reports a Google engine',
      );
      expect(source, contains('AppStrings.settingsOhosTtsVoiceMissing'));
      expect(source, contains('AppStrings.voiceListLabel'));
    });

    test('the splash companion branch offers no dead-end action', () {
      final source =
          File('lib/views/splash/splash_page.dart').readAsStringSync();

      // The branch is delimited by the platform check that opens it and the
      // Android-only status switch that follows it. Asserting both markers
      // first keeps a moved or renamed branch from making the substring below
      // silently empty — an empty substring would pass every "must not contain".
      final start = source.indexOf('if (isHarmonyOsTarget) {');
      final androidStart = source.lastIndexOf('final (title, body) = switch');
      expect(start, greaterThanOrEqualTo(0),
          reason: 'the companion branch is missing entirely');
      expect(androidStart, greaterThan(start),
          reason: 'the Android-only switch is no longer after the branch');

      final branch = source.substring(start, androidStart);
      // `openSystemTtsSettings` returns false outside Android and
      // `openGoogleTtsInstallPage` needs a store app; both would dismiss the
      // dialog having done nothing, which is how a dead-end button ships.
      expect(branch, isNot(contains('openSystemTtsSettings')));
      expect(branch, isNot(contains('openGoogleTtsInstallPage')));
      expect(branch, isNot(contains('splashCouldNotOpenStore')));
      expect(branch, isNot(contains('splashInstallGoogleTts')));
      expect(branch, contains('AppStrings.splashAcknowledge'));
    });
  });
}
