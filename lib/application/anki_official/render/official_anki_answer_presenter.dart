import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';

/// Narrow contract: formal scoring may start only after a matching answer ACK.
abstract class OfficialAnswerPresenter {
  int get presentedCardId;
  int get presentGeneration;
  String get currentSide;
  OfficialPresentAck? get lastAck;
  bool get hasAnswerPresentAck;
  bool get hasQuestionPresentAck;
  bool get isRenderError;
  String? get renderErrorCode;

  Future<void> loadAndShowQuestion(int cardId);
  Future<void> showAnswer({bool autoplay = true});
  OfficialPresentAck? acceptPresent(OfficialPresentAck ack);
  void invalidateGeneration();
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
  Future<void> dispose();
}
