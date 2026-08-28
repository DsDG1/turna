import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/play/play_review_eligibility.dart';
import 'package:turna/domain/course/course_scope.dart';

void main() {
  test('builtin language is not an Anki review scope', () {
    expect(PlayReviewEligibility.isLanguage(const BuiltinCourseScope('tr')),
        isTrue);
    expect(PlayReviewEligibility.isAnki(const BuiltinCourseScope('tr')),
        isFalse);
    expect(PlayReviewEligibility.isLanguageScope(''), isTrue);
    expect(PlayReviewEligibility.isAnkiScope(''), isFalse);
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
    expect(PlayReviewEligibility.isAnkiScope('anki:deck1'), isTrue);
    expect(
      PlayReviewEligibility.isAnkiScope(
        CourseScopeCodec.encode(
          const OfficialAnkiCourseScope(
            profileId: 'p',
            sourceId: 's',
          ),
        ),
      ),
      isTrue,
    );
  });
}
