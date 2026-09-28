import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';

class FakeLocalCache extends LocalCacheService {
  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'OWNER'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => null;
  @override
  String? getActiveOutletId() => null;
  @override
  bool isAllOutletsScope() => false;
  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
}

class FakeDashboardOwnerRepo implements OwnerRepository {
  DashboardMetrics metrics;
  int getDashboardMetricsCallCount = 0;

  FakeDashboardOwnerRepo({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    getDashboardMetricsCallCount++;
    return metrics;
  }

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOrdersRepo implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Navigation Tab Reset Tests', () {
    late FakeDashboardOwnerRepo fakeOwnerRepo;
    late FakeOrdersRepo fakeOrdersRepo;
    late FakePosRepo fakePosRepo;
    late OwnerBloc ownerBloc;
    late OrdersBloc ordersBloc;
    late CartBloc cartBloc;
    late MockAuthBloc authBloc;
    late OutletScopeCubit outletScopeCubit;

    setUp(() {
      fakeOwnerRepo = FakeDashboardOwnerRepo(
        metrics: DashboardMetrics(
          todaySales: 50000,
          todayCount: 2,
          periodSales: 120000,
          periodOrders: 5,
          outstanding: 30000,
          todo: 3,
          completed: 7,
          overdue: 1,
          dueToday: 2,
          serviceMix: [],
          cash: [],
        ),
      );

      fakeOrdersRepo = FakeOrdersRepo();
      fakePosRepo = FakePosRepo();

      ownerBloc = OwnerBloc(ownerRepository: fakeOwnerRepo);
      ordersBloc = OrdersBloc(ordersRepository: fakeOrdersRepo);
      cartBloc = CartBloc(posRepository: fakePosRepo);

      final user = User(id: 'u1', name: 'Owner User', phone: 'owner');
      final store = StoreSummary(
        storeId: 's1',
        storeName: 'Test Store',
        role: 'OWNER',
      );
      authBloc = MockAuthBloc(
        AuthenticatedState(
          user: user,
          currentStore: store,
          availableStores: [store],
        ),
      );

      outletScopeCubit = OutletScopeCubit(localCache: FakeLocalCache())
        ..hydrate();
    });

    tearDown(() {
      ownerBloc.close();
      ordersBloc.close();
      cartBloc.close();
      authBloc.close();
      outletScopeCubit.close();
    });

    Widget buildTestWidget() {
      return MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OwnerBloc>.value(value: ownerBloc),
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<CartBloc>.value(value: cartBloc),
          BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
        ],
        child: const MaterialApp(home: MainNavigationShell()),
      );
    }

    testWidgets(
      'Switching away from Dashboard tab resets its period selector to default (This month)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        ownerBloc.add(LoadDashboardEvent());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Initially period is "This month"
        expect(find.text('This month'), findsWidgets);

        // Change period to "This week"
        await tester.tap(find.text('This month').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('This week').last);
        await tester.pumpAndSettle();

        // Verify "This week" is active
        expect(find.text('This week'), findsWidgets);

        // Tap Orders bottom nav tab
        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();

        // Now on Orders tab. Tap Dashboard bottom nav tab to return
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();

        // Dashboard period has reset back to "This month"
        expect(find.text('This month'), findsWidgets);
      },
    );

    testWidgets('Switching away from Orders tab resets its quick filters', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Switch to Orders tab
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      // Initially "Selected dates" is selected
      expect(find.text('Selected dates'), findsOneWidget);

      // Tap "Late" quick filter chip
      await tester.tap(find.text('Late'));
      await tester.pumpAndSettle();

      // Switch to Dashboard tab
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      // Switch back to Orders tab
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      // Filters have reset: "Selected dates" is back to active
      expect(find.text('Selected dates'), findsOneWidget);
    });
  });
}
