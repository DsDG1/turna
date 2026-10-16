import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';

/// Dart half of the HarmonyOS reviewer contract (ADR 0050 §6 step 5b, route E).
///
/// The wire vocabulary — channel name, method names, receipt codes — lives in
/// [OfficialAnkiReviewerProtocol], whose ArkTS twin is checked name-for-name
/// by the protocol guard test. A rename on either side is a silent
/// `MissingPluginException` that only shows up when someone opens a card on a
/// device, which is exactly what that test exists to make loud.
///
/// Three calls go down and three come up. The asymmetry is deliberate and is
/// forced by the platform: the origin server answers a **synchronous**
/// `onInterceptRequest`, so it cannot ask Dart for media bytes at request time
/// (a MethodChannel call is a promise). Dart therefore pushes the card's media
/// before the `present` that will request it, and the page only ever reports
/// upwards.
class OfficialAnkiReviewerChannel {
  OfficialAnkiReviewerChannel._(this.channel);

  /// Channel name kept identical to the existing probe so the rename from
  /// "probe" to "reviewer" stays invisible to the rest of the Dart side.
  static const String channelName =
      OfficialAnkiReviewerProtocol.channelName;

  final MethodChannel channel;

  static OfficialAnkiReviewerChannel? _instance;

  static OfficialAnkiReviewerChannel get instance {
    return _instance ??= OfficialAnkiReviewerChannel._(
      const MethodChannel(channelName),
    );
  }

  /// Test seam. The handler is installed once per process, so a test cannot
  /// re-install it through a per-case object the way it could with an instance
  /// field.
  static void resetForTest() {
    _instance = null;
  }

