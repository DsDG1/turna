import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';

/// ADR 0041 retired the OHOS *product line*; ADR 0047 authorises a *companion
/// lite build* instead. The switch is the presence of `ohos/` itself, so a
/// partial revert re-arms the EOL branch automatically.
///
/// The companion branch is not a whitelist: it swaps "these strings must not
/// exist" for "this override set is the only allowed one, and every entry is
/// pinned". See ADR 0047 §5 for the rationale.
void main() {
  group('OHOS architecture guard', () {
    test('OHOS platform tree is absent, or is a complete companion build', () {
      if (!_companionBuild) {
        expect(Directory('ohos').existsSync(), isFalse);
        expect(File('lib/data/rdb_query_executor.dart').existsSync(), isFalse);
        expect(File('lib/utils/ohos_file_picker.dart').existsSync(), isFalse);
      } else {
        for (final required in _requiredOhosFiles) {
          expect(
            File(required).existsSync(),
            isTrue,
            reason: 'companion build is missing $required',
          );
        }
        final commitSet = _gitCommitSet('ohos');
        final artifacts = commitSet
            .where((p) =>
                // Committed in the pre-EOL tree; ohos/.gitignore never covered
                // them. The template's own resources/base/profile/buildinfo.json5
                // is a source file and stays tracked.
                p.endsWith('.tsbuildinfo') ||
                p.endsWith('.tsbuildinfo.linter') ||
                p.endsWith('/local.properties') ||
                p.contains('/oh_modules/') ||
                p.contains('/node_modules/') ||
                p.endsWith('/package-lock.json') ||
                p.endsWith('/oh-package-lock.json5'))
            .toList();
        expect(
          artifacts,
          isEmpty,
          reason: 'build artifacts must not be committed: $artifacts',
        );

        // A hand-written plugin that is not registered on the engine leaves its
        // method channel without a handler. The symptom is a blank screen at
        // launch, with no build error and no Dart log — the RDB channel is
        // reached during startup, so `openDb` throws MissingPluginException
        // before the first frame. Only EntryAbility can register these: the
        // Flutter tool generates GeneratedPluginRegistrant.ets from pubspec
        // and has no package to learn them from.
        //
        // The import alone must not satisfy this: an ability that imports a
        // plugin but never adds it compiles cleanly and still leaves the
        // channel unserved.
        const ability = 'ohos/entry/src/main/ets/entryability/EntryAbility.ets';
        final abilitySource = File(ability).readAsStringSync();
        for (final plugin in _handWrittenPlugins) {
          expect(
            RegExp('new\\s+$plugin\\s*\\(').hasMatch(abilitySource),
            isTrue,
            reason: '$ability does not register $plugin with the engine; its '
                'method channel will have no handler and the app will open to '
                'a blank screen',
          );
        }
      }

      // The fork patch toolchain stays dead in both branches: the prebuilt SDK
      // route never needed it (ADR 0047 §2.6).
      expect(File('tool/apply_patches.sh').existsSync(), isFalse);
      expect(Directory('tool/patches').existsSync(), isFalse);
    });

    test('active trees do not contain forbidden OHOS markers', () {
      // Platform branches under lib/ are the companion build's own surface;
      // everywhere else (tool, CI, docs) the full needle set stays active.
      final libNeedles = _companionBuild ? _companionLibNeedles : _needles;
      // pubspec.yaml legitimately carries fork URLs under the companion build,
      // and the override ratchet below is strictly stronger than a substring ban.
      final pubspecNeedles = _companionBuild
          ? _needles.where((n) => n != 'openharmony')
          : _needles;

      final violations = <String>[];
      for (final root in <String>[
        'lib',
        'pubspec.yaml',
        'tool',
        '.github',
        'README.md',
        'AGENTS.md',
        'docs/project-guide.md',
        'docs/android-build-setup.md',
      ]) {
        final needles = root == 'pubspec.yaml' ? pubspecNeedles : libNeedles;
        final entity = FileSystemEntity.typeSync(root);
        if (entity == FileSystemEntityType.notFound) {
          // Optional CI dirs may be absent in some checkouts.
          if (root == '.github') continue;
          violations.add('missing scan root: $root');
          continue;
        }
        if (entity == FileSystemEntityType.file) {
          _scanFile(File(root), needles, violations);
        } else {
          for (final file
              in Directory(root).listSync(recursive: true).whereType<File>()) {
            if (_shouldSkip(file.path)) continue;
            _scanFile(file, needles, violations);
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('override parser handles the pre-EOL shape, comments and versions',
        () {
      const pubspec = '''
name: turna
dependency_overrides:
  # OHos (HarmonyOS) platform implementations from openharmony-tpc community.
  shared_preferences:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
      ref: br_shared_preferences-v2.5.3_ohos
  file_picker:
    git:
      url: https://gitcode.com/openharmony-sig/fluttertpc_file_picker.git
  win32: 2.7.0
flutter:
  uses-material-design: true
''';
      final parsed = _parseDependencyOverrides(pubspec.split('\n'));

      expect(parsed.keys,
          containsAll(<String>['shared_preferences', 'file_picker', 'win32']));
      expect(parsed['shared_preferences']!.url,
          'https://gitcode.com/openharmony-tpc/flutter_packages.git');
      expect(parsed['shared_preferences']!.ref,
          'br_shared_preferences-v2.5.3_ohos');
      expect(parsed['shared_preferences']!.path,
          'packages/shared_preferences/shared_preferences');
      // The pre-EOL pubspec tracked default branches for four of seven forks.
      expect(parsed['file_picker']!.url, isNotNull);
      expect(parsed['file_picker']!.ref, isNull);
      // A bare version pin has no git block at all.
      expect(parsed['win32']!.url, isNull);
      // A dedent ends the block; `flutter:` must not be parsed as an override.
      expect(parsed.containsKey('flutter'), isFalse);
      expect(parsed.containsKey('uses-material-design'), isFalse);
    });

    test('override parser treats a missing block as empty', () {
      expect(_parseDependencyOverrides(<String>['name: turna', 'version: 1.0']),
          isEmpty);
    });

    test('OHOS dependency overrides are the approved pinned set', () {
      final overrides =
          _parseDependencyOverrides(File('pubspec.yaml').readAsLinesSync());
      final gitOverrides = <String, _Override>{
        for (final entry in overrides.entries)
          if (entry.value.url != null) entry.key: entry.value,
      };

      for (final entry in overrides.entries) {
        expect(
          entry.value.path,
          isNot(contains('ohos')),
          reason: '${entry.key} must not point into the local ohos tree',
        );
      }
      final pathOverrides = <String, String>{
        for (final entry in overrides.entries)
          if (entry.value.url == null && entry.value.path != null)
            entry.key: entry.value.path!,
      };

      if (!_companionBuild) {
        expect(
          gitOverrides,
          isEmpty,
          reason: 'no OHOS fork overrides outside a companion build: '
              '${gitOverrides.keys.toList()}',
        );
        expect(
          pathOverrides,
          isEmpty,
          reason: 'no vendored overrides outside a companion build: '
              '${pathOverrides.keys.toList()}',
        );
        return;
      }

      expect(
        gitOverrides.keys.toSet(),
        _approvedOverrideRepos.keys.toSet(),
        reason: 'override set drifted from ADR 0047 §6',
      );
      for (final entry in gitOverrides.entries) {
        final repo = _approvedOverrideRepos[entry.key]!;
        expect(entry.value.url, contains(repo), reason: '${entry.key} repo');
        expect(
          entry.value.ref,
          isNotNull,
          reason: '${entry.key} must pin a ref, not track the default branch',
        );
        final pinned = _pinnedOverrideRefs[entry.key];
        if (pinned != null) {
          expect(entry.value.ref, pinned, reason: '${entry.key} ref drifted');
        }
      }

      expect(
        pathOverrides,
        _approvedVendoredOverrides,
        reason: 'vendored override set drifted from ADR 0047 §7',
      );

      for (final forbidden in _neverOverride) {
        expect(
          gitOverrides.containsKey(forbidden) ||
              pathOverrides.containsKey(forbidden),
          isFalse,
          reason: '$forbidden has no approved OHOS fork (ADR 0047 §5.5)',
        );
      }
    });

    test('OHOS capability checks in lib/ all go through one predicate', () {
      if (!_companionBuild) return;

      // `TargetPlatform.ohos` exists only in the OHOS fork, so `lib/` must
      // compare the platform by name — but only in ONE place. The first real
      // device run of the RDB layer dead-ended on the splash because the
      // Official Anki cold-start locator opened a second `sqlite3` FFI
      // database on a platform that has no `libsqlite3.so`, and nothing had
      // gated it. Per-site ad-hoc comparisons are how that happened; one
      // predicate in `lib/core/ohos_target.dart` is what keeps the next
      // capability from being missed the same way.
      final offenders = <String>[];
      final lib = Directory('lib');
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final relative = file.path.replaceAll(r'\', '/');
        if (relative == 'lib/core/ohos_target.dart') continue;
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') ||
              trimmed.startsWith('/*') ||
              trimmed.startsWith('*')) {
            continue;
          }
          if (line.contains("defaultTargetPlatform.name == 'ohos'") ||
              line.contains('TargetPlatform.ohos')) {
            offenders.add(relative);
          }
        }
      }
      expect(
        offenders.toSet(),
        isEmpty,
        reason: 'route OHOS checks through isHarmonyOsTarget '
            '(lib/core/ohos_target.dart) instead of inlining them: '
            '${offenders.toSet().toList()}',
      );
    });

    test('vendored UI packages are SDK-neutral (no ohos enum value)', () {
      if (!_companionBuild) return;

      for (final entry in _approvedVendoredOverrides.entries) {
        final root = Directory(entry.value);
        expect(root.existsSync(), isTrue,
            reason: 'missing vendored ${entry.key}');
        var ohos = 0;
        var wildcardArms = 0;
        final malformed = <String>[];
        for (final file in root.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          for (final line in file.readAsLinesSync()) {
            final trimmed = line.trim();
            final isComment = trimmed.startsWith('//') ||
                trimmed.startsWith('/*') ||
                trimmed.startsWith('*');
            if (isComment) continue;
            if (line.contains('TargetPlatform.ohos')) ohos++;
            if (RegExp(r'^\s*(default:|_ (when .* )?=>)').hasMatch(line)) {
              wildcardArms++;
            }
            if (RegExp(r'TargetPlatform\.\w+[^\s|,)]+TargetPlatform\.')
                .hasMatch(line)) {
              malformed.add('${file.path}: missing "||" separator');
            }
          }
        }
        // The point of the port: `TargetPlatform.ohos` exists only in the OHOS
        // fork and `dependency_overrides` has no platform conditioning, so
        // naming it would break the Android/iOS build and every test. ohos must
        // ride a wildcard arm instead, which is unreachable on the official SDK.
        expect(ohos, 0, reason: '${entry.key} names TargetPlatform.ohos');
        expect(
          malformed,
          isEmpty,
          reason: 'malformed logical-or chains would not parse: $malformed',
        );
        // A floor, not an exact count: upstream may legitimately add or drop
        // wildcard arms, but a re-vendor that lost the port must fail here
        // rather than at the two-minute compile.
        expect(
          wildcardArms,
          greaterThanOrEqualTo(_minWildcardArms[entry.key]!),
          reason: 'wildcard arms in ${entry.key} dropped below the port floor',
        );
      }
    });

    test('audio and TTS cross the platform boundary by name, on both sides', () {
      if (!_companionBuild) return;

      // A MethodChannel name is a string, so nothing in either toolchain checks
      // it: renaming the channel on one side compiles, passes every test, and
      // produces a build where every sound effect and every spoken word is
      // silent. Both ends are asserted from one place for that reason.
      const channels = <String, List<String>>{
        'me.dsdogs.turna/audio': <String>[
          'ohos/entry/src/main/ets/plugins/AudioPlugin.ets',
          'lib/service/audio_backend.dart',
        ],
        'me.dsdogs.turna/tts': <String>[
          'ohos/entry/src/main/ets/plugins/TtsPlugin.ets',
          'lib/service/speech_backend.dart',
        ],
      };
      for (final entry in channels.entries) {
        for (final path in entry.value) {
          expect(
            File(path).readAsStringSync(),
            contains(entry.key),
            reason: '$path no longer names the ${entry.key} channel; the two '
                'sides would silently stop talking to each other',
          );
        }
      }

      // The controller must keep going through the backends. A direct plugin
      // call added here would work on Android and throw MissingPluginException
      // on the companion build — the exact "compiles everywhere, fails on
      // device" shape this guard exists to catch.
      final controller =
          File('lib/application/audio_controller.dart').readAsStringSync();
      for (final plugin in <String>['audioplayers', 'flutter_tts']) {
        expect(
          controller,
          isNot(contains("import 'package:$plugin/")),
          reason: 'AudioController must reach $plugin through a backend in '
              'lib/service/, not import it directly',
        );
      }
    });

    test('the TTS voice reply keys agree across the channel', () {
      // The reply is a map with two keyed lists, and the two halves live in
      // files that no host test can execute together. This drifted once: the
      // plugin was changed to split "installed" from "supported" and the Dart
      // fake kept answering with a single list, so `invokeMapMethod` cast a
      // `List` to `Map?` and four tests failed on a TypeError raised inside the
      // platform channel. The production pair stayed correct — which is exactly
      // why a gate has to compare them by source rather than trust the tests.
      final plugin =
          File('ohos/entry/src/main/ets/plugins/TtsPlugin.ets')
              .readAsStringSync();
      final backend =
          File('lib/service/speech_backend.dart').readAsStringSync();

      for (final key in const <String>['installed', 'supported']) {
        expect(
          plugin,
          contains("'$key':"),
          reason: 'TtsPlugin no longer sends a \'$key\' voice list; the Dart '
              'side reads that key and would see nothing',
        );
        expect(
          backend,
          contains("['$key']"),
          reason: 'speech_backend no longer reads the \'$key\' voice list the '
              'plugin sends, so that half of the answer is dropped',
        );
      }
    });

    test('the voice list queries both module types', () {
      // Only the offline module reports voices the device already has; the
      // online one is where *downloadable* voices live. Querying just one
      // collapses "no Turkish voice" and "Turkish is downloadable" into the
      // same answer, and the user gets told the wrong remedy. Which index is
      // which is decided inside the plugin and is not observable from Dart, so
      // this compares the source instead.
      final plugin =
          File('ohos/entry/src/main/ets/plugins/TtsPlugin.ets')
              .readAsStringSync();
      final queryModules =
          RegExp(r'VOICE_QUERY_MODULES\s*:\s*number\[\]\s*=\s*(\[[^\]]*\])')
              .firstMatch(plugin)
              ?.group(1);
      expect(
        queryModules,
        isNotNull,
        reason: 'VOICE_QUERY_MODULES is gone; the module list must stay named '
            'and typed so this gate can read it',
      );
      expect(queryModules, contains('0'));
      expect(queryModules, contains('1'));

      // The engine's own query is the "already installed" half, and it has to
      // ask the offline module — the online one would return downloadable
      // voices and report them as present.
      expect(
        plugin,
        contains('online: OFFLINE_MODULE'),
        reason: 'the installed-voice query must use the offline module',
      );
    });

    test('capability matrix never requires Legacy fallback writers', () {
      // ADR 0050 §5 removed the sibling assertion that forbade
      // `case 'ohos':`, because authorising the official path on HarmonyOS is
      // exactly what that assertion forbade. The `legacyFallbackRequired`
      // assertion is untouched: no platform may be routed back to a Legacy
      // writer for lack of an Official engine, and ADR 0050 authorises the
      // official path rather than reviving the Legacy one.
      //
      // Consequence, recorded rather than left silent: nothing in the gate now
      // prevents a future edit from turning the HarmonyOS branch back into a
      // Legacy route. ADR 0050 §5 is the only record of that decision.
      final text = File(
        'lib/application/anki_official/migration/official_anki_engine_kind.dart',
      ).readAsStringSync();
      expect(text.contains('legacyFallbackRequired: true'), isFalse);
    });

    test('HarmonyOS routes to Official engine, not to unavailable', () {
      // ADR 0050 §6 step 3. This is the gate ADR 0050 §5 said was missing:
      // removing the "no case 'ohos':" assertion left nothing preventing a
      // later edit from quietly reverting the platform to ankiUnavailable,
      // and that revert would be invisible until someone ran the app on a
      // HarmonyOS device. This one asserts the opposite direction of the
      // removed assertion — HarmonyOS must NOT be in the unsupported bucket.
      final matrix = OfficialAnkiCapabilityMatrix.forPlatform('ohos');
      expect(matrix.officialCore, isTrue);
      expect(matrix.legacyFallbackRequired, isFalse);
      // Deliberately still false: the ArkTS PlatformView does not exist until
      // step 5b, and advertising the reviewer now would offer a UI that
      // cannot render.
      expect(
        matrix.officialReviewer,
        isFalse,
        reason: 'faithful reviewer is step 5b, not step 3',
      );

      expect(
        const AnkiImportExecutionPlanner().productModeFor(platform: 'ohos'),
        AnkiProductMode.officialAndroid,
      );

      // And the host resolver must produce 'ohos' rather than 'unknown'.
      // `Platform.is*` is all-false on the device (§2.1), so a chain of them
      // lands on 'unknown', which the matrix maps to officialCore=false —
      // the exact failure step 2's receipt was taken alongside.
      final source = File(
        'lib/application/anki_official/migration/official_anki_engine_kind.dart',
      ).readAsStringSync();
      final host = source.substring(source.indexOf('static String _hostPlatform'));
      final code = host
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        RegExp(r"if \(isHarmonyOsTarget\) return 'ohos';").hasMatch(code),
        isTrue,
        reason: 'every Platform.is* is false on HarmonyOS; only the predicate '
            'can name it',
      );

      // The runtime probe must not short-circuit the platform any more — that
      // refusal is what made `unsupported_platform` indistinguishable from a
      // load failure and forced ADR 0050 §4.2 to need its own probe.
      final composition = File(
        'lib/application/anki_official/official_anki_composition.dart',
      ).readAsStringSync();
      final guard = composition.substring(
        composition.indexOf('static OfficialAnkiRuntimeProbe probe('),
      );
      final gate = RegExp(
        r'if \(!\(Platform\.isAndroid[\s\S]{0,200}?isHarmonyOsTarget\)\)',
      );
      expect(gate.hasMatch(guard), isTrue,
          reason: 'probe must accept HarmonyOS via the single predicate');
    });

    test('Official native ABI packaging is arm64-only (doc 34 §14.2)', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      // Active abiFilters assignment would conflict with Flutter's
      // --target-platform split; comments documenting that rule are fine.
      expect(
        RegExp(r'^\s*ndk\s*\{[^}]*abiFilters', multiLine: true, dotAll: true)
            .hasMatch(gradle),
        isFalse,
      );
      expect(
        RegExp(r'^\s*abiFilters\b', multiLine: true).hasMatch(gradle),
        isFalse,
      );
      expect(gradle.contains('target-platform android-arm64'), isTrue);

      final release = File('tool/build_release.py').readAsStringSync();
      expect(release.contains('--target-platform'), isTrue);
      expect(release.contains('android-arm64'), isTrue);
      expect(release.contains('app-arm64-v8a-release.apk'), isTrue);

      final setup = File('docs/android-build-setup.md').readAsStringSync();
      expect(
        setup.contains(
          'flutter build apk --release --split-per-abi --target-platform android-arm64',
        ),
        isTrue,
      );

      // The .so itself is a build artifact (never committed): the
      // official-anki-android-arm64 CI job builds it, and its "Inspect .so"
      // step is where artifact presence is enforced. Statically we can still
      // pin the packaging rule: jniLibs may only ever hold arm64-v8a.
      final jniLibs = Directory('android/app/src/main/jniLibs');
      final abiDirs = jniLibs.existsSync()
          ? jniLibs
              .listSync()
              .whereType<Directory>()
              .map((d) => d.path.replaceAll('\\', '/').split('/').last)
              .toList()
          : const <String>[];
      expect(abiDirs, everyElement('arm64-v8a'),
          reason: 'jniLibs must package arm64-v8a only (doc 34 §14.2)');
    });

    test('companion hap ships the arm64 Anki engine in libs/arm64-v8a', () {
      if (!_companionBuild) return;

      // Deliberately different from the Android route above: Android builds
      // the .so in CI and never commits it, but the companion hap has no such
      // job (ADR 0050 §6 step 6), so the artifact IS committed. The gate
      // therefore moves from "absent" to "present, correct ABI, arm64 only",
      // and must fail loudly if the commit is dropped — a missing engine on
      // HarmonyOS degrades to ankiUnavailable with no build error, which is
      // exactly the failure shape this repository keeps having to discover
      // only on hardware.
      const lib = 'ohos/entry/libs/arm64-v8a/libturna_anki.so';
      final file = File(lib);
      expect(file.existsSync(), isTrue,
          reason: 'companion hap needs $lib; ADR 0050 §6 step 1');

      // ELF64 header check rather than a byte-count threshold: the file is a
      // build product and its size moves with the engine, but the ABI it was
      // compiled for is a decision, not an accident.
      final handle = file.openSync();
      final bytes = handle.readSync(20);
      handle.closeSync();
      expect(bytes.length, greaterThanOrEqualTo(20));
      // The ELF magic is 0x7F 'E' 'L' 'F' — the leading 0x7F is part of it.
      expect(bytes.sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46],
          reason: 'engine .so must be an ELF object');
      expect(bytes[4], 2, reason: 'ELF64 required');
      // e_machine is little-endian at offset 18: 0xB7 = 62 = EM_AARCH64.
      expect(bytes[18] | (bytes[19] << 8), 0xB7,
          reason: 'engine .so must be aarch64');

      // The same arm64-only rule as jniLibs above, but stated over the .so files
      // rather than the directory names: the template leaves an empty
      // libs/x86_64 behind, git cannot track an empty directory, so a
      // directory-name assertion would fail on a populated working copy and
      // pass on a fresh clone. What actually costs anything is an x86_64
      // object — ~23 MB in every hap, unloadable on a real device.
      final libs = Directory('ohos/entry/libs');
      final packaged = <String>[];
      if (libs.existsSync()) {
        for (final entry in libs.listSync(recursive: true)) {
          if (entry is File && entry.path.endsWith('.so')) {
            final abi = entry.path
                .replaceAll('\\', '/')
                .split('/')
                .elementAt(3);
            if (abi != 'arm64-v8a') packaged.add(abi);
          }
        }
      }
      expect(packaged, isEmpty,
          reason: 'companion hap must package the engine for arm64-v8a only; '
              'found .so under $packaged');

      // The artifact is committed, so it must not be swept up by an ignore
      // rule that would leave the working copy populated but a fresh clone
      // without the engine. `--no-index` is required: without it git
      // consults the index, and a tracked file is by definition not ignored,
      // so the assertion would pass no matter what .gitignore says.
      final ignored = Process.runSync(
              'git', ['check-ignore', '-q', '--no-index', lib])
          .exitCode;
      expect(ignored, isNot(0),
          reason: '$lib is committed on purpose; an ignore rule would make '
              'the engine vanish on a fresh clone');

      // The resolver must reach the bare name on HarmonyOS. Asserting the
      // source rather than the return value because `isHarmonyOsTarget` is
      // false on the host SDK, so the branch is unreachable from this test.
      final transport =
          File('lib/application/anki_official/engine/'
                  'official_anki_native_transport.dart')
              .readAsStringSync();
      final resolver = transport.substring(
          transport.indexOf('String? resolveOfficialAnkiLibraryPath'));
      expect(RegExp("isHarmonyOsTarget[\\s\\S]{0,600}?return 'libturna_anki\\.so'")
          .hasMatch(resolver),
          isTrue,
          reason: 'resolveOfficialAnkiLibraryPath must return the bundled '
              'name on HarmonyOS, otherwise the probe reports null and the '
              'capability matrix reports the engine as missing');
    });
  });
}

