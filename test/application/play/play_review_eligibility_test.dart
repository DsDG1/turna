import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/play/play_review_eligibility.dart';
import 'package:turna/domain/course/course_scope.dart';

/// Typed 判定的消费方：练习台与个人页快捷入口的 scope 分支（ADR 0037 /
/// 0067）——记忆卡课程激活时语言队列让位给记忆卡复习入口。
void main() {
  test('builtin language is not an Anki review scope', () {
    expect(PlayReviewEligibility.isLanguage(const BuiltinCourseScope('tr')),
        isTrue);
    expect(
        PlayReviewEligibility.isAnki(const BuiltinCourseScope('tr')), isFalse);
  });

  test('official and legacy Anki scopes are Anki review scopes', () {
    expect(
      PlayReviewEligibility.isAnki(
        const OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: 'src',
        ),
      ),
      isTrue,
    );
    expect(
      PlayReviewEligibility.isAnki(const LegacyAnkiCourseScope('imp')),
      isTrue,
    );
    expect(
      PlayReviewEligibility.isLanguage(const LegacyAnkiCourseScope('imp')),
      isFalse,
    );
  });
}
