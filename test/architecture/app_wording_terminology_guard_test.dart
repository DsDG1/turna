// Guard: app-facing wording must not say "Anki".
//
// Turna shows its card system as 记忆卡. Internal identifiers, protocol keys
// and the third-party AGPL notice keep the Anki name on purpose — the exact
// split is written down in AGENTS.md §7.2. This test enforces the app half.
//
// Why a source scan instead of widget tests: the wording lives in one string
// table plus a handful of inline literals, and a widget test would only cover
// the screens someone remembered to mount. Scanning the table strictly, plus
// every Chinese-language literal in `lib/`, covers the whole app surface.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tokens that legitimately keep the "anki" spelling: native protocol keys,
/// the native library name, the local reviewer origin, import paths and
/// migration file names. These are contracts, not copy.
final RegExp _technicalToken = RegExp(
  r'official_anki|libturna_anki|anki\.local|anki://|package:|\.dart|\.jsonl|collection\.anki2',
  caseSensitive: false,
);

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

/// Single-quoted Dart string literals, without the surrounding quotes.
/// Identifiers are out of scope by construction.
final RegExp _literal = RegExp(r"'(?:[^'\\\r\n]|\\.)*'");

String _stripInterpolations(String body) => body
    .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
    .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '');

List<String> _literals(String source) => _literal
    .allMatches(source)
    .map((m) => m.group(0)!.substring(1, m.group(0)!.length - 1))
    .toList();

List<File> _dartSources(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !RegExp(r'\.(g|freezed|config)\.dart$').hasMatch(f.path))
    .toList();

void main() {
  test('the app string table does not say Anki', () {
    const path = 'lib/l10n/app_strings.dart';
    final source = File(path).readAsStringSync();

    final offenders = <String>[];
    for (final literal in _literals(source)) {
      final body = _stripInterpolations(literal);
      if (!body.toLowerCase().contains('anki')) continue;
      if (_technicalToken.hasMatch(body)) continue;
      offenders.add(body);
    }

    expect(
      offenders,
      isEmpty,
      reason: '界面文案写「记忆卡」，不写 anki（AGENTS.md §7.2）',
    );
  });

  test('no Chinese-facing literal in lib/ says Anki', () {
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      if (file.path.endsWith('app_strings.dart')) continue;
      for (final literal in _literals(file.readAsStringSync())) {
        final body = _stripInterpolations(literal);
        if (!_cjk.hasMatch(body)) continue;
        if (!body.toLowerCase().contains('anki')) continue;
        if (_technicalToken.hasMatch(body)) continue;
        offenders.add('${file.path}: $body');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '中文界面文案写「记忆卡」，不写 anki（AGENTS.md §7.2）',
    );
  });

  test('the in-app changelog does not say Anki', () {
    final source = File('assets/changelog.md').readAsStringSync();
    expect(
      source.toLowerCase(),
      isNot(contains('anki')),
      reason: '应用内更新日志写「记忆卡」，不写 anki（AGENTS.md §7.2）',
    );
  });

  test('the in-app reviewer pages do not say Anki outside the local origin', () {
    final offenders = <String>[];
    for (final file
        in Directory('assets/anki_reviewer').listSync(recursive: true).whereType<File>()) {
      // The local reviewer origin is a contract with the native side, not copy.
      final stripped = file.readAsStringSync().replaceAll(
            RegExp('anki\\.local', caseSensitive: false),
            'local-origin',
          );
      if (stripped.toLowerCase().contains('anki')) offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: '复习器页面的标题与无障碍标签写「记忆卡」，不写 anki',
    );
  });

  test('the Anki AGPL notice keeps the third-party name', () {
    const path = 'lib/application/anki_official/official_anki_license_notices.dart';
    final source = File(path).readAsStringSync();
    expect(
      source,
      contains('Anki is licensed under the GNU Affero General Public License'),
      reason: '第三方许可必须点名 Anki，不得随文案改动一起改掉',
    );
  });

  test('the string table still carries the native error keys', () {
    final source = File('lib/l10n/app_strings.dart').readAsStringSync();
    expect(
      source,
      contains('official_anki.render_failed'),
      reason: '协议键仍是协议键：它们是原生错误码，不是文案',
    );
    expect(
      source,
      contains('记忆卡'),
      reason: 'positive control: the table was scanned, not gutted',
    );
  });
}
