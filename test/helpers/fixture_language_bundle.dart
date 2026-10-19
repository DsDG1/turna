// Asset-bundle fixtures for tests that need a second packed language.
//
// Until 0.9 the French course shipped in `assets/courses/french/` and doubled
// as the acceptance fixture for the multi-language machinery. It is no longer
// part of the build (0.9 ships Turkish only), so the same JSON now lives under
// `test/fixtures/french_course/` and is served to the seeder through this
// overlay bundle. Keys keep their historical `assets/courses/french/...`
// spelling: `CourseLoader.baseDirFor('fr')` derives paths from the manifest's
// `dir`, and the tests assert that contract.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Directory holding the retired French course JSON (verbatim copy).
const String kFrenchFixtureDir = 'test/fixtures/french_course';

/// Serves [overrides] by key and delegates everything else to [fallback]
/// (the real bundle) — which is what lets a fixture language sit alongside the
/// shipped Turkish tree without copying it.
class OverlayAssetBundle extends CachingAssetBundle {
  OverlayAssetBundle(this.overrides, {AssetBundle? fallback})
      : _fallback = fallback ?? rootBundle;

  final Map<String, String> overrides;
  final AssetBundle _fallback;

  @override
  Future<ByteData> load(String key) async {
    final text = overrides[key];
    if (text != null) {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
    }
    return _fallback.load(key);
  }
}

/// A bundle that adds French to whatever the shipped manifest declares.
///
/// The packaged manifest is read through [rootBundle] rather than duplicated
/// here, so adding a language to the app keeps this fixture in sync without an
/// edit; only the French descriptor is injected.
Future<AssetBundle> frenchCourseFixtureBundle() async {
  String read(String relative) =>
      File('$kFrenchFixtureDir/$relative').readAsStringSync();

  final packed = jsonDecode(
    await rootBundle.loadString('assets/courses/manifest.json'),
  ) as Map<String, dynamic>;
  final languages = (packed['languages'] as List<dynamic>).toList()
    ..add(<String, dynamic>{
      'code': 'fr',
      'displayName': 'French',
      'ttsLocale': 'fr-FR',
      'dir': 'french',
      'nativeLabel': 'Apprendre le français',
      'signatureChars': 'àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ',
    });

  return OverlayAssetBundle(<String, String>{
    'assets/courses/manifest.json': jsonEncode({'languages': languages}),
    'assets/courses/french/index.json': read('index.json'),
    'assets/courses/french/vocab.json': read('vocab.json'),
    'assets/courses/french/grammar_points.json': read('grammar_points.json'),
    'assets/courses/french/expressions.json': read('expressions.json'),
    'assets/courses/french/sections/fr-section1.json':
        read('sections/fr-section1.json'),
  });
}
