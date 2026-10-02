import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_inset.dart';
import 'package:myshop/shared/widgets/blocked_screen.dart';

Widget createTestApp(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  group('BlockedScreen', () {
    testWidgets('"Try again" button dispatches onRetry callback', (
      tester,
    ) async {
      bool retried = false;
      bool signedOut = false;

      await tester.pumpWidget(
        createTestApp(
          BlockedScreen(
            reason: 'membership_inactive',
            isOwner: false,
            onRetry: () => retried = true,
            onSignOut: () => signedOut = true,
          ),
        ),
      );

      final tryAgainFinder = find.widgetWithText(PrimaryButton, 'Try again');
      expect(tryAgainFinder, findsOneWidget);

      await tester.tap(tryAgainFinder);
      await tester.pump();

      expect(retried, isTrue);
      expect(signedOut, isFalse);
    });

    testWidgets('"Sign out" button dispatches onSignOut callback', (
      tester,
    ) async {
      bool retried = false;
      bool signedOut = false;

      await tester.pumpWidget(
        createTestApp(
          BlockedScreen(
            reason: 'store_locked',
            isOwner: true,
            onRetry: () => retried = true,
            onSignOut: () => signedOut = true,
          ),
        ),
      );

      final signOutFinder = find.widgetWithText(SecondaryButton, 'Sign out');
      expect(signOutFinder, findsOneWidget);

      await tester.tap(signOutFinder);
      await tester.pump();

      expect(signedOut, isTrue);
      expect(retried, isFalse);
    });

    testWidgets(
      'pendingCount > 0 renders note with correct count in text (plural)',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            BlockedScreen(
              reason: 'store_locked',
              isOwner: true,
              onRetry: () {},
              onSignOut: () {},
              pendingCount: 4,
            ),
          ),
        );

        expect(find.byType(AppInset), findsOneWidget);
        expect(
          find.text(
            "4 actions saved on this device haven't synced yet. They'll go through automatically once your access is restored.",
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
      },
    );

    testWidgets('pendingCount == 1 renders note with singular action wording', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          BlockedScreen(
            reason: 'store_locked',
            isOwner: false,
            onRetry: () {},
            onSignOut: () {},
            pendingCount: 1,
          ),
        ),
      );

      expect(find.byType(AppInset), findsOneWidget);
      expect(
        find.text(
          "1 action saved on this device haven't synced yet. They'll go through automatically once your access is restored.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('pendingCount == 0 renders nothing extra (no pending note)', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          BlockedScreen(
            reason: 'store_locked',
            isOwner: false,
            onRetry: () {},
            onSignOut: () {},
            pendingCount: 0,
          ),
        ),
      );

      expect(find.byType(AppInset), findsNothing);
      expect(find.textContaining("haven't synced yet"), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_rounded), findsNothing);
    });

    testWidgets('pendingCount null renders nothing extra (no pending note)', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          BlockedScreen(
            reason: 'store_locked',
            isOwner: false,
            onRetry: () {},
            onSignOut: () {},
            pendingCount: null,
          ),
        ),
      );

      expect(find.byType(AppInset), findsNothing);
      expect(find.textContaining("haven't synced yet"), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_rounded), findsNothing);
    });

    group('billing_pending (F4)', () {
      testWidgets(
        'Owner copy points to the platform administrator, makes no payment promise, and keeps Retry',
        (tester) async {
          bool retried = false;
          await tester.pumpWidget(
            createTestApp(
              BlockedScreen(
                reason: 'billing_pending',
                isOwner: true,
                onRetry: () => retried = true,
                onSignOut: () {},
              ),
            ),
          );

          expect(find.text('Billing not completed'), findsOneWidget);
          expect(
            find.text(
              'Your store account setup is pending billing completion. Contact your platform administrator to complete setup.',
            ),
            findsOneWidget,
          );
          // No self-serve payment route exists for owners, so the screen must
          // not promise one.
          expect(find.textContaining('Complete payment'), findsNothing);
          expect(find.textContaining('web dashboard'), findsNothing);
          expect(
            find.text('Ask your owner to complete billing.'),
            findsNothing,
          );
          expect(
            find.widgetWithText(PrimaryButton, 'Complete payment'),
            findsNothing,
          );

          final retryBtn = find.widgetWithText(PrimaryButton, 'Retry');
          expect(retryBtn, findsOneWidget);

          await tester.tap(retryBtn);
          await tester.pump();
          expect(retried, isTrue);
        },
      );

      testWidgets(
        'Employee copy, no complete payment button, no call owner button, and Retry button',
        (tester) async {
          bool retried = false;
          await tester.pumpWidget(
            createTestApp(
              BlockedScreen(
                reason: 'billing_pending',
                isOwner: false,
                ownerPhone: '9876543210',
                onRetry: () => retried = true,
                onSignOut: () {},
              ),
            ),
          );

          expect(find.text('Billing not completed'), findsOneWidget);
          expect(
            find.text('Ask your owner to complete billing.'),
            findsOneWidget,
          );
          expect(
            find.text('Complete payment to start using your organization.'),
            findsNothing,
          );
          expect(
            find.text('Complete payment on the KlenPOS web dashboard'),
            findsNothing,
          );
          expect(
            find.widgetWithText(PrimaryButton, 'Complete payment'),
            findsNothing,
          );
          expect(
            find.widgetWithText(PrimaryButton, 'Call store owner'),
            findsNothing,
          );

          final retryBtn = find.widgetWithText(PrimaryButton, 'Retry');
          expect(retryBtn, findsOneWidget);

          await tester.tap(retryBtn);
          await tester.pump();
          expect(retried, isTrue);
        },
      );
    });
  });
}
