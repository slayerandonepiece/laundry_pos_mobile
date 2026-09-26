import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_switcher.dart';

class FakeLocalCache extends LocalCacheService {

  @override
  Map<String, dynamic>? getCachedUser() => null;

  final Map<String, String> _rememberedOutlets = {};
  @override
  String? getRememberedOutlet(String userId, String storeId) =>
      _rememberedOutlets['$userId::$storeId'];
  @override
  Future<void> setRememberedOutlet(
    String userId,
    String storeId,
    String outletId,
  ) async => _rememberedOutlets['$userId::$storeId'] = outletId;

  Map<String, dynamic>? storeDetails;
  List<Map<String, dynamic>>? allowedOutlets;
  String? activeOutletId;
  bool allOutletsScope;

  FakeLocalCache({
    this.storeDetails = const {'role': 'OWNER'},
    this.allowedOutlets = const [
      {
        'id': 'outlet_1',
        'outletCode': 'OBLRCHN01',
        'displayName': 'Chinnapanahalli',
        'isDefault': true,
        'status': 'ACTIVE',
      },
      {
        'id': 'outlet_2',
        'outletCode': 'OBLRMTH02',
        'displayName': 'Marathahalli',
        'isDefault': false,
        'status': 'ACTIVE',
      },
    ],
    this.activeOutletId,
    this.allOutletsScope = true,
  });

  @override
  Map<String, dynamic>? getCachedStoreDetails() => storeDetails;

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => allowedOutlets;

  @override
  String? getActiveOutletId() => activeOutletId;

  @override
  Future<void> setActiveOutletId(String outletId) async {
    activeOutletId = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    activeOutletId = null;
  }

  @override
  bool isAllOutletsScope() => allOutletsScope;

  @override
  Future<void> setAllOutletsScope(bool value) async {
    allOutletsScope = value;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    allOutletsScope = false;
  }
}

class FakeDashboardOwnerRepository implements OwnerRepository {
  DashboardMetrics metrics;
  final List<({String? from, String? to})> calls = [];

  FakeDashboardOwnerRepository({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    calls.add((from: from, to: to));
    return metrics;
  }

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => metrics;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackingOwnerBloc extends OwnerBloc {
  final List<LoadDashboardEvent> loadDashboardEvents = [];

  TrackingOwnerBloc({required super.ownerRepository});

  @override
  void add(OwnerEvent event) {
    if (event is LoadDashboardEvent) {
      loadDashboardEvents.add(event);
    }
    super.add(event);
  }
}

class FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  FakeAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOrdersBloc extends Bloc<OrdersEvent, OrdersState>
    implements OrdersBloc {
  FakeOrdersBloc([List<Order> orders = const []])
    : super(OrdersState(allOrders: orders)) {
    on<LoadOrdersEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OwnerDashboardScreen Outlet Scope & Vocabulary (O5.2)', () {
    late FakeDashboardOwnerRepository fakeOwnerRepo;
    late TrackingOwnerBloc ownerBloc;
    late FakeOrdersBloc ordersBloc;
    late FakeAuthBloc authBloc;

    setUp(() {
      fakeOwnerRepo = FakeDashboardOwnerRepository(
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
          serviceMix: [
            ServiceMixItem(label: 'Dry Clean', amount: 80000),
          ],
          cash: [
            CashPoint(label: 'Mon', income: 30000, expenses: 10000),
            CashPoint(label: 'Tue', income: 50000, expenses: 20000),
          ],
        ),
      );
      ownerBloc = TrackingOwnerBloc(ownerRepository: fakeOwnerRepo);
      ordersBloc = FakeOrdersBloc([
        Order(
          id: 'ORD-001',
          name: 'Alice Smith',
          phone: '9876543210',
          date: '2026-09-12',
          due: '2026-09-13',
          status: 'Pending',
          lines: [],
          payments: [],
        ),
        Order(
          id: 'ORD-002',
          name: 'Charlie Delivered',
          phone: '9876543212',
          date: '2026-09-08',
          due: '2026-09-09',
          status: 'Delivered',
          lines: [],
          payments: [],
        ),
      ]);
      authBloc = FakeAuthBloc();
    });

    tearDown(() async {
      await ownerBloc.close();
      await ordersBloc.close();
      await authBloc.close();
    });

    Widget buildScreen(OutletScopeCubit outletScopeCubit) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<OwnerBloc>.value(value: ownerBloc),
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
        ],
        child: const MaterialApp(home: OwnerDashboardScreen()),
      );
    }

    Future<void> pumpDashboard(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('Switcher is shown for owner with >= 1 outlet', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final singleOutletCache = FakeLocalCache(
        allowedOutlets: const [
          {
            'id': 'outlet_1',
            'outletCode': 'OBLRCHN01',
            'displayName': 'Chinnapanahalli',
            'isDefault': true,
            'status': 'ACTIVE',
          },
        ],
      );
      final cubit = OutletScopeCubit(localCache: singleOutletCache)..hydrate();
      addTearDown(cubit.close);

      await tester.pumpWidget(buildScreen(cubit));
      await pumpDashboard(tester);

      expect(find.byType(OutletSwitcher), findsOneWidget);
      expect(find.text('All outlets'), findsOneWidget);
    });

    testWidgets('Changing outlet scope dispatches LoadDashboardEvent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cache = FakeLocalCache();
      final cubit = OutletScopeCubit(localCache: cache)..hydrate();
      addTearDown(cubit.close);

      await tester.pumpWidget(buildScreen(cubit));
      await pumpDashboard(tester);

      // Clear initial mount LoadDashboardEvent
      ownerBloc.loadDashboardEvents.clear();
      fakeOwnerRepo.calls.clear();

      // Narrow scope to a specific outlet via the switcher sheet
      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chinnapanahalli'));
      await pumpDashboard(tester);

      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(cubit.state.allOutlets, isFalse);
      expect(ownerBloc.loadDashboardEvents.length, 1);
      expect(fakeOwnerRepo.calls.length, 1);

      // Switch back to All outlets
      cubit.selectAllOutlets();
      await pumpDashboard(tester);

      expect(cubit.state.allOutlets, isTrue);
      expect(ownerBloc.loadDashboardEvents.length, 2);
      expect(fakeOwnerRepo.calls.length, 2);
    });

    testWidgets(
      'New M0 vocabulary labels render and old labels do not appear',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cubit = OutletScopeCubit(localCache: FakeLocalCache())..hydrate();
        addTearDown(cubit.close);

        await tester.pumpWidget(buildScreen(cubit));
        await pumpDashboard(tester);

        // New labels render
        expect(find.text('Open orders'), findsOneWidget);
        expect(find.text('Delivered'), findsWidgets); // chip + donut legend
        expect(
          find.text('Collected vs expenses — this month'),
          findsOneWidget,
        );
        expect(find.text('payments collected this month'), findsOneWidget);
        expect(
          find.text('Collected'),
          findsNWidgets(2), // SalesTrendChart badge + CashFlowChart legend
        );

        // Old labels do not render
        expect(find.text('Waiting'), findsNothing);
        expect(find.text('Completed'), findsNothing);
        expect(find.text('Income'), findsNothing);
        expect(find.text('Money in & expenses'), findsNothing);
        expect(find.text('Received minus spent'), findsNothing);
      },
    );
  });
}
