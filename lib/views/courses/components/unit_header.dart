// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// A header label for a Unit grouping in the course tree.
///
/// Displays the unit name with a small colored accent bar on the left.
class UnitHeader extends StatelessWidget {
  final String name;

  const UnitHeader({Key? key, required this.name}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 20, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: VarnamalaTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ],
      ),
    );
  }
}
