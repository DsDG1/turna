import 'package:flutter/material.dart';
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

  final IconData icon;
  final String label;
  final SessionProgressStyle progressStyle;
  final double maxWidth;
}

LessonPresentationProfile lessonPresentationProfile(LessonTemplate template) {
  return switch (template) {
    LessonTemplate.intro => LessonPresentationProfile(
        icon: Icons.school_rounded,
        label: AppStrings.lessonTemplateIntro,
        progressStyle: SessionProgressStyle.dots,
        maxWidth: 720,
      ),
    LessonTemplate.practice => LessonPresentationProfile(
        icon: Icons.edit_note_rounded,
        label: AppStrings.lessonTemplatePractice,
        progressStyle: SessionProgressStyle.dots,
        maxWidth: 720,
      ),
    LessonTemplate.listening => LessonPresentationProfile(
        icon: Icons.headphones_rounded,
        label: AppStrings.lessonTemplateListening,
        progressStyle: SessionProgressStyle.dots,
        maxWidth: 720,
      ),
    LessonTemplate.dialogue => LessonPresentationProfile(
        icon: Icons.forum_rounded,
        label: AppStrings.lessonTemplateDialogue,
        progressStyle: SessionProgressStyle.bar,
        maxWidth: 760,
      ),
    LessonTemplate.reading => LessonPresentationProfile(
        icon: Icons.menu_book_rounded,
        label: AppStrings.lessonTemplateReading,
        progressStyle: SessionProgressStyle.dots,
        maxWidth: 880,
      ),
    LessonTemplate.review => LessonPresentationProfile(
        icon: Icons.refresh_rounded,
        label: AppStrings.lessonTemplateReview,
        progressStyle: SessionProgressStyle.bar,
        maxWidth: 720,
      ),
    LessonTemplate.mastery => LessonPresentationProfile(
        icon: Icons.flag_rounded,
        label: AppStrings.lessonTemplateMastery,
        progressStyle: SessionProgressStyle.bar,
        maxWidth: 720,
      ),
    LessonTemplate.legacy => LessonPresentationProfile(
        icon: Icons.widgets_rounded,
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