bool get _companionBuild => Directory('ohos').existsSync();

/// What git would actually commit under [path]: tracked files plus untracked
/// files that are not ignored. Walking the filesystem instead would flag
/// legitimate local build output (`ohos/node_modules/`, `ohos/oh_modules/`),
/// which the ignore rules cover but never commit.
List<String> _gitCommitSet(String path) {
  final result = Process.runSync('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'git ls-files failed for $path (exit ${result.exitCode}): '
      '${result.stderr}',
    );
  }
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim().replaceAll('\\', '/'))
      .where((l) => l.isNotEmpty)
      .toList();
}

const _needles = <String>[
  'HarmonyOsRdbExecutor',
  'OhosInitializationSettings',
  'OhosNotification',
  'openharmony',
  'tool/apply_patches.sh',
];

/// Under lib/ the companion build owns these three; the patch toolchain needle
/// and the fork-URL needle stay active.
const _companionLibNeedles = <String>[
  'openharmony',
  'tool/apply_patches.sh',
];

/// Presence only. The two media icons are also content-gated -- 216x216, no
/// alpha, full bleed, byte-identical to `tool/sync_ohos_icons.py`'s output --
/// in `test/sync_ohos_icons_test.py`, which is where the DevEco scaffold
/// placeholder regression is actually caught.
const _requiredOhosFiles = <String>[
  'ohos/AppScope/app.json5',
  'ohos/AppScope/resources/base/media/app_icon.png',
  'ohos/build-profile.json5',
  'ohos/hvigorfile.ts',
  'ohos/hvigorconfig.ts',
  'ohos/entry/src/main/module.json5',
  'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
  'ohos/entry/src/main/ets/plugins/RdbPlugin.ets',
  'ohos/entry/src/main/ets/plugins/FilePickerPlugin.ets',
  'ohos/entry/src/main/ets/plugins/AudioPlugin.ets',
  'ohos/entry/src/main/ets/plugins/TtsPlugin.ets',
  'ohos/entry/src/main/resources/base/media/icon.png',
];

