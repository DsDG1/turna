// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/gems_provider.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/loader.dart';

class GemsDisplay extends StatelessWidget {
  const GemsDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, color: TurnaTheme.error, size: 18),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GemsProvider>().getGemsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }

              final gems = snapshot.data ?? 0;
              return Text(
                '$gems',
                style: const TextStyle(
                  color: TurnaTheme.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
