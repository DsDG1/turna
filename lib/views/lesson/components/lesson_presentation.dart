import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/listening_phase.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/session_shell.dart';

class LessonPresentationProfile {
  const LessonPresentationProfile({
    required this.icon,
    required this.label,
    required this.progressStyle,
    required this.maxWidth,
  });

  final TurnaIconId icon;
  final String label;
  final SessionProgressStyle progressStyle;
  final double maxWidth;
}

LessonPresentationProfile lessonPresentationProfile(LessonTemplate template) {
  return switch (template) {
    LessonTemplate.guide => LessonPresentationProfile(
      icon: TurnaIconId.explore,
      label: AppStrings.lessonTemplateGuide,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 760,
    ),
    LessonTemplate.intro => LessonPresentationProfile(
      icon: TurnaIconId.school,
      label: AppStrings.lessonTemplateIntro,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 720,
    ),
    LessonTemplate.practice => LessonPresentationProfile(
      icon: TurnaIconId.edit,
      label: AppStrings.lessonTemplatePractice,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 720,
    ),
    LessonTemplate.listening => LessonPresentationProfile(
      icon: TurnaIconId.headphones,
      label: AppStrings.lessonTemplateListening,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 720,
    ),
    LessonTemplate.dialogue => LessonPresentationProfile(
      icon: TurnaIconId.chat,
      label: AppStrings.lessonTemplateDialogue,
      progressStyle: SessionProgressStyle.bar,
      maxWidth: 760,
    ),
    LessonTemplate.reading => LessonPresentationProfile(
      icon: TurnaIconId.book,
      label: AppStrings.lessonTemplateReading,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 880,
    ),
    LessonTemplate.review => LessonPresentationProfile(
      icon: TurnaIconId.refresh,
      label: AppStrings.lessonTemplateReview,
      progressStyle: SessionProgressStyle.bar,
      maxWidth: 720,
    ),
    LessonTemplate.mastery => LessonPresentationProfile(
      icon: TurnaIconId.flag,
      label: AppStrings.lessonTemplateMastery,
      progressStyle: SessionProgressStyle.bar,
      maxWidth: 720,
    ),
    LessonTemplate.legacy => LessonPresentationProfile(
      icon: TurnaIconId.layers,
      label: AppStrings.lessonTemplateLegacy,
      progressStyle: SessionProgressStyle.dots,
      maxWidth: 720,
    ),
  };
}

ListeningPhase? listeningPhaseForStage(Lesson lesson, Stage? stage) {
  if (lesson.template != LessonTemplate.listening || stage == null) {
    return null;
  }
  for (final phase in lesson.content.listeningPhases) {
    if (stage.id == 'lp-${phase.id}') return phase;
  }
  return null;
}