/// Turna's own ArkTS plugins. Not packages, so the Flutter tool's registrant
/// generator cannot know about them; registration is [EntryAbility]'s job.
///
/// A plugin that is not a missing file but a missing *registration* is the
/// worse failure: it compiles, every test passes, and the app opens to a blank
/// screen or a silent button. The registration assertion above exists for
/// exactly that case.
const _handWrittenPlugins = <String>[
  'RdbPlugin',
  'FilePickerPlugin',
  'AudioPlugin',
  'TtsPlugin',
];

/// ADR 0047 §6. Refs still open are enforced only for presence until W3 lands.
/// `file_picker` and `flutter_local_notifications` are deliberately absent.
/// `file_picker`: its 8.x fork needs `web ^0.5.1`, which
/// contradicts share_plus's `web ^1.0.0`, and its 10.x fork is published under a
/// different package name (`file_picker_ohos`). The companion build does not
/// need it -- the ArkTS picker uses its own platform channel and never calls
/// `FilePicker.platform`.
///
/// `flutter_local_notifications`: its fork names `TargetPlatform.ohos` in nine
/// dispatch branches and adds public API upstream lacks
/// (`InitializationSettings.ohos`). No wildcard arm can neutralise a type
/// reference, so the fork cannot coexist with the official SDK. Local reminders
/// are out of companion scope (ADR 0047 §2).
const _approvedOverrideRepos = <String, String>{
  'shared_preferences': 'openharmony-tpc/flutter_packages.git',
  'path_provider': 'openharmony-tpc/flutter_packages.git',
  'url_launcher': 'openharmony-tpc/flutter_packages.git',
  'package_info_plus': 'openharmony-sig/flutter_plus_plugins.git',
  'share_plus': 'openharmony-sig/flutter_plus_plugins.git',
};

