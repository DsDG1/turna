/// Host-level present acknowledgement. Scoring binds to this, not the tap.
class OfficialPresentAck {
  const OfficialPresentAck({
    required this.cardId,
    required this.generation,
    required this.side,
    required this.ok,
    this.code,
  });

  final int cardId;
  final int generation;
  final String side;
  final bool ok;
  final String? code;
}

/// Result of one native `present` invocation.
class OfficialAnkiPresentResult {
  const OfficialAnkiPresentResult({
    required this.ok,
    this.code,
    this.generation,
    this.side,
    this.height,
    this.recoverable = false,
    this.heightIgnored = false,
  });

  final bool ok;
  final String? code;
  final int? generation;
  final String? side;
  final double? height;
  final bool recoverable;
  final bool heightIgnored;

  static const supersededCode = 'RENDER_SUPERSEDED';

  bool get isSuperseded => code == supersededCode;

  factory OfficialAnkiPresentResult.fromNative(Object? raw) {
    if (raw is! Map) {
      return const OfficialAnkiPresentResult(
        ok: false,
        code: 'RENDER_TIMEOUT',
        recoverable: true,
      );
    }
    final map = Map<String, Object?>.from(raw);
    var code = map['code'] as String?;
    if (code != null && code.isEmpty) {
      code = null;
    }
    final ok = map['ok'] == true;
    if (!ok && (code == null || code == 'renderError')) {
      code = code == 'renderError' ? 'UNRENDERABLE_CARD' : 'RENDER_TIMEOUT';
    }
    return OfficialAnkiPresentResult(
      ok: ok,
      code: code,
      generation: (map['generation'] as num?)?.toInt(),
      side: map['side'] as String?,
      height: (map['height'] as num?)?.toDouble(),
      recoverable: map['recoverable'] == true || _recoverableCodes.contains(code),
    );
  }

  OfficialAnkiPresentResult copyWith({
    bool? ok,
    String? code,
    int? generation,
    String? side,
    double? height,
    bool? recoverable,
    bool? heightIgnored,
  }) {
    return OfficialAnkiPresentResult(
      ok: ok ?? this.ok,
      code: code ?? this.code,
      generation: generation ?? this.generation,
      side: side ?? this.side,
      height: height ?? this.height,
      recoverable: recoverable ?? this.recoverable,
      heightIgnored: heightIgnored ?? this.heightIgnored,
    );
  }

  static const _recoverableCodes = {
    'RENDER_TIMEOUT',
    supersededCode,
    'MATHJAX_ASSET_MISSING',
    'MATHJAX_TYPESET_FAILED',
    'SHELL_ASSET_MISSING',
    'FRAME_ASSET_MISSING',
    'WEBVIEW_MAIN_FRAME_ERROR',
    'SHELL_NOT_READY',
  };
}

/// Serializes Flutter-side presents so a stale completion cannot overwrite a
/// newer page height, and a superseded call does not hang.
class OfficialAnkiPresentGate {
  var _acceptedGeneration = 0;
  double? lastHeight;
  var inFlight = 0;

  int get acceptedGeneration => _acceptedGeneration;

  Future<OfficialAnkiPresentResult> run(
    int generation,
    Future<OfficialAnkiPresentResult> Function() present,
  ) async {
    inFlight += 1;
    try {
      final result = await present();
      if (result.isSuperseded) {
        return result;
      }
      final resultGen = result.generation ?? generation;
      if (resultGen < _acceptedGeneration) {
        return result.copyWith(heightIgnored: true, height: lastHeight);
      }
      if (result.ok) {
        _acceptedGeneration = resultGen;
        if (result.height != null) {
          lastHeight = result.height;
        }
      }
      return result;
    } finally {
      inFlight -= 1;
    }
  }

  bool shouldApplyHeight(int generation, double height) {
    if (generation < _acceptedGeneration) return false;
    _acceptedGeneration = generation;
    lastHeight = height;
    return true;
  }
}

/// Drops a second in-flight `present` for the same card / side / generation.
/// After the call settles (ok or fail), the same generation may retry.
/// A newer generation (flip, retry, next card) always goes through.
class OfficialAnkiPresentDeduper {
  int? _cardId;
  int? _generation;
  String? _side;
  var inFlight = false;

  bool shouldSkip({
    required int cardId,
    required int generation,
    required String side,
  }) {
    if (inFlight &&
        _cardId == cardId &&
        _generation == generation &&
        _side == side) {
      return true;
    }
    _cardId = cardId;
    _generation = generation;
    _side = side;
    inFlight = true;
    return false;
  }

  void markSettled() {
    inFlight = false;
  }
}
