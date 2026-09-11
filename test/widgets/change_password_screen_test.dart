import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/profile/presentation/change_password_screen.dart';

class MockAuthRepository implements AuthRepository {
  bool throwError = false;
  String errorMessage = 'Current password is incorrect.';
  String? passedOldPassword;
  String? passedNewPassword;
  int changePasswordCallCount = 0;

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    changePasswordCallCount++;
    passedOldPassword = currentPassword;
    passedNewPassword = newPassword;
    if (throwError) {
      throw Exception(errorMessage);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = MockAuthRepository();
  });

  Widget buildTestWidget() {
    return RepositoryProvider<AuthRepository>.value(
      value: mockRepo,
      child: const MaterialApp(home: ChangePasswordScreen()),
    );
  }

  testWidgets(
    'ChangePasswordScreen validates fields and submits successfully',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Change password'), findsOneWidget);
      expect(find.text('CURRENT PASSWORD'), findsOneWidget);
      expect(find.text('NEW PASSWORD'), findsOneWidget);
      expect(find.text('CONFIRM NEW PASSWORD'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      // Initially submit button should be disabled
      final submitFinder = find.widgetWithText(
        ElevatedButton,
        'Change password',
      );
      expect(tester.widget<ElevatedButton>(submitFinder).enabled, isFalse);

      // Enter short new password (< 8 chars)
      await tester.enterText(fields.at(0), 'oldpass123');
      await tester.enterText(fields.at(1), 'short');
      await tester.enterText(fields.at(2), 'short');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitFinder).enabled, isFalse);

      // Enter valid 8+ chars matching passwords
      await tester.enterText(fields.at(1), 'newsecret123');
      await tester.enterText(fields.at(2), 'newsecret123');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitFinder).enabled, isTrue);

      // Submit valid password change
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(mockRepo.changePasswordCallCount, equals(1));
      expect(mockRepo.passedOldPassword, equals('oldpass123'));
      expect(mockRepo.passedNewPassword, equals('newsecret123'));
      expect(find.text('Password updated successfully.'), findsOneWidget);
    },
  );

  testWidgets(
    'ChangePasswordScreen surfaces server error when submission fails',
    (tester) async {
      mockRepo.throwError = true;
      mockRepo.errorMessage = 'Current password is incorrect.';

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'wrongpass');
      await tester.enterText(fields.at(1), 'newsecret123');
      await tester.enterText(fields.at(2), 'newsecret123');
      await tester.pumpAndSettle();

      final submitFinder = find.widgetWithText(
        ElevatedButton,
        'Change password',
      );
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(mockRepo.changePasswordCallCount, equals(1));
      expect(find.text('Current password is incorrect.'), findsOneWidget);
    },
  );
}
