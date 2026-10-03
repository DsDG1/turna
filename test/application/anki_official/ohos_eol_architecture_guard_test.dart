import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

    test('capability matrix never requires Legacy fallback writers', () {
      final text = File(
        'lib/application/anki_official/migration/official_anki_engine_kind.dart',
      ).readAsStringSync();
      expect(text.contains('legacyFallbackRequired: true'), isFalse);
      // The companion build ships no Official Anki host, so this stays
      // unconditional even in that branch (ADR 0047 §2.2).
      expect(
        RegExp(r"case\s+'ohos'\s*:").hasMatch(text),
        isFalse,
      );
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

const _requiredOhosFiles = <String>[
  'ohos/AppScope/app.json5',
  'ohos/build-profile.json5',
  'ohos/hvigorfile.ts',
  'ohos/hvigorconfig.ts',
  'ohos/entry/src/main/module.json5',
  'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
  'ohos/entry/src/main/ets/plugins/RdbPlugin.ets',
  'ohos/entry/src/main/ets/plugins/FilePickerPlugin.ets',
];

/// Turna's own ArkTS plugins. Not packages, so the Flutter tool's registrant
/// generator cannot know about them; registration is [EntryAbility]'s job.
const _handWrittenPlugins = <String>['RdbPlugin', 'FilePickerPlugin'];

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
