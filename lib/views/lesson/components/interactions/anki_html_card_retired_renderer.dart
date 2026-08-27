// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/theme.dart';

/// Placeholder for [AnkiHtmlCard] items persisted by retired Legacy imports
/// (doc 35 L2 deleted the NoteStore fidelity renderer). Official review
/// still renders fidelity HTML through its own surface — this renderer only
/// covers lesson bodies and mistake-log replays that still carry the type,
/// so they degrade to an acknowledge-and-continue card instead of throwing
/// in [lookupRenderer].
@injectable
class AnkiHtmlCardRetiredRenderer extends InteractionRenderer {
  @override
  Type get handlesType => AnkiHtmlCard;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    return _RetiredAnkiHtmlCardBody(onSubmit: onSubmit);
  }
}

class _RetiredAnkiHtmlCardBody extends StatelessWidget {
  const _RetiredAnkiHtmlCardBody({required this.onSubmit});

  final OnInteractionSubmit onSubmit;

  @override
  Widget build(BuildContext context) {
    return InteractionBody(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.style_outlined,
                size: 40,
                color: TurnaTheme.brandTeal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '旧版导入的 Anki 卡片',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '该卡片来自已停用的旧版导入源，已不再逐卡渲染。\n请通过「设置 → 旧版与兼容性」迁移到官方引擎。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            LessonCheckButton(
              label: '继续',
              enabled: true,
              onPressed: () => onSubmit(true),
            ),
          ],
        ),
      ),
    );
  }
}