/// Every ref is pinned. Four of the seven pre-EOL overrides tracked a default
/// branch, so the old tree was not reproducible at all; the ratchet requires a
/// `ref` precisely to stop that coming back.
const _pinnedOverrideRefs = <String, String>{
  'shared_preferences': 'br_shared_preferences-v2.5.3_ohos',
  'path_provider': 'br_path_provider-v2.1.5_ohos',
  'url_launcher': 'br_url_launcher-v6.3.2_ohos',
  'package_info_plus': 'br_package_info_plus-v9.0.0_ohos',
  'share_plus': 'br_share_plus-v10.1.1_ohos',
};

const _neverOverride = <String>[
  'webview_flutter',
  'flutter_tts',
  'audioplayers',
];

/// Vendored copies carrying the OHOS TargetPlatform port (ADR 0047 §7).
const _approvedVendoredOverrides = <String, String>{
  'material_ui': 'third_party/flutter/material_ui',
  'cupertino_ui': 'third_party/flutter/cupertino_ui',
};

/// Floors for the wildcard arms the port introduces. Deliberately a floor: the
/// exact count moves with upstream, but a re-vendor that dropped the port must
/// not pass. Measured 2026-10-03 after the SDK-neutral port.
const _minWildcardArms = <String, int>{
  'material_ui': 89,
  'cupertino_ui': 22,
};

