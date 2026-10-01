import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/network/firebase_service.dart';
import 'package:myshop/features/maintenance/presentation/maintenance_screen.dart';

void main() {
  group('MaintenanceScreen Widget Tests', () {
    testWidgets(
      'Renders all required brand elements, heading, and default message',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: MaintenanceScreen()));

        // Verify Scaffold background is Deep Hydro (#0A2540)
        final scaffoldFinder = find.byType(Scaffold);
        expect(scaffoldFinder, findsOneWidget);
        final Scaffold scaffold = tester.widget(scaffoldFinder);
        expect(scaffold.backgroundColor, equals(AppColors.brandDeepHydro));

        // Verify Non-dismissible PopScope
        final popScopeFinder = find.byType(PopScope);
        expect(popScopeFinder, findsOneWidget);
        final PopScope popScope = tester.widget(popScopeFinder);
        expect(popScope.canPop, isFalse);

        // Verify circular badge with Crisp Mint (#4CFFB3)
        final badgeContainerFinder = find.ancestor(
          of: find.byIcon(Icons.build_rounded),
          matching: find.byType(Container),
        );
        expect(badgeContainerFinder, findsOneWidget);
        final Container badgeContainer = tester.widget(
          badgeContainerFinder.first,
        );
        final decoration = badgeContainer.decoration as BoxDecoration;
        expect(decoration.color, equals(AppColors.brandCrispMint));
        expect(decoration.shape, equals(BoxShape.circle));

        // Verify Heading
        expect(find.text('Down for maintenance.'), findsOneWidget);

        // Verify Body Text comes from FirebaseService.maintenanceMessage
        expect(find.text(FirebaseService.maintenanceMessage), findsOneWidget);

        // Verify "Check again" outlined button
        final buttonFinder = find.widgetWithText(OutlinedButton, 'Check again');
        expect(buttonFinder, findsOneWidget);
      },
    );

    testWidgets('Renders custom message and ETA when non-empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MaintenanceScreen(
            message: 'Custom maintenance message for testing.',
            eta: '2:00 PM UTC',
          ),
        ),
      );

      expect(
        find.text('Custom maintenance message for testing.'),
        findsOneWidget,
      );
      expect(find.text('2:00 PM UTC'), findsOneWidget);
    });

    testWidgets('Does NOT render ETA caption or fallback when eta is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MaintenanceScreen(message: 'Ongoing upgrade', eta: ''),
        ),
      );

      expect(find.text('Ongoing upgrade'), findsOneWidget);
      // Ensure no fallback ETA text exists
      expect(find.textContaining('Expected back'), findsNothing);
      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets(
      'Tapping "Check again" invokes callback and handles loading indicator',
      (WidgetTester tester) async {
        bool checkAgainCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: MaintenanceScreen(
              onCheckAgain: () async {
                checkAgainCalled = true;
              },
            ),
          ),
        );

        final button = find.widgetWithText(OutlinedButton, 'Check again');
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pump();

        expect(checkAgainCalled, isTrue);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Does not contain hardcoded "KlenPOS" in non-dynamic UI text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MaintenanceScreen(
            message: 'Generic service maintenance in progress.',
            eta: '',
          ),
        ),
      );

      // When dynamic message does not mention KlenPOS, no other widget has it hardcoded
      expect(find.textContaining('KlenPOS'), findsNothing);
      expect(find.text('Down for maintenance.'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
    });
  });
}
