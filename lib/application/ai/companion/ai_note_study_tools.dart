// Project imports:
import 'package:turna/application/ai/ai_saved_explanations.dart';

class AiNoteVerificationQuestion {
  const AiNoteVerificationQuestion({
    required this.prompt,
    required this.checkpoint,
  });

  final String prompt;
  final String checkpoint;
}

class AiNoteAnkiDraft {
  const AiNoteAnkiDraft({required this.front, required this.back});

  final String front;
  final String back;

  String get asTsv => '${_singleLine(front)}\t${_singleLine(back)}';

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
}

/// Builds private, deterministic study aids from a saved explanation.
///
/// This intentionally does not call a model: opening a note never uploads it,
/// and the prompts remain usable while the app is offline.
class AiNoteStudyTools {
  const AiNoteStudyTools();

  List<AiNoteVerificationQuestion> verificationQuestions(
    SavedExplanation note,
  ) {
    final title = note.title.trim().isEmpty ? '这条知识点' : note.title.trim();
    final questions = <AiNoteVerificationQuestion>[
      AiNoteVerificationQuestion(
        prompt: '不看笔记，用自己的话解释“$title”。',
        checkpoint: '检查是否说清核心规则、适用条件和一个关键细节。',
      ),
      AiNoteVerificationQuestion(
        prompt: '写一个能正确运用“$title”的土耳其语例句，并翻译成中文。',
        checkpoint: '检查形式是否正确、语境是否自然、翻译是否一致。',
      ),
    ];
    if (note.body.trim().length >= 80) {
      questions.add(
        AiNoteVerificationQuestion(
          prompt: '举一个容易与“$title”混淆的情况，并说明怎样区分。',
          checkpoint: '检查是否给出明确的对比依据，而不只是重复结论。',
        ),
      );
    }
    return questions;
  }

  AiNoteAnkiDraft ankiDraft(SavedExplanation note) => AiNoteAnkiDraft(
        front: note.title.trim().isEmpty ? '请解释这条知识点' : note.title.trim(),
        back: note.body.trim(),
      );
}