bool _shouldSkip(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.contains('/archive/')) return true;
  if (normalized.endsWith('CHANGELOG.md')) return true;
  if (normalized.contains('/.dart_tool/')) return true;
  if (normalized.contains('/.appanalyzer/')) return true;
  if (normalized.endsWith('.png') ||
      normalized.endsWith('.jpg') ||
      normalized.endsWith('.jar') ||
      normalized.endsWith('.so')) {
    return true;
  }
  return false;
}

void _scanFile(File file, Iterable<String> needles, List<String> violations) {
  late final String content;
  try {
    content = file.readAsStringSync();
  } catch (_) {
    return;
  }
  for (final needle in needles) {
    if (content.contains(needle)) {
      // ADR / doc 34 may mention the forbidden strings while documenting EOL.
      final path = file.path.replaceAll('\\', '/');
      if (path.endsWith('0041-ohos-product-eol.md')) continue;
      if (path.endsWith('0047-ohos-companion-lite-build.md')) continue;
      if (path.contains('34-official-anki-production-cutover')) continue;
      if (path.contains('ohos_eol_architecture_guard_test.dart')) continue;
      violations.add('$path -> $needle');
    }
  }
}

class _Override {
  _Override({this.url, this.ref, this.path});

  final String? url;
  final String? ref;
  final String? path;
}

/// Reads the `dependency_overrides` block. Deliberately narrow: only the
/// `url` / `ref` / `path` keys the ratchet needs, and an absent block is an
/// empty map rather than an error.
Map<String, _Override> _parseDependencyOverrides(List<String> lines) {
  final start = lines.indexWhere((l) => l.startsWith('dependency_overrides:'));
  if (start < 0) return <String, _Override>{};

  final result = <String, _Override>{};
  String? name;
  final body = <String>[];

  void flush() {
    if (name == null) return;
    String? pick(String key) {
      for (final line in body) {
        final trimmed = line.trim();
        if (trimmed.startsWith('$key:')) {
          return trimmed.substring(key.length + 1).trim();
        }
      }
      return null;
    }

    result[name!] = _Override(
      url: pick('url'),
      ref: pick('ref'),
      path: pick('path'),
    );
    name = null;
    body.clear();
  }

  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      flush();
      break;
    }
    if (line.trimLeft().startsWith('#')) continue;
    final entry = RegExp(r'^ {2}([A-Za-z0-9_]+):\s*(.*)$').firstMatch(line);
    if (entry != null) {
      flush();
      name = entry.group(1);
      continue;
    }
    if (name != null) body.add(line);
  }
  flush();
  return result;
}
