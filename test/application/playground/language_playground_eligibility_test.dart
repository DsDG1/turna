// Unit tests for [LanguagePlaygroundEligibility] — the single authoritative
// policy deciding whether the language Playground may be shown or entered.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/playground/language_playground_eligibility.dart';

void main() {
  group('LanguagePlaygroundEligibility.isEligibleScope', () {
    test('built-in language course scope is eligible', () {
      expect(LanguagePlaygroundEligibility.isEligibleScope(''), isTrue);
    });

    test('legacy Anki deck scopes are ineligible', () {
      expect(LanguagePlaygroundEligibility.isEligibleScope('anki:'), isFalse);
      expect(
        LanguagePlaygroundEligibility.isEligibleScope('anki:1718000000'),
        isFalse,
      );
    });

    test('official Anki projection scopes are ineligible', () {
      expect(
        LanguagePlaygroundEligibility.isEligibleScope('anki:official-src-1'),
        isFalse,
      );
    });

    test('non-Anki (future language) scopes stay eligible', () {
      // 当前只有 '' 与 'anki:*' 两个 scope 家族；未来新增语言课程 scope
      // 时必须升级为显式 CourseKind，而不是被这里误伤。
      expect(LanguagePlaygroundEligibility.isEligibleScope('tr:'), isTrue);
    });
  });
}