  /// Installs the page-to-Dart half. Returns after the handler is live, so a
  /// caller may invoke `present` immediately afterwards without racing the
  /// registration — otherwise the first card's answer would be dropped and look
  /// like a reviewer that ignores the learner.
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
  }) async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case OfficialAnkiReviewerProtocol.methodShowAnswer:
          onShowAnswer(call.arguments as String? ?? '');
          return null;
        case OfficialAnkiReviewerProtocol.methodRate:
          // The reply IS the receipt: the page disables the four buttons on
          // tap and only re-enables them on what this returns, so a refusal
          // must travel back or it reads on device as a dead button.
          return onRate(call.arguments as String? ?? '');
        case OfficialAnkiReviewerProtocol.methodTypedChanged:
          onTypedChanged(call.arguments as String? ?? '');
          return null;
        case OfficialAnkiReviewerProtocol.methodRetryAdvance:
          // The page's explicit "retry the advance" entry after an
          // `advance_failed` receipt: the rating itself is already committed
          // in the scheduler, so this re-runs the advance only.
          return onRetryAdvance?.call(call.arguments as String? ?? '') ??
              OfficialAnkiReviewerProtocol.receiptEngineError;
        case OfficialAnkiReviewerProtocol.methodRetryPresent:
          await onRetryPresent?.call();
          return null;
        case OfficialAnkiReviewerProtocol.methodRequestUndo:
          await onUndo?.call();
          return null;
        case OfficialAnkiReviewerProtocol.methodReviewSettlement:
          // UI-7: the completion row's statistics. JSON because the value is
          // a small record the page formats itself; an empty reply keeps the
          // plain "Review complete" row.
          final data = await onSettlement?.call();
          return data == null ? '' : jsonEncode(data);
        default:
          // Answered rather than thrown: an unknown method from the page is a
          // protocol drift, and it must not take down the page's own call stack
          // on a platform where the failure would be invisible.
          logger.w('[OhosReviewer] unknown page call ${call.method}');
          return null;
      }
    });
  }

  /// Resolves once the reviewer page has finished loading its shell.
  ///
  /// [open] itself resolves only when the learner closes the ability, so a
  /// caller that awaited it before [present] would present into a page that
  /// no longer exists. This is the other signal: the page marks the shell
  /// ready from `onPageEnd`.
  Future<void> waitUntilReady() async {
    await channel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodAwaitReviewerReady,
    );
  }

  /// Opens the reviewer ability. Resolves when the learner closes it.
  Future<String> open({required String mediaRoot}) async {
    final verdict = await channel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodOpenReviewer,
      <String, Object?>{OfficialAnkiReviewerProtocol.argMediaRoot: mediaRoot},
    );
    return verdict ?? '';
  }

  /// Pushes one media file's bytes for the card about to be presented.
  ///
  /// Base64 because a MethodChannel carries strings and this SDK's standard
  /// codec has no byte-array mapping — the same reason `AudioPlugin.stageBytes`
  /// and the RDB BLOB bridge base64. The bytes come from
  /// [OfficialAnkiMediaResolver] rather than a second reader written in ArkTS,
  /// so the path rules are applied exactly once, by the side that owns them.
  ///
  /// Disk reads are async and large payloads are base64-encoded on an
  /// isolate: both used to run on the main isolate, where a multi-megabyte
  /// audio stalled every animation on screen for the duration of the read
  /// plus a ×4/3 string build. Small files stay inline — an isolate spawn
  /// per icon costs more than the encode it would offload.
  Future<void> pushMedia(
    OfficialAnkiMediaResolver resolver,
    String name,
  ) async {
    final decision = resolver.resolveRelativeName(name);
    if (!decision.allowed || decision.file == null) {
      logger.w('[OhosReviewer] media denied ${decision.reason}: $name');
      return;
    }
    final bytes = await decision.file!.readAsBytes();
    final encoded = bytes.length >= _base64IsolateThreshold
        ? await compute(base64Encode, bytes)
        : base64Encode(bytes);
    await channel.invokeMethod<void>(
      OfficialAnkiReviewerProtocol.methodCacheReviewerMedia,
      <String, Object?>{
        OfficialAnkiReviewerProtocol.argName: name,
        OfficialAnkiReviewerProtocol.argBase64: encoded,
      },
    );
  }

  /// Pushes every media file a rendered card references.
  ///
  /// Taken from the card's own HTML rather than from the whole collection: a
  /// 20 000-card collection has media this card does not want, and pushing all
  /// of it would cost base64 round-trips for files nobody will request.
  Future<void> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  ) async {
    for (final name in names.toSet()) {
      await pushMedia(resolver, name);
    }
  }

  /// Presents one side of the card and returns the frame's own ack.
  ///
  /// The ack is handed back as its decoded map rather than summarised, because
  /// "the card drew" and "the frame gave up" have to stay distinguishable — the
  /// difference between showing the answer and silently advancing a card that
  /// never rendered.
  Future<Map<String, Object?>?> present({
    required Map<String, Object?> payload,
    required String side,
  }) async {
    final raw = await channel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodPresentReviewer,
      <String, Object?>{
        OfficialAnkiReviewerProtocol.argPayloadJson: jsonEncode(payload),
        OfficialAnkiReviewerProtocol.argSide: side,
      },
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// The frame's last ack, for anything that wants the measured height — the
  /// only place that number exists.
  Future<Map<String, Object?>?> lastAck() async {
    final raw = await channel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodReviewerLastAck,
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  /// Pushes a render failure the page cannot otherwise see. The ArkTS
  /// `present` promise only carries acks that crossed the channel; failures
  /// detected on this side (media push exceptions, controller errors) would
  /// otherwise strand the page on a shell with no card and no explanation.
  Future<void> reportFailure(String code) async {
    await channel.invokeMethod<void>(
      OfficialAnkiReviewerProtocol.methodNotifyReviewerFailure,
      code,
    );
  }
}

/// Above this size a media file's base64 encoding moves to an isolate (see
/// [OfficialAnkiReviewerChannel.pushMedia]). 64 KB keeps every icon and small
/// image inline while moving audios — the payloads that actually stall frames
/// — off the main isolate.
const int _base64IsolateThreshold = 64 * 1024;

/// Every `https://anki.local/media/…` reference in a card's HTML, decoded to
/// the filename the resolver expects.
///
/// Returned names are the raw decoded ones — no normalisation, no NFC/NFD
/// rewriting, no stripping of directories. `OfficialAnkiMediaResolver` matches
/// names as they are stored on disk, so "tidying" them here would silently miss
/// every media file whose name is not pure ASCII.
Iterable<String> mediaNamesIn(String html) {
  final pattern = RegExp(r'''https://anki\.local/media/([^\s"'<>)]+)''');
  final names = <String>[];
  for (final match in pattern.allMatches(html)) {
    final raw = match.group(1);
    if (raw == null || raw.isEmpty) {
      continue;
    }
    try {
      final decoded = Uri.decodeComponent(raw);
      if (!decoded.contains('/') && !decoded.contains('\\')) {
        names.add(decoded);
      }
    } on FormatException {
      // A malformed escape is not a media name worth asking the resolver about;
      // the origin server will reject it on its own if something requests it.
      continue;
    }
  }
  return names;
}
