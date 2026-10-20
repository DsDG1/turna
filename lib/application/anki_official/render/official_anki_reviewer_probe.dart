import 'package:flutter/services.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';

/// The MethodChannel the native reviewer answers on. The name lives in
/// [OfficialAnkiReviewerProtocol], whose ArkTS twin is checked by the protocol
/// guard test — a rename on either side is a silent `MissingPluginException`
/// until someone opens a card on a device.
const MethodChannel officialAnkiReviewerChannel =
    MethodChannel(OfficialAnkiReviewerProtocol.channelName);

bool _probeStarted = false;

/// Runs the ADR 0050 §6 step 5b capability probe on HarmonyOS and logs what
/// comes back. Returns immediately; the verdict arrives whenever the native
/// page finishes, so callers must not await this to know anything.
///
/// What it answers is the whole of step 5b's acceptance criterion — can ArkUI
/// `Web` satisfy the reviewer's CSP, its synthetic `https://anki.local` origin,
/// and media Range requests — plus the assumption route E inherited: that a
/// Flutter plugin can put a native page on screen and get an answer back at
/// all. The verdict string is logged verbatim, transcript and all, because the
/// interesting failures are the ones where the page's account and the
/// server's record disagree, and a summary would have thrown that away.
Future<void> logOfficialAnkiReviewerProbe() async {
  if (!isHarmonyOsTarget) {
    return;
  }
  // One run per process. The native side also refuses a second answer, but a
  // second launch would put a full-screen page in front of the user, which is
  // the part worth guarding here.
  if (_probeStarted) {
    return;
  }
  _probeStarted = true;
  try {
    final verdict = await officialAnkiReviewerChannel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodProbeReviewerCapabilities,
    );
    logger.i('[OhosAnkiReviewerProbe] $verdict');
  } on MissingPluginException catch (e) {
    // The plugin is registered by hand in `EntryAbility`, so "not registered"
    // is the expected failure when a build predates step 5b. It is also the
    // exact failure a reviewer would hit, so it is logged rather than hidden.
    logger.w('[OhosAnkiReviewerProbe] channel unavailable: $e');
  } catch (e) {
    logger.w('[OhosAnkiReviewerProbe] failed: $e');
  }
}

/// Whether the probe has been launched. Only used to keep a test from racing a
/// second launch; the probe's own guard is the one that matters at runtime.
bool get officialAnkiReviewerProbeStarted => _probeStarted;

/// Test seam. The guard is a module-level bool because the launch has to be
/// once-per-process, and `flutter_test` cannot un-set that between cases the
/// way it could if it were an instance field.
void resetOfficialAnkiReviewerProbeForTest() {
  _probeStarted = false;
}

bool _assetProbeStarted = false;

/// Whether the reviewer ability can read its own asset bundle, and logs the
/// per-asset answer.
///
/// This is the other half of step 5b, and the half that does not need a screen.
/// The capability probe answers "can ArkUI `Web` host the card frame"; this
/// answers "can the bytes that frame requests be produced at all". The two fail
/// independently, and a reviewer built on the wrong answer to either one renders
/// a blank page — which, on this platform, looks the same as the loud
/// `renderer_ohos_pending` it was meant to replace.
///
/// The route matters enough to measure rather than assume. `AudioPlugin` records
/// that the promise form of the platform read never settled on Mate 90 Pro Max /
/// API 26, while the synchronous form does; if that still holds, the 2.27 MB
/// MathJax read is a platform-thread stall the reviewer has to plan around, and
/// if it no longer holds, the reviewer does not. Neither reading can be inherited
/// from another file's comment.
Future<void> logOfficialAnkiReviewerAssetProbe() async {
  if (!isHarmonyOsTarget || _assetProbeStarted) {
    return;
  }
  _assetProbeStarted = true;
  try {
    final report = await officialAnkiReviewerChannel.invokeMethod<String>(
      OfficialAnkiReviewerProtocol.methodProbeReviewerAssets,
    );
    logger.i('[OhosAnkiReviewerAssetProbe] $report');
  } on MissingPluginException catch (e) {
    logger.w('[OhosAnkiReviewerAssetProbe] channel unavailable: $e');
  } catch (e) {
    logger.w('[OhosAnkiReviewerAssetProbe] failed: $e');
  }
}

/// Test seam, for the same reason as [resetOfficialAnkiReviewerProbeForTest]:
/// the once-per-process guard has to be a module-level bool.
void resetOfficialAnkiReviewerAssetProbeForTest() {
  _assetProbeStarted = false;
}
