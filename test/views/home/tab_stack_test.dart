// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/views/home/components/tab_stack.dart';

/// Verifies the TabStack contract: native-default instant switching (no
/// transition frames), children stay mounted (state preserved across
/// switches), hidden tabs are offstage + ticker-disabled + semantics-excluded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget pumpStack(WidgetTester tester, {required int index}) {
    return MaterialApp(
      home: Scaffold(
        body: TabStack(
          index: index,
          children: const [
            _CounterScreen(label: 'tab-a'),
            _CounterScreen(label: 'tab-b'),
          ],
        ),
      ),
    );
  }

  testWidgets('keeps inactive children mounted and preserves their state',
      (tester) async {
    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pumpAndSettle();

    // Increment tab A's counter, then switch away and back.
    await tester.tap(find.text('tab-a:0'));
    await tester.pump();
    expect(find.text('tab-a:1'), findsOneWidget);

    await tester.pumpWidget(pumpStack(tester, index: 1));
    await tester.pumpAndSettle();
    expect(find.text('tab-b:0'), findsOneWidget);
    // Hidden tab stays mounted (state alive) but offstage: its text exists in
    // the widget tree yet must not be visible for semantics.
    expect(find.text('tab-a:1', skipOffstage: false), findsOneWidget);

    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pumpAndSettle();
    expect(find.text('tab-a:1'), findsOneWidget);
  });

  testWidgets('switches instantly without any transition frames',
      (tester) async {
    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(pumpStack(tester, index: 1));
    await tester.pump(const Duration(milliseconds: 1));
    // Native-default behavior: the new tab is fully visible on the switch
    // frame and no ticker runs afterwards.
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('tab-b:0'), findsOneWidget);
  });

  testWidgets('same index rebuild does not animate', (tester) async {
    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('hidden tab content is excluded from semantics',
      (tester) async {
    await tester.pumpWidget(pumpStack(tester, index: 0));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp(r'tab-b')),
      findsNothing,
    );
  });
}

/// A minimal stateful screen that proves state preservation across switches.
class _CounterScreen extends StatefulWidget {
  final String label;

  const _CounterScreen({required this.label});

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: '${widget.label}:$_count',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => setState(() => _count++),
          child: Text('${widget.label}:$_count'),
        ),
      ),
    );
  }
}
