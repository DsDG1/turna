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
  static const String channelName = OfficialAnkiReviewerProtocol.channelName;

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
    Future<void> Function()? onShowQuestion,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,
  }) async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case OfficialAnkiReviewerProtocol.methodShowAnswer:
          onShowAnswer(call.arguments as String? ?? '');
          return null;
        case OfficialAnkiReviewerProtocol.methodShowQuestion:
          await onShowQuestion?.call();
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
        case OfficialAnkiReviewerProtocol.methodReviewSettlement:
          // UI-7: the completion row's statistics. JSON because the value is
          // a small record the page formats itself; an empty reply keeps the
          // plain "Review complete" row.
          final data = await onSettlement?.call();
          return data == null ? '' : jsonEncode(data);
        case OfficialAnkiReviewerProtocol.methodReplayAudio:
          return await onReplayAudio?.call() ?? '';
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

  /// Abandons a reviewer that was opened before a card existed (P0-1).
  ///
  /// Answered rather than awaited: the ArkTS side either closes the live
  /// session or remembers the request for the session that is still booting,
  /// so there is nothing to wait for here.
  Future<void> close() async {
    await channel.invokeMethod<void>(
      OfficialAnkiReviewerProtocol.methodCloseReviewer,
    );
  }

  /// Above this size (`256 KB`), [pushMedia] leaves the file on disk for
  /// `AnkiOriginServer.mediaResponse` to read on demand via positioned
  /// `fs.openSync` + `fs.readSync(file.fd, buffer, { offset, length })` under
  /// `mediaRoot`, avoiding a full-file read, ×4/3 Base64 string allocation, and
  /// MethodChannel copy for multi-megabyte audio/video or high-res images (O1).
  /// Small icons and short clips still warm the per-card in-memory map so the
  /// synchronous `onInterceptRequest` path avoids a file open per icon.
  static const int directReadBypassThreshold = 256 * 1024;

  /// Resolves one media name and reports whether it is **settled**.
  ///
  /// "Settled" means the name needs no further attempt: either its bytes are
  /// in the native cache, or sending them is pointless — the resolver rejected
  /// the name and the file is missing, or it exceeds
  /// [directReadBypassThreshold] and the origin server serves it from disk under
  /// Range requests. Retrying either case cannot change the outcome, and
  /// re-reading a 3 MB audio's first 256 KB on every present would be a
  /// regression dressed as diligence.
  ///
  /// The only unsettled outcome is a transient one — the read or the channel
  /// trip throws. Those escape to [pushMediaForCard], which keeps the name out
  /// of its result so the next present retries it.
  ///
  /// Base64 is used because a MethodChannel carries strings and this SDK's
  /// standard codec has no byte-array mapping; payloads `>= 64 KB` encode on a
  /// background isolate via [compute].
  Future<bool> pushMedia(
    OfficialAnkiMediaResolver resolver,
    String name,
  ) async {
    final decision = resolver.resolveRelativeName(name);
    if (!decision.allowed || decision.file == null) {
      logger.w('[OhosReviewer] media denied ${decision.reason}: $name');
      return true;
    }
    // One open, one bounded read. The previous shape asked the file its length
    // and then read it whole: two IOs, and a multi-megabyte file was
    // materialised in memory only to be discarded for exceeding the threshold.
    // Reading `threshold + 1` bytes answers both questions at once — a buffer
    // that filled means the file is too big and belongs on the Range path. A
    // short buffer is EOF for a regular file, so there is nothing left to
    // collect.
    final handle = await decision.file!.open();
    try {
      final bytes = await handle.read(directReadBypassThreshold + 1);
      if (bytes.length > directReadBypassThreshold) {
        return true;
      }
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
      return true;
    } finally {
      await handle.close();
    }
  }

  /// How many media files may be in flight at once.
  ///
  /// Four rather than unbounded: each worker holds one file's bytes plus its
  /// Base64 string, and a card can reference a dozen icons. Unbounded
  /// parallelism trades a few hundred milliseconds for a memory spike on a
  /// platform whose reviewer page already carries a 2.27 MB MathJax payload.
  static const int mediaPushConcurrency = 4;

  /// Pushes every media file a rendered card references, and reports the names
  /// that are settled.
  ///
  /// Taken from the card's own HTML rather than from the whole collection: a
  /// 20 000-card collection has media this card does not want, and pushing all
  /// of it would cost base64 round-trips for files nobody will request.
  ///
  /// The returned set is the ledger the caller records. A name missing from it
  /// was a transient failure and will be retried on the next present; the
  /// origin server's disk fallback covers this render meanwhile.
  Future<Set<String>> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  ) async {
    final pending = names.toSet().toList(growable: false);
    if (pending.isEmpty) return <String>{};
    final settled = <String>{};
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= pending.length) return;
        final name = pending[index];
        try {
          if (await pushMedia(resolver, name)) {
            settled.add(name);
          }
        } catch (error, stack) {
          // One unreadable file must not cancel the remaining pushes; staying
          // out of the settled set is what makes it retryable.
          logger.w('[OhosReviewer] media push failed: $name',
              error: error, stackTrace: stack);
        }
      }
    }

    final workers = pending.length < mediaPushConcurrency
        ? pending.length
        : mediaPushConcurrency;
    await Future.wait(
      List<Future<void>>.generate(workers, (_) => worker()),
    );
    return settled;
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
  final pattern = RegExp(
    r'''(?:https://anki\.local/media/|(?<=[\s"'=(])/media/)([^\s"'<>)]+)''',
  );
  final names = <String>[];
  for (final match in pattern.allMatches(html)) {
    var raw = match.group(1);
    if (raw == null || raw.isEmpty) {
      continue;
    }
    final hash = raw.indexOf('#');
    if (hash >= 0) {
      raw = raw.substring(0, hash);
    }
    final query = raw.indexOf('?');
    if (query >= 0) {
      raw = raw.substring(0, query);
    }
    if (raw.isEmpty) {
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
