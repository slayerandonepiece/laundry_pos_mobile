import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/presentation/dialogs/forgot_password_dialog.dart';
import 'package:myshop/shared/widgets/app_button.dart';

void main() {
  group('ForgotPasswordDialog Tests', () {
    testWidgets(
      'Renders explanation, call button when phone provided, and dismisses on Got it',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ForgotPasswordDialog.show(
                    context,
                    storePhone: '9876543210',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Forgot password?'), findsOneWidget);
        expect(
          find.text(
            'Your store owner can reset your password for you from the Staff settings.',
          ),
          findsOneWidget,
        );
        expect(find.text('Call store owner'), findsOneWidget);
        expect(find.text('Got it'), findsOneWidget);

        await tester.tap(find.widgetWithText(SecondaryButton, 'Got it'));
        await tester.pumpAndSettle();

        expect(find.text('Forgot password?'), findsNothing);
      },
    );

    testWidgets('Does not show call button when phone is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ForgotPasswordDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Call store owner'), findsNothing);
      expect(find.text('Got it'), findsOneWidget);
    });
  });
}
