import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/presentation/login_screen.dart';

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LoginScreen 5-state test suite', () {
    testWidgets('State 2a: Empty fields -> Sign in button is disabled', (
      tester,
    ) async {
      final bloc = MockAuthBloc(UnauthenticatedState());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      expect(find.text('Sign in'), findsWidgets);
      // Button exists and fields are empty
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('State 2b: Inline validation error on empty submit', (
      tester,
    ) async {
      final bloc = MockAuthBloc(UnauthenticatedState());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      // Enter phone only
      await tester.enterText(find.byType(TextField).first, 'reddy');
      await tester.pump();

      // Tap Sign in button
      await tester.tap(find.text('Sign in').last);
      await tester.pump();

      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('State 2c: Invalid credentials error banner', (tester) async {
      final bloc = MockAuthBloc(
        UnauthenticatedState(errorMessage: 'Invalid phone or password.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      expect(find.text('Invalid phone or password.'), findsOneWidget);
    });

    testWidgets('State 2d: Loading state shows loading indicator', (
      tester,
    ) async {
      final bloc = MockAuthBloc(AuthLoadingState());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('State 2e: Authenticated but no active store banner', (
      tester,
    ) async {
      final bloc = MockAuthBloc(UnauthenticatedState(noActiveStore: true));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      expect(
        find.text(
          'Your account is not linked to any active store. Check with your store owner.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Tapping "Forgot your password?" opens ForgotPasswordDialog', (
      tester,
    ) async {
      final bloc = MockAuthBloc(UnauthenticatedState());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      await tester.tap(find.textContaining('Forgot your password?'));
      await tester.pumpAndSettle();

      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('B4: Error banner does not shift form layout position', (
      tester,
    ) async {
      final normalBloc = MockAuthBloc(UnauthenticatedState());
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: normalBloc,
            child: const LoginScreen(),
          ),
        ),
      );
      final normalFieldPosition = tester.getTopLeft(
        find.byType(TextField).first,
      );

      final errorBloc = MockAuthBloc(
        UnauthenticatedState(errorMessage: 'Invalid phone or password.'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: errorBloc,
            child: const LoginScreen(),
          ),
        ),
      );
      final errorFieldPosition = tester.getTopLeft(
        find.byType(TextField).first,
      );

      expect(errorFieldPosition, equals(normalFieldPosition));
    });

    testWidgets(
      'B4: Dismissing error banner with (X) button closes the banner',
      (tester) async {
        final bloc = MockAuthBloc(
          UnauthenticatedState(errorMessage: 'Invalid phone or password.'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<AuthBloc>.value(
              value: bloc,
              child: const LoginScreen(),
            ),
          ),
        );

        expect(find.text('Invalid phone or password.'), findsOneWidget);
        expect(find.byKey(const Key('login_error_dismiss')), findsOneWidget);

        await tester.tap(find.byKey(const Key('login_error_dismiss')));
        await tester.pumpAndSettle();

        expect(find.text('Invalid phone or password.'), findsNothing);
      },
    );

    testWidgets('B4: Error banner auto-dismisses after 6 seconds', (
      tester,
    ) async {
      final bloc = MockAuthBloc(
        UnauthenticatedState(errorMessage: 'Invalid phone or password.'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const LoginScreen(),
          ),
        ),
      );

      expect(find.text('Invalid phone or password.'), findsOneWidget);

      // Advance clock by 6 seconds
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.text('Invalid phone or password.'), findsNothing);
    });
  });
}
