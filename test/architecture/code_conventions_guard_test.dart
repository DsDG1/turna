// Code conventions guard: turns previously self-enforced AGENTS.md §8 rules
// (debugPrint ban, SQL LIKE discipline, *_page.dart / components/ ratchets,
// views/ Color(0x...) & peacock* ban) into hard CI gates.
//
// Allowlists for surviving legacy sites are bidirectionally checked: any new
// unapproved occurrence fails, and removing an existing legacy site without
// shrinking its allowlist fails so ratchets only tighten over time.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _isGeneratedDart(String normalizedPath) {
  return normalizedPath.endsWith('.g.dart') ||
      normalizedPath.endsWith('.gr.dart') ||
      normalizedPath.endsWith('.freezed.dart') ||
      normalizedPath.startsWith('lib/gen/');
}

/// Splits Dart [source] into `(codeOnly, stringLiterals)` while stripping both
/// `//` line comments and `/* ... */` block comments cleanly across quotes,
/// triple-quotes, and raw string literals (`r'...'`).
({String codeOnly, String stringLiterals}) _tokenizeDart(String source) {
  final code = StringBuffer();
  final strings = StringBuffer();
  final n = source.length;
  var i = 0;

  while (i < n) {
    final c = source[i];
    final next = i + 1 < n ? source[i + 1] : '';

    // Line comment
    if (c == '/' && next == '/') {
      i += 2;
      while (i < n && source[i] != '\n') {
        i++;
      }
      code.write('\n');
      continue;
    }

    // Block comment
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < n && !(source[i] == '*' && source[i + 1] == '/')) {
        if (source[i] == '\n') code.write('\n');
        i++;
      }
      i += 2;
      code.write(' ');
      continue;
    }

    // Raw string prefix: r'...' / r"..." / r'''...''' / r"""..."""
    var isRaw = false;
    var quoteStart = i;
    if (c == 'r' &&
        (next == "'" || next == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i - 1]))) {
      isRaw = true;
      quoteStart = i + 1;
    }

    if (source[quoteStart] == "'" || source[quoteStart] == '"') {
      final quoteChar = source[quoteStart];
      final triple = quoteChar * 3;
      final isTriple = quoteStart + 2 < n &&
          source.substring(quoteStart, quoteStart + 3) == triple;
      final delimLen = isTriple ? 3 : 1;
      var j = quoteStart + delimLen;
      final lit = StringBuffer();
      while (j < n) {
        if (!isRaw && source[j] == '\\' && j + 1 < n) {
          lit.write(source.substring(j, j + 2));
          j += 2;
          continue;
        }
        if (isTriple) {
          if (j + 2 < n && source.substring(j, j + 3) == triple) {
            j += 3;
            break;
          }
        } else if (source[j] == quoteChar) {
          j += 1;
          break;
        }
        lit.write(source[j]);
        j++;
      }
      strings
        ..write(lit.toString())
        ..write('\n');
      code.write(' "" ');
      i = j;
      continue;
    }

    code.write(c);
    i++;
  }

  return (codeOnly: code.toString(), stringLiterals: strings.toString());
}

