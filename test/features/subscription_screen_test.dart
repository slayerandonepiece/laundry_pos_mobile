import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/more_screen.dart';
import 'package:myshop/features/owner/presentation/subscription_screen.dart';

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOwnerRepository implements OwnerRepository {
  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async => DashboardMetrics();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthState createAuthState({String? paidThroughDate}) {
  return AuthenticatedState(
    user: User(id: 'u1', name: 'Alice Owner', phone: 'alice'),
    currentStore: StoreSummary(
      storeId: 's1',
      storeName: 'MyShop',
      role: 'OWNER',
      paidThroughDate: paidThroughDate,
    ),
    availableStores: [
      StoreSummary(
        storeId: 's1',
        storeName: 'MyShop',
        role: 'OWNER',
        paidThroughDate: paidThroughDate,
      ),
    ],
  );
}

void main() {
  group('SubscriptionScreen Tests', () {
    testWidgets(
      '1. Active-plan state renders correctly when paidThroughDate is a future date (> 7 days)',
      (tester) async {
        final futureDate = DateTime.now().add(const Duration(days: 30));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Subscription'), findsOneWidget);
        expect(find.text('Your plan is active'), findsOneWidget);
        expect(find.text('Renews on $dateStr'), findsOneWidget);

        // Billing history placeholder
        expect(find.text('Billing history'), findsOneWidget);
        expect(
          find.text("Invoice downloads aren't available in the app yet."),
          findsOneWidget,
        );
        expect(find.text('Contact support'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Renewal-warning state renders when paidThroughDate is near (<= 7 days) or in the past',
      (tester) async {
        final nearDate = DateTime.now().add(const Duration(days: 3));
        final dateStr =
            '${nearDate.year}-${nearDate.month.toString().padLeft(2, '0')}-${nearDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Your plan renews soon'), findsOneWidget);
        expect(
          find.text('Please keep payment updated. Renews on $dateStr.'),
          findsOneWidget,
        );
        expect(find.text('Your plan is active'), findsNothing);
      },
    );

    testWidgets(
      '3. Null-date neutral state renders when paidThroughDate is null',
      (tester) async {
        final authBloc = MockAuthBloc(createAuthState(paidThroughDate: null));

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const MaterialApp(home: SubscriptionScreen()),
          ),
        );

        expect(find.text('Plan status unavailable'), findsOneWidget);
        expect(
          find.text("Plan status isn't available right now."),
          findsOneWidget,
        );
        expect(find.text('Your plan is active'), findsNothing);
        expect(find.text('Your plan renews soon'), findsNothing);
      },
    );

    testWidgets(
      '4. Tapping "Subscription" in MoreScreen navigates to SubscriptionScreen',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final futureDate = DateTime.now().add(const Duration(days: 30));
        final dateStr =
            '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

        final authBloc = MockAuthBloc(
          createAuthState(paidThroughDate: dateStr),
        );
        final ownerBloc = OwnerBloc(ownerRepository: FakeOwnerRepository());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<OwnerBloc>.value(value: ownerBloc),
            ],
            child: const MaterialApp(home: MoreScreen()),
          ),
        );

        expect(find.text('Subscription'), findsOneWidget);

        await tester.tap(find.text('Subscription'));
        await tester.pumpAndSettle();

        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(find.text('Your plan is active'), findsOneWidget);
      },
    );
  });
}
