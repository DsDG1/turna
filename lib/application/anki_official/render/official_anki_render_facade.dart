import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_capabilities.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// All UI render/compare calls go through this facade.
class OfficialAnkiRenderFacade {
  OfficialAnkiRenderFacade({
    required OfficialAnkiEngineInfo info,
    OfficialAnkiEngine? engine,
    OfficialAnkiSession? session,
  })  : _info = info,
        _engine = engine,
        _session = session,
        _capabilities = OfficialAnkiCapabilities(info);

  final OfficialAnkiEngineInfo _info;
  final OfficialAnkiEngine? _engine;
  final OfficialAnkiSession? _session;
  final OfficialAnkiCapabilities _capabilities;

  OfficialAnkiEngineInfo get info => _info;

  static Future<OfficialAnkiRenderFacade> fromWorker() async {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialRenderer) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.renderer_flag_fail_closed',
      );
    }
    OfficialAnkiCompositionRoot.rejectInProcessForProduction(flags);
    final session = OfficialAnkiCompositionRoot.requireWorkerSession();
    final info = await session.engineInfo();
    return OfficialAnkiRenderFacade(info: info, session: session);
  }

  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) async {
    _capabilities.require(OfficialAnkiOperation.renderCard);
    if (cardId <= 0) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_card_id',
      );
    }
    final engine = _engine;
    if (engine != null) {
      return engine.renderCard(
        cardId: cardId,
        browser: browser,
        includeAvTags: includeAvTags,
      );
    }
    return _session!.renderCard(
      cardId: cardId,
      browser: browser,
      includeAvTags: includeAvTags,
    );
  }

  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) async {
    _capabilities.require(OfficialAnkiOperation.compareTypedAnswer);
    final engine = _engine;
    if (engine != null) {
      return engine.compareTypedAnswer(
        cardId: cardId,
        marker: marker,
        provided: provided,
      );
    }
    return _session!.compareTypedAnswer(
      cardId: cardId,
      marker: marker,
      provided: provided,
    );
  }

  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) async {
    _capabilities.require(OfficialAnkiOperation.extractClozeForTyping);
    final engine = _engine;
    if (engine != null) {
      return engine.extractClozeForTyping(text: text, ordinal: ordinal);
    }
    return _session!.extractClozeForTyping(text: text, ordinal: ordinal);
  }
}