List<File> _allLibDartFiles() {
  final root = Directory('lib');
  if (!root.existsSync()) {
    throw StateError('Run flutter test from repo root (missing lib/).');
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _norm(String path) => path.replaceAll('\\', '/');

/// Surviving constant-pattern SQL LIKE sites; parameterized LIKE must use
/// `lib/data/sql_like.dart` (`escapeLikePattern` / `containsLike` / `prefixLike`).
const Set<String> _allowedConstantLikeFiles = {
  'lib/application/anki_official/storage/official_anki_database.dart',
  'lib/application/anki_official/v2/official_anki_v2_view_store.dart',
  'lib/application/course_pack/imported_languages.dart',
  'lib/data/course_database.dart',
  'lib/data/course_repository.dart',
  'lib/data/gem_ledger_dao.dart',
};

/// Surviving *_screen.dart files locked in under AGENTS.md §5 ratchet.
/// Any new screen/page must use `*_page.dart`; remove entries as legacy
/// screens migrate.
const Set<String> _legacyScreenFiles = {
  'lib/views/anki/anki_import_screen.dart',
  'lib/views/anki/anki_review_screen.dart',
  'lib/views/lesson/new_lesson_screen.dart',
  'lib/views/play/daily_challenge_screen.dart',
  'lib/views/play/play_hub_screen.dart',
  'lib/views/profile/profile_screen.dart',
  'lib/views/review/grammar_review_screen.dart',
  'lib/views/review/mistake_practice_screen.dart',
  'lib/views/review/srs_review_screen.dart',
};

/// Surviving feature-scoped `widgets/` folders (excluding `lib/views/widgets`).
/// New feature folders must use `components/`.
const Set<String> _legacyFeatureWidgetsDirs = {
  'lib/views/profile/widgets',
  'lib/views/settings/widgets',
};

void main() {
  group('AGENTS.md §8 code conventions guard', () {
    final libFiles = _allLibDartFiles();

    test('debugPrint is restricted to lib/core/log_capture.dart', () {
      const allowedPath = 'lib/core/log_capture.dart';
      final debugPrintCall = RegExp(r'\bdebugPrint\s*\(');
      final hits = <String>{};

      for (final file in libFiles) {
        final rel = _norm(file.path);
        final tokens = _tokenizeDart(file.readAsStringSync());
        if (debugPrintCall.hasMatch(tokens.codeOnly)) {
          hits.add(rel);
        }
      }

      expect(
        hits,
        equals({allowedPath}),
        reason: 'Use Turna logger (lib/core/logger.dart) instead of debugPrint. '
            'Only $allowedPath recursion guards may call debugPrint directly.',
      );
    });

    test('raw .like() / SQL LIKE is restricted to sql_like.dart and constant ratchet',
        () {
      const helperPath = 'lib/data/sql_like.dart';
      final driftLikeCall = RegExp(r'\.like\s*\(');
      final sqlLikeKeyword = RegExp(r'\bLIKE\b');
      final sqlLowerLike = RegExp(r'(?:\bnot\s+like\b|\blike\s+[\x27?])',
          caseSensitive: false);

      final hits = <String>{};
      for (final file in libFiles) {
        final rel = _norm(file.path);
        if (_isGeneratedDart(rel) || rel == helperPath) continue;
        final tokens = _tokenizeDart(file.readAsStringSync());
        if (driftLikeCall.hasMatch(tokens.codeOnly) ||
            sqlLikeKeyword.hasMatch(tokens.stringLiterals) ||
            sqlLowerLike.hasMatch(tokens.stringLiterals)) {
          hits.add(rel);
        }
      }

      final unapproved = hits.difference(_allowedConstantLikeFiles);
      final stale = _allowedConstantLikeFiles.difference(hits);
      expect(
        unapproved,
        isEmpty,
        reason: 'New SQL LIKE queries must use escapeLikePattern / containsLike / '
            'prefixLike from $helperPath.',
      );
      expect(
        stale,
        isEmpty,
        reason: 'Shrink _allowedConstantLikeFiles: these files no longer use '
            'raw LIKE directly.',
      );
    });

    test('*_screen.dart and feature widgets/ dir ratchets stay exact', () {
      final actualScreens = libFiles
          .map((f) => _norm(f.path))
          .where((p) => p.endsWith('_screen.dart'))
          .toSet();
      expect(
        actualScreens.difference(_legacyScreenFiles),
        isEmpty,
        reason: 'New UI routes/screens must be named *_page.dart, not *_screen.dart.',
      );
      expect(
        _legacyScreenFiles.difference(actualScreens),
        isEmpty,
        reason: 'Shrink _legacyScreenFiles when existing *_screen.dart files '
            'are migrated or removed.',
      );

      final viewsDir = Directory('lib/views');
      final actualFeatureWidgets = viewsDir
          .listSync(recursive: true)
          .whereType<Directory>()
          .map((d) => _norm(d.path))
          .where((p) => p != 'lib/views/widgets' && p.endsWith('/widgets'))
          .toSet();
      expect(
        actualFeatureWidgets.difference(_legacyFeatureWidgetsDirs),
        isEmpty,
        reason: 'Feature-private widgets belong under <feature>/components/, '
            'not <feature>/widgets/.',
      );
      expect(
        _legacyFeatureWidgetsDirs.difference(actualFeatureWidgets),
        isEmpty,
        reason: 'Shrink _legacyFeatureWidgetsDirs when legacy feature widgets/ '
            'folders are retired.',
      );
    });

    test('lib/views/ has zero bare Color(0x...) and lib/ has zero peacock* aliases',
        () {
      final bareHexColor = RegExp(r'\bColor\s*\(\s*0[xX][0-9a-fA-F]+\s*\)');
      final peacockAlias = RegExp(r'\bpeacock[A-Za-z0-9_]*\b', caseSensitive: false);
      final bareColorHits = <String>[];
      final peacockHits = <String>[];

      for (final file in libFiles) {
        final rel = _norm(file.path);
        if (_isGeneratedDart(rel)) continue;
        final tokens = _tokenizeDart(file.readAsStringSync());
        if (rel.startsWith('lib/views/') && bareHexColor.hasMatch(tokens.codeOnly)) {
          bareColorHits.add(rel);
        }
        if (peacockAlias.hasMatch(tokens.codeOnly)) {
          peacockHits.add(rel);
        }
      }

      expect(
        bareColorHits,
        isEmpty,
        reason: 'Use TurnaTheme tokens in lib/core/theme.dart instead of bare '
            'Color(0x...) literals in lib/views/.',
      );
      expect(
        peacockHits,
        isEmpty,
        reason: 'Legacy peacock* palette aliases are retired; use TurnaTheme '
            'brand tokens.',
      );
    });
  });
}
