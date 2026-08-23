// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

/// Single auto-scroll policy for streaming chat pages (Plan 3 §21.3).
///
/// Responsibilities:
///   * follow the stream only while the user is already near the bottom;
///   * lock following when the user scrolls up (never fight the user) and
///     unlock when they return to the bottom;
///   * throttle follow-scrolls to at most one per [minInterval] — many
///     network batches must not queue many animations;
///   * jump (no animation) when a new message is appended, animate briefly
///     for content growth, and cancel everything on [dispose].
///
/// The page reports user intent from a `NotificationListener<UserScroll-
/// Notification>` (user drags only, not the coordinator's own animations)
/// via [lockFollow] / [unlockFollow].
class ChatAutoScrollCoordinator {
  ChatAutoScrollCoordinator({
    this.minInterval = const Duration(milliseconds: 90),
    this.nearBottomThreshold = 120,
    this.followDuration = const Duration(milliseconds: 120),
  });

  final Duration minInterval;
  final double nearBottomThreshold;
  final Duration followDuration;

  ScrollController? _controller;
  bool _followLocked = false;
  DateTime _lastFollow = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingFollow;
  bool _disposed = false;

  int _scheduledFollows = 0;

  /// Number of scroll animations actually scheduled — tests assert this is
  /// bounded by the throttle, not equal to the number of content updates.
  @visibleForTesting
  int get scheduledFollows => _scheduledFollows;

  @visibleForTesting
  bool get followLocked => _followLocked;

  void attach(ScrollController controller) {
    _controller = controller;
  }

  /// The user dragged toward earlier content: stop following until they
  /// explicitly return to the bottom.
  void lockFollow() => _followLocked = true;

  /// The user came back to (near) the bottom: resume following.
  void unlockFollow() => _followLocked = false;

  /// A new message was appended (bubble count grew): jump, don't animate.
  void onMessagesAppended() {
    if (_disposed) return;
    _scheduleFollow(jump: true);
  }

  /// Streaming content grew: follow with a short animation, throttled and
  /// skipped entirely while the user is reading earlier content.
  void onContentChanged() {
    if (_disposed || _followLocked) return;
    _scheduleFollow(jump: false);
  }

  /// The stream ended: settle at the bottom once if following.
  void onStreamFinished() {
    if (_disposed || _followLocked) return;
    _scheduleFollow(jump: false, force: true);
  }

  void _scheduleFollow({required bool jump, bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    if (_followLocked && !jump) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastFollow) < minInterval) {
      // Coalesce: at most ONE pending follow, replacing any earlier pending
      // one (never queue a second animation behind the first).
      _pendingFollow?.cancel();
      _pendingFollow = Timer(minInterval, () {
        _pendingFollow = null;
        _apply(jump: jump);
      });
      return;
    }
    _apply(jump: jump);
  }

  void _apply({required bool jump}) {
    final controller = _controller;
    if (_disposed || controller == null || !controller.hasClients) return;
    _lastFollow = DateTime.now();
    _scheduledFollows++;
    final target = controller.position.maxScrollExtent;
    if (jump) {
      controller.jumpTo(target);
    } else {
      controller.animateTo(
        target,
        duration: followDuration,
        curve: Curves.easeOut,
      );
    }
  }

  /// Cancel pending timers; the page calls this in dispose.
  void dispose() {
    _disposed = true;
    _pendingFollow?.cancel();
    _pendingFollow = null;
    _controller = null;
  }
}
