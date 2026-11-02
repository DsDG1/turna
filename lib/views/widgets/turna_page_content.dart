import 'package:flutter/material.dart';

class TurnaPageContent extends StatelessWidget {
  const TurnaPageContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    return Align(alignment: alignment, child: content);
  }
}
