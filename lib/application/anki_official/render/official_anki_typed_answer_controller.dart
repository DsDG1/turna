import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';

enum OfficialAnkiTypedPhase {
  idle,
  editing,
  comparing,
  shown,
  recoverableError,
}

class OfficialAnkiTypedAnswerController {
  OfficialAnkiTypedAnswerController(this._facade);

  final OfficialAnkiRenderFacade _facade;
  var _generation = 0;
  var provided = '';
  var frozen = false;
  OfficialAnkiTypedComparison? comparison;
  OfficialAnkiTypedAnswerHint? hint;
  OfficialAnkiException? error;
  OfficialAnkiTypedPhase phase = OfficialAnkiTypedPhase.idle;

  void attach(OfficialAnkiTypedAnswerHint? nextHint) {
    _generation += 1;
    hint = nextHint;
    provided = '';
    frozen = false;
    comparison = null;
    error = null;
    if (nextHint == null) {
      phase = OfficialAnkiTypedPhase.idle;
      return;
    }
    if (nextHint.marker.isEmpty) {
      error = const OfficialAnkiException(
        code: OfficialAnkiErrorCode.typedFieldNotFound,
        messageKey: 'official_anki.typed_field_unknown',
        recoverable: true,
      );
      phase = OfficialAnkiTypedPhase.recoverableError;
      return;
    }
    phase = OfficialAnkiTypedPhase.editing;
  }

  void updateProvided(String value) {
    if (frozen) return;
    provided = value;
  }

  void restoreInputOnQuestion() {
    if (phase == OfficialAnkiTypedPhase.idle) return;
    frozen = false;
    comparison = null;
    if (error == null) {
      phase = OfficialAnkiTypedPhase.editing;
    }
  }

  Future<OfficialAnkiTypedComparison?> compare({
    required int cardId,
    required int generation,
  }) async {
    final current = hint;
    if (current == null) {
      return null;
    }
    if (current.marker.isEmpty) {
      error = const OfficialAnkiException(
        code: OfficialAnkiErrorCode.typedFieldNotFound,
        messageKey: 'official_anki.typed_field_unknown',
        recoverable: true,
      );
      phase = OfficialAnkiTypedPhase.recoverableError;
      frozen = false;
      return null;
    }
    if (current.clozeOrdinal != null && current.marker.contains('cloze:')) {
      // Empty cloze is reported by native EXTRACT; treat missing expected as recoverable.
    }
    frozen = true;
    phase = OfficialAnkiTypedPhase.comparing;
    try {
      final result = await _facade.compareTypedAnswer(
        cardId: cardId,
        marker: current.marker,
        provided: provided,
      );
      if (generation != _generation) return null;
      comparison = result;
      error = null;
      phase = OfficialAnkiTypedPhase.shown;
      return result;
    } on OfficialAnkiException catch (caught) {
      if (generation != _generation) return null;
      error = OfficialAnkiException(
        code: caught.code,
        messageKey: caught.messageKey,
        recoverable: true,
        debugDetails: caught.debugDetails,
      );
      phase = OfficialAnkiTypedPhase.recoverableError;
      frozen = false;
      return null;
    } catch (caught) {
      if (generation != _generation) return null;
      error = OfficialAnkiException(
        code: OfficialAnkiErrorCode.renderFailed,
        messageKey: 'official_anki.typed_compare_failed',
        recoverable: true,
        debugDetails: caught.toString(),
      );
      phase = OfficialAnkiTypedPhase.recoverableError;
      frozen = false;
      return null;
    }
  }

  int get generation => _generation;
}
