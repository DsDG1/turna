// Flutter imports:
import 'package:flutter/material.dart';

/// Where a WebView-backed Anki card appears. Drives the sizing policy
/// (WEBVIEW-UX-2026-08 §4): lesson cards get a large-but-bounded window,
/// review/preview surfaces fill all remaining space above the action bar.
enum AnkiWebViewScene { lesson, review, officialPreview }

/// Height jitter below this threshold (logical dp) is ignored so media
/// resize storms cannot re-layout the page every frame.
const double ankiWebViewHeightEpsilon = 2.0;

/// Inputs the host page already knows: usable viewport after SafeArea,
/// orientation, keyboard inset and - once the WebView reports it - the
/// measured CSS-pixel content height.
class AnkiWebViewSizingInput {
  final Size viewport;
  final Orientation orientation;
  final AnkiWebViewScene scene;
  final double keyboardBottom;

  const AnkiWebViewSizingInput({
    required this.viewport,
    required this.orientation,
    required this.scene,
    this.keyboardBottom = 0,
  });

  bool get isTablet => viewport.shortestSide >= 600;

  bool get isLandscape => orientation == Orientation.landscape;

  bool get keyboardOpen => keyboardBottom > 0;
}

/// Sizing decisions for one card surface. [fillRemainingSpace] scenes ignore
/// the card heights and let the WebView expand into the remaining column
/// (the page must place it inside an [Expanded] / flex parent).
class AnkiWebViewSizingResult {
  /// Large initial window for lesson cards; WebView-measured height later
  /// replaces it via [resolveLessonCardHeight].
  final double initialCardHeight;
  final double minCardHeight;
  final double maxCardHeight;

  /// Review and official-preview scenes: no fixed card height, the WebView
  /// fills the area between the header and the rating/action bar.
  final bool fillRemainingSpace;

  /// Horizontal page padding. On tablets it centers content within
  /// [maxContentWidth] instead of stretching edge to edge.
  final double horizontalPadding;
  final double maxContentWidth;

  /// Gap between the card area and the bottom action bar; shrinks on short
  /// screens so buttons stay reachable without shrinking touch targets.
  final double bottomGap;

  const AnkiWebViewSizingResult({
    required this.initialCardHeight,
    required this.minCardHeight,
    required this.maxCardHeight,
    required this.fillRemainingSpace,
    required this.horizontalPadding,
    required this.maxContentWidth,
    required this.bottomGap,
  });
}

AnkiWebViewSizingResult resolveAnkiWebViewSizing(AnkiWebViewSizingInput input) {
  final tablet = input.isTablet;
  // Tablets center content within the max width instead of stretching edge
  // to edge; phones keep the standard page padding.
  final double horizontalPadding;
  if (tablet) {
    horizontalPadding =
        ((input.viewport.width - ankiWebViewTabletMaxWidth) / 2)
            .clamp(20, 1000)
            .toDouble();
  } else if (input.viewport.width < 380) {
    horizontalPadding = 16;
  } else {
    horizontalPadding = 20;
  }

  final bottomGap = (input.viewport.height * 0.03).clamp(8, 24).toDouble();

  if (input.scene != AnkiWebViewScene.lesson) {
    return AnkiWebViewSizingResult(
      initialCardHeight: input.viewport.height,
      minCardHeight: input.viewport.height,
      maxCardHeight: input.viewport.height,
      fillRemainingSpace: true,
      horizontalPadding: horizontalPadding,
      maxContentWidth: tablet ? ankiWebViewTabletMaxWidth : double.infinity,
      bottomGap: bottomGap,
    );
  }

  // Lesson cards: a generous window bounded so the outer page scroll keeps
  // the check/grade buttons reachable. Keyboard takes priority over the
  // portrait minimum (inputs and actions must stay reachable).
  final double min;
  if (input.keyboardOpen) {
    min = 200;
  } else if (input.isLandscape) {
    min = 240;
  } else {
    min = 320;
  }
  final max = input.isLandscape
      ? (input.viewport.height * 0.9).clamp(240, 720).toDouble()
      : 720.0;
  final fraction = input.isLandscape ? 0.6 : 0.52;
  final initial = (input.viewport.height * fraction).clamp(min, max).toDouble();
  return AnkiWebViewSizingResult(
    initialCardHeight: initial,
    minCardHeight: min,
    maxCardHeight: max,
    fillRemainingSpace: false,
    horizontalPadding: horizontalPadding,
    maxContentWidth: tablet ? ankiWebViewTabletMaxWidth : double.infinity,
    bottomGap: bottomGap,
  );
}

/// Merge a WebView-reported content height into the lesson card height.
///
/// The reported value is clamped to the policy bounds and jitter below
/// [ankiWebViewHeightEpsilon] keeps the current height so image/font resize
/// loops cannot pump setState through layout.
double resolveLessonCardHeight({
  required double currentHeight,
  required double? contentHeight,
  required AnkiWebViewSizingResult sizing,
}) {
  if (contentHeight == null || !contentHeight.isFinite || contentHeight <= 0) {
    return currentHeight;
  }
  final candidate =
      contentHeight.clamp(sizing.minCardHeight, sizing.maxCardHeight).toDouble();
  if ((candidate - currentHeight).abs() < ankiWebViewHeightEpsilon) {
    return currentHeight;
  }
  return candidate;
}

/// Tablet content never stretches past this width; the card area centers.
const double ankiWebViewTabletMaxWidth = 760;
