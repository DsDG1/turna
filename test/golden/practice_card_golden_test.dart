@Tags(['golden'])
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_practice_card.dart';

/// 做题链路两张核心卡片的 golden 基线。
///
/// 这两个组件是全项目改动最频繁、却长期没有视觉回归网的地方：
/// `677137b1` 那次 25 个文件的质感升级完全没有 golden 兜底。
///
/// 覆盖：`InteractionOptionTile` 四态（默认 / 选中 / 正确 / 错误）+
/// `LessonPracticeCard` front / back 两变体。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TurnaTheme.lightTheme,
        darkTheme: TurnaTheme.darkTheme,
        themeMode: mode,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (ctx) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'OPTION STATES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: TurnaTheme.textHintColor(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InteractionOptionTile(
                    label: 'merhaba',
                    index: 1,
                    isSelected: false,
                    isCorrect: false,
                    isWrong: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  InteractionOptionTile(
                    label: 'günaydın',
                    index: 2,
                    isSelected: true,
                    isCorrect: false,
                    isWrong: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  InteractionOptionTile(
                    label: 'teşekkürler',
                    index: 3,
                    isSelected: true,
                    isCorrect: true,
                    isWrong: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  InteractionOptionTile(
                    label: 'hoşça kal',
                    index: 4,
                    isSelected: true,
                    isCorrect: false,
                    isWrong: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'PRACTICE CARD',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: TurnaTheme.textHintColor(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LessonPracticeCard(
                    appearAnimation: false,
                    minHeight: 110,
                    child: Center(
                      child: Text(
                        'Merhaba',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: TurnaTheme.textPrimaryColor(ctx),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LessonPracticeCard(
                    appearAnimation: false,
                    minHeight: 110,
                    variant: LessonPracticeCardVariant.back,
                    child: Center(
                      child: Text(
                        'Merhaba · 你好',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.textPrimaryColor(ctx),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('practice card light golden', (tester) async {
    await pump(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/practice_card_light.png'),
    );
  });

  testWidgets('practice card dark golden', (tester) async {
    await pump(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/practice_card_dark.png'),
    );
  });
}
