// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

class Loader extends StatelessWidget {
  const Loader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 12,
      width: 12,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        color: VarnamalaTheme.warning,
      ),
    );
  }
}
