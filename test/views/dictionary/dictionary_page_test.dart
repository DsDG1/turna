// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/dictionary/dictionary_page.dart';

/// R11 词条阅读目录的版面契约：搜索起点 + 防抖 + 目录行 + 词条正文 +
/// 宽屏两栏。点读与 AI 讲解的数据接缝（AudioController / DI）不在本文件
/// 覆盖范围 —— 它们未随版面翻新改动。
void main() {
  setUp(() {
    vocabById
      ..clear()
      ..addAll({
        'w-1': const WordEntry(
          id: 'w-1',
          term: 'Habari',
          translation: 'Hello',
          pronunciation: 'ha-BA-ri',
        ),
        'w-2': const WordEntry(
          id: 'w-2',
          term: 'Asante',
          translation: 'Thank you',
        ),
      });
    expressionsById.clear();
    grammarPointById.clear();
  });

  tearDown(() {
    vocabById.clear();
    expressionsById.clear();
    grammarPointById.clear();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: const DictionaryPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('landing shows the full entry directory before any query',
      (tester) async {
    await pumpPage(tester);

    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsOneWidget);
    expect(find.text(AppStrings.dictionaryAllEntriesCount(2)), findsOneWidget);
    expect(find.text('Habari'), findsOneWidget);
    expect(find.text('Asante'), findsOneWidget);
    // 无课时链接时元信息只保留类型。
    expect(find.text(AppStrings.dictionaryKindWord), findsNWidgets(2));
  });

  testWidgets('typing shows the searching state, then debounced results',
      (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'hab');
    // 防抖窗口内：搜索框尾部是 spinner（输入中态由 TurnaSearchField 承担）。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 终值落地：只剩命中行，节头消失。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Habari'), findsOneWidget);
    expect(find.text('Asante'), findsNothing);
    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsNothing);
  });

  testWidgets('no matches falls back to the empty state', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(AppStrings.dictionaryNoMatches), findsOneWidget);
  });

  testWidgets('clear returns to the full directory without waiting the debounce',
      (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'hab');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Asante'), findsNothing);

    // 清除键立即回调（清空不该等防抖）：单帧后即回全部目录。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsOneWidget);
    expect(find.text('Asante'), findsOneWidget);
  });

  testWidgets('narrow screens swap the list for the entry detail', (tester) async {
    // 默认测试画布 800×600 逻辑宽 < 840 → 单栏。
    await pumpPage(tester);

    await tester.tap(find.text('Habari'));
    await tester.pumpAndSettle();

    // 词条正文：主词 + 发音 + 44 点读键 + 返回目录。
    expect(find.byTooltip(AppStrings.dictionaryPlayPronunciation), findsOneWidget);
    expect(find.text('ha-BA-ri'), findsOneWidget);
    expect(find.text(AppStrings.dictionaryBackToList), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);

    await tester.tap(find.text(AppStrings.dictionaryBackToList));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsOneWidget);
    expect(
      find.byTooltip(AppStrings.dictionaryPlayPronunciation),
      findsNothing,
    );
  });

  testWidgets('wide screens show index and entry side by side', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPage(tester);

    // 未选词条时右栏是选择提示，目录仍在。
    expect(find.text(AppStrings.dictionaryPickPrompt), findsOneWidget);
    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsOneWidget);

    await tester.tap(find.text('Habari'));
    await tester.pumpAndSettle();

    // 并排：目录与词条正文同屏，且没有返回键（返回语义属于单栏）。
    expect(find.text(AppStrings.dictionaryAllEntriesTitle), findsOneWidget);
    expect(find.byTooltip(AppStrings.dictionaryPlayPronunciation), findsOneWidget);
    expect(find.text(AppStrings.dictionaryBackToList), findsNothing);
  });

  testWidgets('grammar entries read as paragraphs with example expressions',
      (tester) async {
    grammarPointById['g-1'] = const GrammarPoint(
      id: 'g-1',
      title: 'Vowel harmony',
      explanation: 'Line one.\nLine two.',
      exampleExpressionIds: ['e-1'],
    );
    expressionsById['e-1'] = const Expression(
      id: 'e-1',
      term: 'merhaba arkadaş',
      translation: 'hello friend',
    );

    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'vowel');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Vowel harmony'));
    await tester.pumpAndSettle();

    // 释义按换行分段连续阅读；例句来自语法点挂接的表达（现有数据源）。
    expect(find.text('Line one.'), findsOneWidget);
    expect(find.text('Line two.'), findsOneWidget);
    expect(find.text(AppStrings.dictionaryExamplesTitle), findsOneWidget);
    expect(find.text('merhaba arkadaş'), findsOneWidget);
    expect(find.text('hello friend'), findsOneWidget);
  });

  testWidgets('rows carry source lesson and learned meta from the link store',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    final linkStore = LessonLinkStore(AppPrefs(preferences));
    await linkStore.upsertFirstSeen(
      ids: const ['w-1'],
      lessonId: 'l-1',
      lessonName: 'Greetings',
      type: LinkType.word,
    );
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<LessonLinkStore>(linkStore);

    await pumpPage(tester);

    expect(find.text('单词 · Greetings · 已学'), findsOneWidget);
    expect(find.text(AppStrings.dictionaryKindWord), findsOneWidget);
  });
}
