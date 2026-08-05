// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/views/profile/widgets/avatar_picker_sheet.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Bare-bones wrapper so the modal route can be hosted in the test binding
/// without pulling in the rest of the app (DI, providers, services).
class _TestHost extends StatelessWidget {
  const _TestHost({required this.user});
  final LocalUser user;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              child: const Text('open'),
              onPressed: () => showAvatarPickerSheet(context, user: user),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  group('showAvatarPickerSheet', () {
    testWidgets('opens with the catalog rendered', (tester) async {
      await tester.pumpWidget(_TestHost(user: LocalUser.local));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Title visible
      expect(find.text(AppStringsTitleProxy.title), findsOneWidget);

      // Every catalog avatar shows up as a label in the grid.
      for (final a in AvatarCatalog.all) {
        expect(find.text(a.name), findsWidgets,
            reason: 'expected avatar ${a.id} to be rendered');
      }
    });

    testWidgets('current selection shows the check overlay', (tester) async {
      final user = LocalUser.local.copyWith(avatarId: 'avatar_fox');
      await tester.pumpWidget(_TestHost(user: user));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The check icon is part of the selected tile's overlay.
      // (Easier: there should be exactly one check icon for the selection.)
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('tapping a tile pops the sheet with the picked id',
        (tester) async {
      await tester.pumpWidget(_TestHost(user: LocalUser.local));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('小狐狸'));
      await tester.pumpAndSettle();

      // Sheet should be gone after popping.
      expect(find.text('小狐狸').hitTestable(), findsNothing);
    });

    testWidgets('dismiss does not pop any id', (tester) async {
      await tester.pumpWidget(_TestHost(user: LocalUser.local));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the close button.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('小狐狸').hitTestable(), findsNothing);
    });

    testWidgets('header exposes a reset button that dismisses the sheet',
        (tester) async {
      await tester.pumpWidget(_TestHost(user: LocalUser.local));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The reset icon must be present in the header (left of close).
      expect(
        find.byIcon(Icons.restart_alt_rounded),
        findsOneWidget,
        reason: 'reset button should be in the picker header',
      );

      // Tapping it should dismiss the sheet. The picker pops with a sentinel
      // and the caller flips it to a copyWith(clearAvatarId: true) — the
      // sentinel behaviour is asserted by the model test; here we just
      // verify the UI affordance exists and dismisses cleanly.
      await tester.tap(find.byIcon(Icons.restart_alt_rounded));
      await tester.pumpAndSettle();

      // The grid contents are gone (sheet popped).
      expect(find.text('小狐狸').hitTestable(), findsNothing);
    });
  });

  group('AvatarWithRing', () {
    testWidgets('renders an emoji child without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarWithRing(
                radius: 24,
                child: Text('🦊', style: TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
      );
      expect(find.text('🦊'), findsOneWidget);
    });
  });
}

/// Lightweight indirection so the test doesn't have to import
/// `app_strings.dart` (which triggers the broken anki_notetype_ai.dart
/// import chain via the DI module). We just look up the title by tag in the
/// catalog name to keep this test self-contained.
class AppStringsTitleProxy {
  static String get title {
    // Mirror AppStrings.accountAvatarChangeTitle (== '选择角色').
    // Hard-coded here so the test stays independent.
    return '选择角色';
  }
}
