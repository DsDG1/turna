import 'package:flutter/foundation.dart';

enum HintLadderStage {
  idle,
  conceptCue,
  ruleCue,
  contrastCue,
  partialReveal,
  fullExplain,
  verify,
}

class HintLadderController extends ChangeNotifier {
  HintLadderStage _stage = HintLadderStage.idle;
  HintLadderStage get stage => _stage;

  int get visibleLevel => switch (_stage) {
        HintLadderStage.idle => 0,
        HintLadderStage.conceptCue => 1,
        HintLadderStage.ruleCue => 2,
        HintLadderStage.contrastCue => 3,
        HintLadderStage.partialReveal => 4,
        HintLadderStage.fullExplain => 5,
        HintLadderStage.verify => 6,
      };

  bool get isVerification => _stage == HintLadderStage.verify;

  bool canAdvance({
    required bool hasSubmittedAnswer,
    required bool allowRevealAnswer,
  }) {
    if (_stage == HintLadderStage.verify) return false;
    final max = hasSubmittedAnswer || allowRevealAnswer
        ? HintLadderStage.fullExplain
        : HintLadderStage.contrastCue;
    return _stage.index < max.index;
  }

  HintLadderStage advance({
    required bool hasSubmittedAnswer,
    required bool allowRevealAnswer,
  }) {
    if (!canAdvance(
      hasSubmittedAnswer: hasSubmittedAnswer,
      allowRevealAnswer: allowRevealAnswer,
    )) {
      return _stage;
    }
    _stage = HintLadderStage.values[_stage.index + 1];
    notifyListeners();
    return _stage;
  }

  void startVerification() {
    if (_stage == HintLadderStage.verify) return;
    _stage = HintLadderStage.verify;
    notifyListeners();
  }

  void reset() {
    if (_stage == HintLadderStage.idle) return;
    _stage = HintLadderStage.idle;
    notifyListeners();
  }

  static String instruction(HintLadderStage stage) => switch (stage) {
        HintLadderStage.idle =>
          'Do not explain yet. Ask what the learner has noticed.',
        HintLadderStage.conceptCue =>
          'Hint level 1: name only the concept being tested and one thing to observe. Maximum 3 short bullets. Do not reveal the answer.',
        HintLadderStage.ruleCue =>
          'Hint level 2: state the relevant rule or pattern with a different example. Do not reveal the answer or eliminate all options.',
        HintLadderStage.contrastCue =>
          'Hint level 3: contrast the two most plausible paths or eliminate at most one distractor. Do not state the final answer.',
        HintLadderStage.partialReveal =>
          'Hint level 4: reveal one intermediate step or part of the form, but still ask the learner to finish.',
        HintLadderStage.fullExplain =>
          'Hint level 5: give the full explanation, compare the submitted answer when present, and end with a transfer question.',
        HintLadderStage.verify =>
          'Verification: create one short, unambiguous variant that tests the same knowledge point without copying the original answer.',
      };

  static String label(HintLadderStage stage) => switch (stage) {
        HintLadderStage.idle => '尚未提示',
        HintLadderStage.conceptCue => '提示 1 · 观察',
        HintLadderStage.ruleCue => '提示 2 · 规则',
        HintLadderStage.contrastCue => '提示 3 · 对比',
        HintLadderStage.partialReveal => '提示 4 · 局部',
        HintLadderStage.fullExplain => '完整讲解',
        HintLadderStage.verify => '理解验证',
      };
}
