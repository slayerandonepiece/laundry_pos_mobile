import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/models/store_profile_model.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/owner/presentation/owner_profile_screen.dart';
import 'package:myshop/features/owner/presentation/payment_methods_screen.dart';
import 'package:myshop/features/owner/presentation/staff_screen.dart';
import 'package:myshop/features/owner/presentation/store_profile_screen.dart';
import 'package:myshop/shared/widgets/sync_status_bar.dart';

class TrackingOwnerBloc extends Bloc<OwnerEvent, OwnerState>
    implements OwnerBloc {
  final List<OwnerEvent> dispatchedEvents = [];

  TrackingOwnerBloc([OwnerState? initialState])
    : super(
        initialState ??
            OwnerState(
              metrics: DashboardMetrics(),
              expenses: [
                Expense(
                  id: 'exp-1',
                  title: 'Detergent',
                  category: 'Supplies',
                  amount: 5000,
                  due: '2026-09-12',
                ),
              ],
              staff: [
                StaffMember(
                  id: 'staff-1',
                  name: 'Alex Staff',
                  username: 'alex',
                  active: true,
                ),
              ],
              paymentMethods: [
                StorePaymentMethod(
                  id: 'pm-1',
                  name: 'Cash',
                  type: 'Cash',
                  active: true,
                ),
              ],
              storeProfile: StoreProfile(
                store: 'Main Laundromat',
                address: '100 Main St',
                phone: '9876543210',
                name: 'Owner Name',
                email: 'owner@example.com',
              ),
            ),
      ) {
    on<OwnerEvent>((event, emit) {
      dispatchedEvents.add(event);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  FakeAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOrdersBloc extends Bloc<OrdersEvent, OrdersState>
    implements OrdersBloc {
  FakeOrdersBloc() : super(OrdersState()) {
    on<OrdersEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestApp({
    required Widget child,
    required TrackingOwnerBloc ownerBloc,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<OwnerBloc>.value(value: ownerBloc),
        BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
        BlocProvider<OrdersBloc>(create: (_) => FakeOrdersBloc()),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Owner Screens SyncStatusBar and Reload Button Affordance Tests', () {
    testWidgets(
      'OwnerDashboardScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const OwnerDashboardScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        await tester.tap(refreshIcon);
        await tester.pump();
        expect(
          bloc.dispatchedEvents.any((e) => e is LoadDashboardEvent),
          isTrue,
        );
      },
    );

    testWidgets(
      'ExpensesScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const ExpensesScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        await tester.tap(refreshIcon);
        await tester.pump();
        expect(
          bloc.dispatchedEvents.any((e) => e is LoadExpensesEvent),
          isTrue,
        );
      },
    );

    testWidgets(
      'StaffScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const StaffScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        await tester.tap(refreshIcon);
        await tester.pump();
        expect(bloc.dispatchedEvents.any((e) => e is LoadStaffEvent), isTrue);
      },
    );

    testWidgets(
      'PaymentMethodsScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const PaymentMethodsScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        await tester.tap(refreshIcon);
        await tester.pump();
        expect(
          bloc.dispatchedEvents.any((e) => e is LoadPaymentMethodsEvent),
          isTrue,
        );
      },
    );

    testWidgets(
      'StoreProfileScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const StoreProfileScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        bloc.dispatchedEvents.clear();
        await tester.tap(refreshIcon);
        await tester.pump();
        expect(
          bloc.dispatchedEvents.any((e) => e is LoadStoreProfileEvent),
          isTrue,
        );
      },
    );

    testWidgets(
      'OwnerProfileScreen contains SyncStatusBar and manual reload icon button',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(
          buildTestApp(child: const OwnerProfileScreen(), ownerBloc: bloc),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBar), findsOneWidget);
        final refreshIcon = find.byIcon(Icons.refresh_rounded);
        expect(refreshIcon, findsOneWidget);

        bloc.dispatchedEvents.clear();
        await tester.tap(refreshIcon);
        await tester.pump();
        expect(
          bloc.dispatchedEvents.any((e) => e is LoadStoreProfileEvent),
          isTrue,
        );
      },
    );
  });
}
