import 'package:turna/domain/course/course_scope.dart';

/// Typed course-scope discrimination (ADR 0037 / 0067)。记忆卡牌组是可
/// 切换的课程（课程管理列出、`CourseProvider.setScope` 接受 anki scope）；
/// 练习台据此裁剪队列：anki 课程激活时语言队列让位给记忆卡复习入口。
abstract final class PlayReviewEligibility {
  static bool isLanguage(CourseScope scope) => scope is BuiltinCourseScope;

  static bool isAnki(CourseScope scope) =>
      scope is OfficialAnkiCourseScope || scope is LegacyAnkiCourseScope;
}
