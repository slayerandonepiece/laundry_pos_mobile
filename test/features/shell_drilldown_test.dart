import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/period_filter.dart';
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
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/presentation/main_navigation_shell.dart';

class _Cache extends LocalCacheService {
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

class _OwnerRepo implements OwnerRepository {
  DashboardMetrics metrics;
  int getDashboardMetricsCallCount = 0;

  _OwnerRepo({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async {
    getDashboardMetricsCallCount++;
    return metrics;
  }

  @override
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) async => metrics;

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => null;

  @override
  List<Expense>? getCachedExpensesSync() => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OrdersRepo implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

  @override
  bool hasCachedOrders({String? outletId, bool? allOutlets}) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosRepo implements PosRepository {
  @override
  List<Product> getCachedProductsList() => [];

  @override
  List<StorePaymentMethod>? getCachedPaymentMethodsList() => null;

  @override
  Future<List<Product>> listProducts() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _Auth(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingOwnerBloc extends OwnerBloc {
  final List<LoadDashboardEvent> dashboardEvents = [];
  _TrackingOwnerBloc({required super.ownerRepository});

  @override
  void add(OwnerEvent event) {
    if (event is LoadDashboardEvent) dashboardEvents.add(event);
    super.add(event);
  }
}

void main() {
  late _TrackingOwnerBloc ownerBloc;
  late OrdersBloc ordersBloc;
  late CartBloc cartBloc;
  late _Auth authBloc;
  late OutletScopeCubit outletScopeCubit;

  setUp(() {
    ownerBloc = _TrackingOwnerBloc(
      ownerRepository: _OwnerRepo(
        metrics: DashboardMetrics(
          todo: 3,
          completed: 7,
          dueToday: 2,
          serviceMix: [],
          cash: [],
        ),
      ),
    );
    ordersBloc = OrdersBloc(ordersRepository: _OrdersRepo());
    cartBloc = CartBloc(posRepository: _PosRepo());
    final store = StoreSummary(
      storeId: 's1',
      storeName: 'Test Store',
      role: 'OWNER',
    );
    authBloc = _Auth(
      AuthenticatedState(
        user: User(id: 'u1', name: 'Owner User', phone: 'owner'),
        currentStore: store,
        availableStores: [store],
      ),
    );
    outletScopeCubit = OutletScopeCubit(localCache: _Cache())..hydrate();
  });

  tearDown(() {
    ownerBloc.close();
    ordersBloc.close();
    cartBloc.close();
    authBloc.close();
    outletScopeCubit.close();
  });

  const filterDate = ValueKey('filter-salesByDate');

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OwnerBloc>.value(value: ownerBloc),
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<CartBloc>.value(value: cartBloc),
          BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
        ],
        child: const MaterialApp(home: MainNavigationShell()),
      ),
    );
    ownerBloc.add(LoadDashboardEvent());
    await settle(tester);
  }

  bool chipSelected(WidgetTester tester, String label) => tester
      .widget<AppFilterChip>(
        find.widgetWithText(AppFilterChip, label, skipOffstage: false),
      )
      .isSelected;

  PeriodRange dateRange(WidgetTester tester) => tester
      .widget<PeriodFilter>(find.byKey(filterDate, skipOffstage: false))
      .value;

  testWidgets('Open orders tile lands on Orders with the Open chip selected', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.text('Open orders'), findsOneWidget);

    await tester.tap(find.text('Open orders'));
    await settle(tester);

    expect(chipSelected(tester, 'Open'), isTrue);
    expect(chipSelected(tester, 'Selected dates'), isFalse);
    // The Orders tab is the visible one.
    expect(find.byType(AppFilterChip), findsWidgets);
    expect(find.text('Open orders'), findsNothing);
  });

  testWidgets('each dashboard tile opens its own view', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Due today').first);
    await settle(tester);
    expect(chipSelected(tester, 'Due today'), isTrue);
    expect(chipSelected(tester, 'Open'), isFalse);
  });

  testWidgets('leaving Orders clears its filters and does not re-apply the '
      'drill-down; the same tile works again (request was cleared)', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.text('Open orders'));
    await settle(tester);
    expect(chipSelected(tester, 'Open'), isTrue);

    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.text('Orders'));
    await settle(tester);
    expect(chipSelected(tester, 'Selected dates'), isTrue);
    expect(chipSelected(tester, 'Open'), isFalse);

    // The same drill-down again only takes effect if the first one was
    // cleared (an unchanged ValueNotifier does not notify).
    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.text('Open orders'));
    await settle(tester);
    expect(chipSelected(tester, 'Open'), isTrue);
  });

  testWidgets('a drill-down from a dashboard on a custom period resets its '
      'cards', (tester) async {
    await pumpShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(filterDate),
        matching: find.text('7 days'),
      ),
    );
    await settle(tester);
    expect(dateRange(tester), PeriodRange.last7);
    expect(ownerBloc.state.cards, isNotEmpty);

    await tester.tap(find.text('Open orders'));
    await settle(tester);

    // Reset on the way out, not only when the owner comes back.
    expect(dateRange(tester), PeriodRange.thisMonth);
    expect(ownerBloc.state.cards, isEmpty);
    expect(chipSelected(tester, 'Open'), isTrue);
  });

  testWidgets(
    'switching store reloads the dashboard with the default month-to-date '
    'daily request, keyed to the outlet scope',
    (tester) async {
      await pumpShell(tester);
      ownerBloc.dashboardEvents.clear();

      final other = StoreSummary(
        storeId: 's2',
        storeName: 'Other Store',
        role: 'OWNER',
      );
      authBloc.emit(
        AuthenticatedState(
          user: User(id: 'u1', name: 'Owner User', phone: 'owner'),
          currentStore: other,
          availableStores: [other],
        ),
      );
      await settle(tester);

      expect(ownerBloc.dashboardEvents, hasLength(1));
      final e = ownerBloc.dashboardEvents.single;
      final now = DateTime.now();
      expect(e.refresh, isTrue);
      expect(e.isDefaultPeriod, isTrue);
      expect(e.granularity, 'day');
      expect(e.to, DateFormatter.toIsoDateString(now));
      expect(
        e.from,
        DateFormatter.toIsoDateString(DateTime(now.year, now.month, 1)),
      );
      final scope = outletScopeCubit.state;
      expect(
        e.requestKey,
        'mtd|${scope.allOutlets ? 'all' : (scope.activeOutletId ?? 'none')}',
      );
    },
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}
