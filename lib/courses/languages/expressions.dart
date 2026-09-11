export 'package:turna/courses/languages/language_content_store.dart'
    show expressionsById;

import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Loads the full expression list into memory and exposes a synchronous
/// id lookup map used by renderers / review UI.
///
/// Called once during [setupLocator] after the course DB is seeded.
Future<List<Expression>> loadExpressions([String? languageCode]) async {
  final store = languageCode == null
      ? LanguageContentStore.active
      : LanguageContentStore.of(languageCode);
  await store.ensureLoaded();
  if (languageCode == null ||
      LanguageCodes.canonicalize(languageCode) ==
          LanguageContentStore.activeCode) {
    store.publishGlobals();
  }
  return store.expressions;
}