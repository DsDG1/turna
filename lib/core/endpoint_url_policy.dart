// Flutter imports:
import 'package:flutter/foundation.dart';

/// Why a user-typed network endpoint was rejected.
///
/// An enum rather than a message so the policy stays free of l10n: each
/// surface maps the same reason to its own localized string, and the two
/// network exits cannot drift into disagreeing about *what* is allowed even
/// if their wording differs.
enum EndpointUrlProblem {
  /// Nothing was typed.
  empty,

  /// Not parseable as a URL, or no host in it.
  malformed,

  /// Parsed, but the scheme is neither `http` nor `https` (`ftp:`, `file:`,
  /// a bare `example.com`, …).
  unsupportedScheme,

  /// Cleartext `http:` to a non-loopback host, in a release build.
  httpsRequired,
}

/// Result of [EndpointUrlPolicy.normalize]. [value] is the normalized text
/// (trailing slashes stripped) regardless of [problem], so a caller can show
/// it back in the field while displaying the error.
typedef EndpointUrlCheck = ({String value, EndpointUrlProblem? problem});

/// The one network-endpoint scheme policy for the whole app.
///
/// ## Why shared
///
/// Turna has exactly two user-configurable network exits, and both carry a
/// credential on every request:
///
///   - the AI base URL (`views/ai/ai_api_config_page.dart`), which sends
///     `Authorization: Bearer <key>`;
///   - the WebDAV server URL (`service/remote_backup/`), which sends Basic
///     auth — `base64(username:password)` — so a cleartext hop exposes the
///     password in a form that needs no reversal at all.
///
/// They were validated differently: the AI page checked the scheme, WebDAV
/// only trimmed slashes. One implementation removes that asymmetry, which is
/// the actual defect — a per-screen copy of the rule is what let the WebDAV
/// exit drift in the first place.
///
/// ## The rule
///
/// Release builds require `https`, except to loopback hosts, which stay
/// reachable so a user can test against a local server without the app
/// learning to accept cleartext credentials in the field. Debug builds allow
/// plain HTTP generally. This is the AI page's pre-existing behaviour,
/// preserved exactly so extracting it changes no shipped behaviour.
abstract final class EndpointUrlPolicy {
  /// Normalize and validate a user-typed endpoint URL.
  static EndpointUrlCheck normalize(String raw) =>
      _normalize(raw, debugBuild: kDebugMode);

  /// [normalize] with the build-mode gate pinned by the caller.
  ///
  /// The release rule has two branches — "https required" and "plain HTTP
  /// allowed" — and a test run only ever exercises one of them, because
  /// `kDebugMode` is fixed for the whole process. Pinning it lets a single
  /// test run prove both, instead of leaving the release branch verified
  /// only by reasoning.
  @visibleForTesting
  static EndpointUrlCheck normalizeForBuild(String raw,
          {required bool debugBuild}) =>
      _normalize(raw, debugBuild: debugBuild);

  static EndpointUrlCheck _normalize(String raw, {required bool debugBuild}) {
    final value = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.isEmpty) {
      return (value: '', problem: EndpointUrlProblem.empty);
    }

    final Uri uri;
    try {
      uri = Uri.parse(value);
    } on FormatException {
      return (value: value, problem: EndpointUrlProblem.malformed);
    }

    final isHttps = uri.scheme == 'https';
    final isHttp = uri.scheme == 'http';
    if (!isHttp && !isHttps) {
      return (value: value, problem: EndpointUrlProblem.unsupportedScheme);
    }
    if (uri.host.isEmpty) {
      return (value: value, problem: EndpointUrlProblem.malformed);
    }
    if (isHttp && !debugBuild && !isLoopbackHost(uri.host)) {
      return (value: value, problem: EndpointUrlProblem.httpsRequired);
    }
    return (value: value, problem: null);
  }

  /// Loopback in the forms a user actually types. `[::1]` is how [Uri.host]
  /// renders the IPv6 loopback literal, and `0.0.0.0` is included because
  /// binding a dev server to all interfaces and pointing the app at it is a
  /// common desktop habit.
  static bool isLoopbackHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '[::1]' ||
        h == '0.0.0.0';
  }
}
