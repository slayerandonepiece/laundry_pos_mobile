import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/orders/presentation/orders_drill_down.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

class _NoOpSyncEngine extends SyncEngine {
  _NoOpSyncEngine({
    required super.ordersRepository,
    required super.ownerRepository,
  }) : super.internal();

  @override
  Future<void> retryNow() async {}

  @override
  Future<void> trigger({bool forceFromStart = false}) async {}
}

class FakeDashboardOwnerRepository implements OwnerRepository {
  DashboardMetrics metrics;
  bool shouldThrow = false;

  /// Every getDashboardMetrics call, in order.
  final List<({String? from, String? to, String? granularity})> requests = [];

  /// When set, getDashboardMetrics waits on it before answering — lets a test
  /// observe the screen while a response is still pending.
  Completer<void>? gate;

  FakeDashboardOwnerRepository({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async {
    requests.add((from: from, to: to, granularity: granularity));
    if (gate != null) await gate!.future;
    if (shouldThrow) throw Exception('Network error');
    return metrics;
  }

  /// Every per-card getPeriodMetrics call, in order.
  final List<({String from, String to, String granularity})> periodRequests =
      [];

  /// What a per-card request answers with; defaults to [metrics].
  DashboardMetrics? periodMetrics;
  bool periodShouldThrow = false;
  Completer<void>? periodGate;

  @override
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) async {
    periodRequests.add((from: from, to: to, granularity: granularity));
    if (periodGate != null) await periodGate!.future;
    if (periodShouldThrow) throw Exception('Network error');
    return periodMetrics ?? metrics;
  }

  /// What "on the phone" holds for the default period; null = nothing cached.
  DashboardMetrics? cachedDefault;

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => cachedDefault;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOrdersRepository implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

  @override
  bool hasCachedOrders({String? outletId, bool? allOutlets}) =>
      cachedOrders.isNotEmpty;

  @override
  Future<bool> processPendingSyncQueue() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOrdersBloc extends Bloc<OrdersEvent, OrdersState>
    implements OrdersBloc {
  MockOrdersBloc([List<Order> orders = const []])
    : super(OrdersState(allOrders: orders)) {
    on<LoadOrdersEvent>((event, emit) {});
    on<RefreshOrdersEvent>(
      (event, emit) => emit(state.copyWith(isLoading: false)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OwnerDashboardScreen Redesign Tests', () {
    late FakeDashboardOwnerRepository fakeOwnerRepo;
    late MockOrdersRepository mockOrdersRepo;
    late OwnerBloc ownerBloc;
    late OrdersBloc ordersBloc;
    late MockAuthBloc authBloc;

    setUp(() {
      fakeOwnerRepo = FakeDashboardOwnerRepository(
        metrics: DashboardMetrics(
          todaySales: 50000, // ₹500
          todayCount: 2,
          periodSales: 120000, // ₹1,200
          periodOrders: 5,
          outstanding: 30000, // ₹300
          todo: 3,
          completed: 7,
          overdue: 1,
          dueToday: 2,
          serviceMix: [
            ServiceMixItem(label: 'Dry Clean', amount: 80000),
            ServiceMixItem(label: 'Wash & Fold', amount: 40000),
          ],
          cash: [
            CashPoint(label: 'Mon', income: 30000, expenses: 10000),
            CashPoint(label: 'Tue', income: 50000, expenses: 20000),
            CashPoint(label: 'Wed', income: 40000, expenses: 15000),
          ],
        ),
      );

      mockOrdersRepo = MockOrdersRepository();
      mockOrdersRepo.cachedOrders = [
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
          name: 'Bob Jones',
          phone: '9876543211',
          date: '2026-09-10',
          due: '2026-09-11',
          status: 'Ready',
          lines: [],
          payments: [],
        ),
        Order(
          id: 'ORD-003',
          name: 'Charlie Delivered',
          phone: '9876543212',
          date: '2026-09-08',
          due: '2026-09-09',
          status: 'Delivered',
          lines: [],
          payments: [],
        ),
        Order(
          id: 'ORD-004',
          name: 'David Later',
          phone: '9876543213',
          date: '2026-09-12',
          due: '2026-09-15',
          status: 'In Progress',
          lines: [],
          payments: [],
        ),
      ];

      SyncEngine.instance = _NoOpSyncEngine(
        ordersRepository: mockOrdersRepo,
        ownerRepository: fakeOwnerRepo,
      );
      ownerBloc = OwnerBloc(ownerRepository: fakeOwnerRepo);
      ordersBloc = OrdersBloc(ordersRepository: mockOrdersRepo);
      authBloc = MockAuthBloc();
    });

    Widget buildTestWidget({ThemeData? theme}) {
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<OwnerBloc>.value(value: ownerBloc),
            BlocProvider<OrdersBloc>.value(value: ordersBloc),
            BlocProvider<AuthBloc>.value(value: authBloc),
          ],
          child: MaterialApp(theme: theme, home: const OwnerDashboardScreen()),
        ),
      );
    }

    const filterDate = ValueKey('filter-salesByDate');
    const filterService = ValueKey('filter-salesByService');

    Finder inFilter(Key filter, String text) =>
        find.descendant(of: find.byKey(filter), matching: find.text(text));

    Future<void> pumpDashboard(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('dashboard preserves a true zero month', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockOrdersRepo.cachedOrders = [];
      fakeOwnerRepo.metrics = DashboardMetrics(
        todaySales: 50000,
        todayCount: 2,
        periodSales: 0,
        periodOrders: 0,
        expensesThisMonth: 45000,
        overdue: 2,
        dueToday: 1,
      );

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      expect(find.text('Sales this month'), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);
    });

    testWidgets(
      '1. Two hero money cards render correct values and "Sales today" card is visually distinguished',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // No order on the phone falls in the last 30 days, so the headline
        // falls back to the dashboard reply's own figures (the fixture dates
        // are fixed, so pin them well outside any window).
        mockOrdersRepo.cachedOrders = [
          for (final o in mockOrdersRepo.cachedOrders)
            Order(
              id: o.id,
              name: o.name,
              phone: o.phone,
              date: '2020-01-01',
              due: o.due,
              status: o.status,
              lines: o.lines,
              payments: o.payments,
            ),
        ];
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);

        // Eyebrow and expanded title
        expect(find.text('WORKSPACE'), findsOneWidget);
        expect(find.text('Dashboard'), findsOneWidget);

        // Card 1: "Sales today"
        expect(find.text('Sales today'), findsOneWidget);
        expect(find.text('₹500'), findsOneWidget);
        expect(find.text('2 orders'), findsOneWidget);

        // Assert "Sales today" is a solid-primary-fill hero card with white text
        final todayValueText = tester.widget<Text>(find.text('₹500'));
        expect(todayValueText.style?.color, Colors.white);
        final todayCardContainer = tester.widget<Container>(
          find
              .ancestor(of: find.text('₹500'), matching: find.byType(Container))
              .first,
        );
        expect(
          (todayCardContainer.decoration as BoxDecoration).color,
          AppColors.primary,
        );
        expect(todayValueText.style?.fontSize, 22);
        expect(todayValueText.style?.fontWeight, FontWeight.w600);

        // Card 2: "Sales this month" (month-to-date from the default reply, independent of the
        // page's month-to-date default period)
        expect(find.text('Sales this month'), findsOneWidget);
        // Also shown as the "Collected" figure of the cash card below.
        expect(find.text('₹1,200'), findsWidgets);
        expect(find.text('5 orders'), findsOneWidget);

        // Assert period sales value is styled with AppColors.text (not accent)
        final periodValueText = tester.widget<Text>(find.text('₹1,200').first);
        expect(periodValueText.style?.color, AppColors.text);
        expect(periodValueText.style?.fontSize, 22);
        expect(periodValueText.style?.fontWeight, FontWeight.w600);
      },
    );

    testWidgets(
      '1b. "Sales this month" shows the server reply, not a sum of the orders cached on the phone',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        String iso(int daysAgo) {
          final d = DateTime.now().subtract(Duration(days: daysAgo));
          return '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
        }

        Order order(String id, int daysAgo, int amount) => Order(
          id: id,
          name: id,
          phone: '9000000000',
          date: iso(daysAgo),
          due: iso(daysAgo),
          status: 'Delivered',
          lines: [
            OrderLine(
              productId: 'p',
              name: 'Wash',
              quantity: 1,
              unit: 'PIECE',
              amount: amount,
            ),
          ],
          payments: [],
        );

        // Cached orders on the phone; the headline ignores them.
        mockOrdersRepo.cachedOrders = [
          order('IN-1', 0, 30000),
          order('IN-2', 29, 25000),
          order('OUT-1', 45, 99900),
        ];
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Sales this month'), findsOneWidget);
        // The cached orders (₹550 over 2 orders in the last 30 days) must not
        // replace the server's month-to-date figures.
        expect(find.text('₹550'), findsNothing);
        expect(find.text('5 orders'), findsOneWidget);
      },
    );

    testWidgets('2. Compact 3-chip row shows correct operational counts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      // Operational chips
      expect(find.text('Open orders'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // metrics.todo

      expect(find.text('Delivered'), findsWidgets); // chip + donut legend
      expect(find.text('7'), findsOneWidget); // metrics.completed

      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // metrics.dueToday: 2
    });

    testWidgets(
      '3. Each period-filtered card has its own chips; the page has none',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // Sales by date and Sales by service — nothing else.
        expect(find.text('This week'), findsNWidgets(2));
        expect(find.text(PeriodRange.currentMonthLabel()), findsNWidgets(2));
        expect(find.text(PeriodRange.previousMonthLabel()), findsNWidgets(2));
        // The old rolling 30 / 90 day chips are gone.
        expect(find.text('30 Days'), findsNothing);
        expect(find.text('90 Days'), findsNothing);
        expect(find.byIcon(Icons.calendar_today_outlined), findsNWidgets(2));
        expect(find.byKey(filterDate), findsOneWidget);
        expect(find.byKey(filterService), findsOneWidget);
        // The money cards stay fixed.
        expect(find.text('Sales today'), findsOneWidget);
        expect(find.text('Sales this month'), findsOneWidget);
      },
    );

    testWidgets('A new order reloads the dashboard without a manual refresh', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);
      final before = fakeOwnerRepo.requests.length;

      // A sale lands in the orders list (placed here or synced from elsewhere).
      mockOrdersRepo.cachedOrders = [
        ...mockOrdersRepo.cachedOrders,
        Order(
          id: 'EL-900',
          name: 'New sale',
          phone: '9000000900',
          date: '2026-09-10',
          due: '2026-09-12',
          status: 'Pending',
          lines: [],
          payments: [],
        ),
      ];
      ordersBloc.add(LoadOrdersEvent());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      // The reload waits a moment so a burst of changes becomes one request.
      await tester.pump(const Duration(seconds: 1));
      await pumpDashboard(tester);

      expect(fakeOwnerRepo.requests.length, greaterThan(before));
    });

    testWidgets(
      '4. "Sales by date" trend chart renders with muted color and empty-guard works',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Sales by date'), findsOneWidget);
        expect(find.text('How your sales moved this week'), findsOneWidget);
        expect(find.byType(LineChart), findsOneWidget);

        // Check line color matches app theme (AppColors.primary)
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(lineChart.data.lineBarsData.first.color, AppColors.primary);

        // Empty cash case: the week card and the page both come back empty
        fakeOwnerRepo.metrics = DashboardMetrics(todaySales: 10000, cash: []);
        fakeOwnerRepo.periodMetrics = DashboardMetrics(
          todaySales: 10000,
          cash: [],
        );
        await tester.tap(find.byTooltip('Refresh'));
        await pumpDashboard(tester);

        // The card stays so its filter does; it says there is nothing.
        expect(find.text('Sales by date'), findsOneWidget);
        expect(find.byType(LineChart), findsNothing);
        expect(find.text('No sales in this period'), findsNWidgets(2));
      },
    );

    testWidgets(
      '5. "How orders are moving" donut/legend has exactly 4 buckets summing to allOrders.length with StatusPill matching colors',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('How orders are moving'), findsOneWidget);
        expect(find.text('Where your orders stand right now'), findsOneWidget);
        expect(find.byType(PieChart), findsOneWidget);

        // 4 buckets derived from mockOrdersRepo (4 orders total: 1 Pending, 1 In Progress, 1 Ready, 1 Delivered)
        final donutCard = find.ancestor(
          of: find.text('How orders are moving'),
          matching: find.byType(AppCard),
        );
        expect(
          find.descendant(of: donutCard, matching: find.text('Pending')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: donutCard, matching: find.text('In progress')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: donutCard, matching: find.text('Ready')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: donutCard, matching: find.text('Delivered')),
          findsOneWidget,
        );

        // Check PieChart sections count, sum, and matching colors
        final pieChart = tester.widget<PieChart>(find.byType(PieChart));
        final sections = pieChart.data.sections;
        expect(sections.length, 4);

        // Pending: value 1, color AppColors.neutralText
        expect(sections[0].value, 1.0);
        expect(sections[0].color, AppColors.neutralText);

        // In progress: value 1, color AppColors.primary
        expect(sections[1].value, 1.0);
        expect(sections[1].color, AppColors.primary);

        // Ready: value 1, color AppColors.violet
        expect(sections[2].value, 1.0);
        expect(sections[2].color, AppColors.violet);

        // Delivered: value 1, color AppColors.success
        expect(sections[3].value, 1.0);
        expect(sections[3].color, AppColors.success);

        // Sum of counts equals mockOrdersRepo.cachedOrders.length (1 + 1 + 1 + 1 = 4)
        final totalOrderCount = sections.fold<double>(
          0,
          (sum, s) => sum + s.value,
        );
        expect(totalOrderCount.toInt(), mockOrdersRepo.cachedOrders.length);
      },
    );

    testWidgets(
      '6. When allOrders is empty, "How orders are moving" section is not rendered',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final emptyOrdersBloc = MockOrdersBloc([]);

        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<OwnerBloc>.value(value: ownerBloc),
                BlocProvider<OrdersBloc>.value(value: emptyOrdersBloc),
                BlocProvider<AuthBloc>.value(value: authBloc),
              ],
              child: const MaterialApp(home: OwnerDashboardScreen()),
            ),
          ),
        );
        await pumpDashboard(tester);

        expect(find.text('How orders are moving'), findsNothing);
        expect(find.byType(PieChart), findsNothing);
      },
    );

    testWidgets(
      '7. "Sales by service" chart renders with muted bar color and empty-guard works',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Sales by service'), findsOneWidget);
        // Bars are plain proportional Containers now (no fl_chart BarChart in Sales by service),
        // so they can't overlap their own value labels the way rod labels did.
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Sales by service'),
              matching: find.byType(AppCard),
            ),
            matching: find.byType(BarChart),
          ),
          findsNothing,
        );
        expect(find.text('Wash & Fold'), findsOneWidget);

        // Empty serviceMix
        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 10000,
          serviceMix: [],
        );
        ownerBloc.add(LoadDashboardEvent());
        await pumpDashboard(tester);

        expect(find.text('Sales by service'), findsOneWidget);
        expect(find.text('Wash & Fold'), findsNothing);
        // The service card reads the (now empty) page data; Sales by date has
        // its own week data.
        expect(find.text('No sales in this period'), findsOneWidget);
      },
    );

    testWidgets(
      '8. "Orders to finish" section is completely removed from widget tree',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // The old "Orders to finish" list is gone; only the Recent orders
        // card lists orders now.
        expect(find.text('Orders to finish'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Recent orders'),
          500,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Recent orders'), findsOneWidget);
      },
    );

    testWidgets(
      '9. Plain AppBar title stays fixed in place on scroll, matching every other owner screen',
      (tester) async {
        tester.view.physicalSize = const Size(400, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // Drag up to scroll the body — the AppBar title never moves or changes.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(find.byType(AppBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Dashboard'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '10. Manual refresh icon button in SliverAppBar triggers dashboard reload',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        final refreshBtn = find.byTooltip('Refresh');
        expect(refreshBtn, findsOneWidget);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 99000,
          todayCount: 5,
          periodSales: 200000,
          periodOrders: 10,
        );

        await tester.tap(refreshBtn);
        await pumpDashboard(tester);

        expect(find.text('₹990'), findsOneWidget);
        expect(find.text('5 orders'), findsOneWidget);
      },
    );

    testWidgets(
      '11. App bar shows retry sync button before refresh button when sync is paused or has error',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SyncManager.instance.completeSync();

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // In synced state, no retry button
        expect(find.byTooltip('Retry sync'), findsNothing);
        expect(find.byTooltip('Refresh'), findsOneWidget);

        // Set sync error
        SyncManager.instance.setError('Network error');
        await tester.pump();

        // Now retry button appears before refresh button
        expect(find.byTooltip('Retry sync'), findsOneWidget);
        expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
        expect(find.byTooltip('Refresh'), findsOneWidget);

        // Clean up back to synced
        SyncManager.instance.completeSync();
        await tester.pump(const Duration(seconds: 3));
        expect(find.byTooltip('Retry sync'), findsNothing);
      },
    );

    testWidgets(
      '11. "Collected vs expenses" card shows Collected / Spent / Net and the spent-vs-kept split',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Collected vs expenses'), findsOneWidget);
        // The fixture has no range series, so it falls back to the
        // calendar-month series and says so.
        expect(find.text('This month'), findsOneWidget);

        // cash fixture: income 300+500+400 = 1200, expenses 100+200+150 = 450,
        // net = 750; spent 450/1200 = 38%, kept 62%.
        expect(find.text('Spent'), findsOneWidget);
        expect(find.text('Net'), findsOneWidget);
        expect(find.text('₹750'), findsOneWidget);
        expect(find.text('₹450'), findsOneWidget);
        expect(find.text('Spent ₹450 · 38%'), findsOneWidget);
        expect(find.text('Kept ₹750 · 62%'), findsOneWidget);

        // Split bar paints at full width with both segments visible, and the
        // two labels sit at opposite ends of the card.
        final spentLabel = tester.getRect(find.text('Spent ₹450 · 38%'));
        final keptLabel = tester.getRect(find.text('Kept ₹750 · 62%'));
        expect(keptLabel.left - spentLabel.right, greaterThan(50));
        final bar = find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 12 && w.width == double.infinity,
        );
        expect(tester.getSize(bar).width, greaterThan(100));
        final segments = find.descendant(
          of: bar,
          matching: find.byType(ColoredBox),
        );
        expect(segments, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          expect(tester.getSize(segments.at(i)).height, 12);
          expect(tester.getSize(segments.at(i)).width, greaterThan(0));
        }
      },
    );

    testWidgets(
      '11b. Collected vs expenses follows the range series and names the selected period',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 1000,
          periodSales: 5000,
          bars: [DashboardBar(label: '23 Sep', amount: 1000)],
          cash: [CashPoint(label: 'Sep', income: 999900, expenses: 111100)],
          cashRange: [
            CashPoint(label: '23 Sep', income: 20000, expenses: 5000),
            CashPoint(label: '24 Sep', income: 10000, expenses: 5000),
          ],
        );

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);
        // Default period: the current month (month-to-date).
        expect(find.text(PeriodRange.currentMonthLabel()), findsWidgets);
        // Totals come from cashRange (₹300 collected, ₹100 spent), not `cash`.
        expect(find.text('Spent ₹100 · 33%'), findsOneWidget);
        expect(find.text('Kept ₹200 · 67%'), findsOneWidget);
        expect(find.text('₹9,999'), findsNothing);

        // A card's own filter never moves it.
        await tester.tap(inFilter(filterDate, 'This week'));
        await pumpDashboard(tester);
        expect(find.text('Last 30 days'), findsNothing);
        expect(find.text(PeriodRange.currentMonthLabel()), findsWidgets);
        expect(find.text('Spent ₹100 · 33%'), findsOneWidget);
      },
    );

    testWidgets(
      '11c. Collected vs expenses says so when spending exceeds collections',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 1000,
          cashRange: [
            CashPoint(label: '23 Sep', income: 10000, expenses: 25000),
          ],
        );

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);
        // ₹100 collected against ₹250 spent: 40% covered, 60% still to cover.
        expect(find.text('Covered ₹100 · 40%'), findsOneWidget);
        expect(find.text('Yet to cover ₹150 · 60%'), findsOneWidget);
        expect(find.text('-₹150'), findsOneWidget);
        // The bar must actually paint: full card width, 12px tall.
        final bar = find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 12 && w.width == double.infinity,
        );
        expect(bar, findsOneWidget);
        expect(tester.getSize(bar).width, greaterThan(100));
        expect(tester.getSize(bar).height, 12);
      },
    );

    testWidgets(
      '11d. Collected vs expenses renders when money came in and nothing was spent',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 1000,
          cashRange: [CashPoint(label: '23 Sep', income: 10000, expenses: 0)],
        );

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Spent ₹0 · 0%'), findsOneWidget);
        expect(find.text('Kept ₹100 · 100%'), findsOneWidget);
      },
    );

    testWidgets('12. A card\'s calendar button opens its own From / To row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);
      expect(find.text('FROM'), findsNothing);
      final requestsBefore = fakeOwnerRepo.periodRequests.length;

      await tester.tap(
        find.descendant(
          of: find.byKey(filterDate),
          matching: find.byIcon(Icons.calendar_today_outlined),
        ),
      );
      await pumpDashboard(tester);

      // Only that card opened one; nothing requested until both are picked.
      expect(find.text('FROM'), findsOneWidget);
      expect(find.text('TO'), findsOneWidget);
      expect(fakeOwnerRepo.periodRequests.length, requestsBefore);
    });

    testWidgets(
      '13. Dashboard alone shows its own load error SnackBar when route is current',
      (tester) async {
        fakeOwnerRepo.shouldThrow = true;
        ownerBloc = OwnerBloc(ownerRepository: fakeOwnerRepo);

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Could not load dashboard — try again'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '14. Dashboard does not show error SnackBar when another route with an OwnerBloc listener is pushed on top',
      (tester) async {
        ownerBloc = OwnerBloc(ownerRepository: fakeOwnerRepo);

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        // Push a second route on top with its own OwnerBloc error listener.
        final navContext = tester.element(find.byType(OwnerDashboardScreen));
        Navigator.of(navContext).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: BlocListener<OwnerBloc, OwnerState>(
                listener: (context, state) {
                  if (state.error != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(state.error!)));
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Emit an error while the second route is on top.
        fakeOwnerRepo.shouldThrow = true;
        ownerBloc.add(LoadDashboardEvent(refresh: true));
        await tester.pumpAndSettle();

        const error = 'Could not load dashboard — try again';
        expect(find.text(error), findsOneWidget);

        // Advance past the first SnackBar's display duration and exit animation;
        // no second queued SnackBar from the backgrounded dashboard should appear.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text(error), findsNothing);
      },
    );

    group('Chart Label Formatting & Visibility Tests', () {
      test('formats verbose weekly date ranges into clean compact strings', () {
        expect(formatChartLabel('1 Sept 2026–6 Sept 2026'), equals('1–6\nSep'));
        expect(
          formatChartLabel('7 Sept 2026 - 12 Sept 2026'),
          equals('7–12\nSep'),
        );
        expect(
          formatChartLabel('13 September 2026–18 September 2026'),
          equals('13–18\nSep'),
        );
        expect(
          formatChartLabel('28 Aug 2026–3 Sep 2026'),
          equals('28 Aug -\n3 Sep'),
        );
        expect(formatChartLabel('Aug 30 - Sep 05'), equals('Aug 30 -\nSep 05'));
      });

      test('formats single dates and weekdays cleanly', () {
        expect(formatChartLabel('22 Sep'), equals('22\nSep'));
        expect(formatChartLabel('1 Sept 2026'), equals('1\nSep'));
        expect(formatChartLabel('28 September'), equals('28\nSep'));
        expect(formatChartLabel('2026-09-15'), equals('15\nSep'));
        expect(formatChartLabel('Monday'), equals('Mon'));
        expect(formatChartLabel('Mon'), equals('Mon'));
        expect(formatChartLabel('September 2026'), equals('Sep'));
        expect(formatChartLabel(''), equals(''));
      });

      test('formats 1 Sep–3 Sep into 01 Sep -\\n03 Sep and 22 Sep into 22\\nSep (F3)', () {
        expect(formatChartLabel('1 Sep–3 Sep'), equals('01 Sep -\n03 Sep'));
        expect(formatChartLabel('22 Sep'), equals('22\nSep'));
      });

      test('shouldShowChartLabel samples cleanly based on count', () {
        // <= 7 points: all are shown
        for (int i = 0; i < 5; i++) {
          expect(shouldShowChartLabel(i, 5), isTrue);
        }
        for (int i = 0; i < 7; i++) {
          expect(shouldShowChartLabel(i, 7), isTrue);
        }

        // > 7 points (e.g. 30 days): first and last always shown, others sampled
        expect(shouldShowChartLabel(0, 30), isTrue);
        expect(shouldShowChartLabel(29, 30), isTrue);
        expect(shouldShowChartLabel(1, 30), isFalse);
      });
    });

    group('DashboardMetrics bars parsing tests (F2)', () {
      test(
        'parses expenses and distinguishes missing from zero period sales',
        () {
          final present = DashboardMetrics.fromJson({
            'periodSales': 0,
            'expenses': 45000,
          });
          final missing = DashboardMetrics.fromJson({'expenses': 0});

          expect(present.hasPeriodSales, isTrue);
          expect(present.expensesThisMonth, 45000);
          expect(missing.hasPeriodSales, isFalse);
        },
      );

      test(
        'fromJson without bars falls back gracefully and preserves cash',
        () {
          final json = {
            'todaySales': 1000,
            'cash': [
              {'label': 'Week 1', 'income': 500, 'expenses': 200},
            ],
          };
          final metrics = DashboardMetrics.fromJson(json);
          expect(metrics.bars, isEmpty);
          expect(metrics.cash.length, 1);
          expect(metrics.cash.first.income, 500);

          final outJson = metrics.toJson();
          expect(outJson['bars'], isEmpty);
        },
      );

      test('fromJson with bars parses bars correctly', () {
        final json = {
          'todaySales': 1000,
          'bars': [
            {'label': '1 Sep', 'amount': 15000},
            {'label': '2 Sep', 'amount': 25000},
          ],
        };
        final metrics = DashboardMetrics.fromJson(json);
        expect(metrics.bars.length, 2);
        expect(metrics.bars[0].label, '1 Sep');
        expect(metrics.bars[0].amount, 15000);
        expect(metrics.bars[1].label, '2 Sep');
        expect(metrics.bars[1].amount, 25000);

        final outJson = metrics.toJson();
        expect(outJson['bars'], isNotNull);
        expect((outJson['bars'] as List).length, 2);
      });
    });

    testWidgets('Chart shows the bars labels for a 7-day fixture (F2)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sevenDayBars = [
        DashboardBar(label: '1 Sep', amount: 10000),
        DashboardBar(label: '2 Sep', amount: 20000),
        DashboardBar(label: '3 Sep', amount: 15000),
        DashboardBar(label: '4 Sep', amount: 30000),
        DashboardBar(label: '5 Sep', amount: 25000),
        DashboardBar(label: '6 Sep', amount: 35000),
        DashboardBar(label: '7 Sep', amount: 40000),
      ];

      fakeOwnerRepo.metrics = DashboardMetrics(
        todaySales: 40000,
        todayCount: 5,
        periodSales: 175000,
        periodOrders: 20,
        bars: sevenDayBars,
        cash: [CashPoint(label: 'Mon', income: 30000, expenses: 10000)],
      );

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      expect(find.text('Sales by date'), findsOneWidget);
      // For <= 7 points, all points are shown formatted: "1\nSep", "2\nSep", etc.
      expect(find.text('1\nSep'), findsOneWidget);
      expect(find.text('7\nSep'), findsOneWidget);
    });

    group('Chart axis fixes', () {
      testWidgets('y-axis shows the ₹0 baseline', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 30000,
          periodSales: 90000,
          bars: [
            DashboardBar(label: '1 Sep', amount: 30000),
            DashboardBar(label: '2 Sep', amount: 60000),
            DashboardBar(label: '3 Sep', amount: 90000),
          ],
        );

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('₹0'), findsWidgets);
      });

      testWidgets('sales line does not overshoot below the baseline', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 4000,
          periodSales: 9500,
          bars: [0, 40, 0, 30, 12, 0, 13]
              .asMap()
              .entries
              .map(
                (e) => DashboardBar(
                  label: '${e.key + 1} Sep',
                  amount: e.value * 100,
                ),
              )
              .toList(),
        );

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.data.lineBarsData, isNotEmpty);
        for (final bar in chart.data.lineBarsData) {
          expect(bar.preventCurveOverShooting, isTrue);
        }
      });

      testWidgets(
        '7 and 12 point charts render on a narrow phone without errors',
        (tester) async {
          tester.view.physicalSize = const Size(360 * 3, 800 * 3);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          for (final count in [7, 12]) {
            fakeOwnerRepo.metrics = DashboardMetrics(
              todaySales: 10000,
              bars: List.generate(
                count,
                (i) =>
                    DashboardBar(label: '${i + 1} Sep', amount: (i + 1) * 3000),
              ),
              cash: List.generate(
                count,
                (i) => CashPoint(
                  label: '${i + 1} Sep',
                  income: 8000,
                  expenses: 3000,
                ),
              ),
            );
            await tester.pumpWidget(buildTestWidget());
            await pumpDashboard(tester);
            expect(tester.takeException(), isNull, reason: '$count points');
          }
        },
      );
    });

    testWidgets(
      '12b. Orders donut is larger and its legend shows share per stage',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        final donut = find.ancestor(
          of: find.byType(PieChart),
          matching: find.byType(SizedBox),
        );
        final size = tester.getSize(donut.first);
        expect(size.width, greaterThanOrEqualTo(120));
        expect(size.height, greaterThanOrEqualTo(120));
        // Every legend row now ends with a percentage.
        expect(find.textContaining('%'), findsWidgets);
      },
    );

    group('Drill-down and recent orders', () {
      Future<List<OrdersDrillDown?>> pumpWithCallback(
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final asked = <OrdersDrillDown?>[];
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<OwnerBloc>.value(value: ownerBloc),
                BlocProvider<OrdersBloc>.value(
                  value: MockOrdersBloc(mockOrdersRepo.cachedOrders),
                ),
                BlocProvider<AuthBloc>.value(value: authBloc),
              ],
              child: MaterialApp(
                home: OwnerDashboardScreen(onOpenOrders: asked.add),
              ),
            ),
          ),
        );
        await pumpDashboard(tester);
        return asked;
      }

      testWidgets('each count tile asks for its own view of the orders', (
        tester,
      ) async {
        final asked = await pumpWithCallback(tester);

        // The tiles sit above the charts, so the first match is the tile
        // ("Delivered" also appears in the donut legend and on a pill).
        await tester.tap(find.text('Open orders').first);
        await tester.tap(find.text('Delivered').first);
        await tester.tap(find.text('Due today').first);

        expect(asked, [
          OrdersDrillDown.open,
          OrdersDrillDown.deliveredToday,
          OrdersDrillDown.dueToday,
        ]);
      });

      testWidgets(
        'Recent orders lists the newest first and View all opens the plain list',
        (tester) async {
          final asked = await pumpWithCallback(tester);

          expect(find.text('Recent orders'), findsOneWidget);
          double y(String name) => tester.getTopLeft(find.text(name)).dy;
          // Fixture dates: Alice/David 12 Sep, Bob 10 Sep, Charlie 8 Sep.
          expect(y('Alice Smith'), lessThan(y('Bob Jones')));
          expect(y('David Later'), lessThan(y('Bob Jones')));
          expect(y('Bob Jones'), lessThan(y('Charlie Delivered')));

          await tester.tap(find.text('View all'));
          expect(asked, [null]);
        },
      );

      testWidgets('Recent orders shows at most five rows', (tester) async {
        mockOrdersRepo.cachedOrders = [
          for (var i = 1; i <= 8; i++)
            Order(
              id: 'ORD-$i',
              name: 'Customer $i',
              phone: '9876543210',
              date: '2026-09-${10 + i}',
              due: '2026-09-25',
              status: 'Pending',
              lines: [],
              payments: [],
            ),
        ];
        await pumpWithCallback(tester);

        expect(find.textContaining('Customer '), findsNWidgets(5));
        // The five newest: 18 down to 14 Sep.
        expect(find.text('Customer 8'), findsOneWidget);
        expect(find.text('Customer 4'), findsOneWidget);
        expect(find.text('Customer 3'), findsNothing);
      });

      testWidgets('no orders on the phone means no Recent orders card', (
        tester,
      ) async {
        mockOrdersRepo.cachedOrders = [];
        await pumpWithCallback(tester);
        expect(find.text('Recent orders'), findsNothing);
      });
    });

    group('Per-card period filters', () {
      String isoDay(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

      // The screen reads the clock while the test runs, so around midnight the
      // expected day may be either side of it: accept the day computed before
      // the test body or the one computed now.
      final testStart = DateTime.now();
      Matcher daysAgo(int days) => anyOf(
        isoDay(testStart.subtract(Duration(days: days))),
        isoDay(DateTime.now().subtract(Duration(days: days))),
      );

      // Monday of this week: what the "This week" chip starts from.
      Matcher weekStart() => anyOf(
        isoDay(
          DateTime(
            testStart.year,
            testStart.month,
            testStart.day - (testStart.weekday - 1),
          ),
        ),
        isoDay(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day - (DateTime.now().weekday - 1),
          ),
        ),
      );

      // First day of the month [back] months before this one.
      Matcher monthStart(int back) => anyOf(
        isoDay(DateTime(testStart.year, testStart.month - back, 1)),
        isoDay(DateTime(DateTime.now().year, DateTime.now().month - back, 1)),
      );

      Future<void> bigPhone(WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }

      testWidgets(
        'with the default period cached, opening makes no request at all',
        (tester) async {
          await bigPhone(tester);
          fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.requests, isEmpty);
          // Only Sales by date, which opens on this week, asks the server.
          expect(fakeOwnerRepo.periodRequests.length, 1);
          expect(fakeOwnerRepo.periodRequests.single.from, weekStart());
        },
      );

      testWidgets(
        'opening the page asks for the month-to-date daily request once',
        (tester) async {
          await bigPhone(tester);
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.requests.length, 1);
          final first = fakeOwnerRepo.requests.first;
          expect(first.granularity, 'day');
          expect(first.from, monthStart(0));
          expect(first.to, daysAgo(0));
          // ... plus the one week request for Sales by date.
          expect(fakeOwnerRepo.periodRequests.length, 1);
        },
      );

      testWidgets(
        'one chip tap makes exactly one request and leaves the page and the other card alone',
        (tester) async {
          await bigPhone(tester);
          fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
          fakeOwnerRepo.periodMetrics = DashboardMetrics(
            bars: [DashboardBar(label: '23 Sep', amount: 4000)],
            serviceMix: [ServiceMixItem(label: 'Only Ironing', amount: 4000)],
          );
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.periodRequests.length, 1); // the opening week
          await tester.tap(
            inFilter(filterDate, PeriodRange.previousMonthLabel()),
          );
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.periodRequests.length, 2);
          expect(fakeOwnerRepo.periodRequests.last.granularity, 'day');
          expect(fakeOwnerRepo.periodRequests.last.from, monthStart(1));
          // The page itself was not asked again ...
          expect(fakeOwnerRepo.requests, isEmpty);
          // ... the other card still shows the page's services ...
          expect(find.text('Wash & Fold'), findsOneWidget);
          expect(find.text('Only Ironing'), findsNothing);
          // ... and the money cards did not change label.
          expect(find.text('Sales this month'), findsOneWidget);
        },
      );

      testWidgets('each preset sends a daily request for its own dates', (
        tester,
      ) async {
        await bigPhone(tester);
        fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        await tester.tap(
          inFilter(filterService, PeriodRange.previousMonthLabel()),
        );
        await pumpDashboard(tester);
        expect(fakeOwnerRepo.periodRequests.last.granularity, 'day');
        expect(fakeOwnerRepo.periodRequests.last.from, monthStart(1));
        // The last day of last month is the day before this month starts.
        expect(
          fakeOwnerRepo.periodRequests.last.to,
          isoDay(
            DateTime(
              DateTime.now().year,
              DateTime.now().month,
              1,
            ).subtract(const Duration(days: 1)),
          ),
        );

        await tester.tap(inFilter(filterService, 'This week'));
        await pumpDashboard(tester);
        expect(fakeOwnerRepo.periodRequests.last.granularity, 'day');
        expect(fakeOwnerRepo.periodRequests.last.from, weekStart());
      });

      testWidgets(
        'back to the current month needs no request: the page already holds it',
        (tester) async {
          await bigPhone(tester);
          fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.periodRequests.length, 1); // the opening week
          await tester.tap(
            inFilter(filterDate, PeriodRange.previousMonthLabel()),
          );
          await pumpDashboard(tester);
          expect(fakeOwnerRepo.periodRequests.length, 2);

          await tester.tap(
            inFilter(filterDate, PeriodRange.currentMonthLabel()),
          );
          await pumpDashboard(tester);
          expect(fakeOwnerRepo.periodRequests.length, 2);
          expect(find.byType(LineChart), findsOneWidget);
        },
      );

      testWidgets(
        'only the changed card shows a spinner while its period loads',
        (tester) async {
          await bigPhone(tester);
          fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          double opacity() =>
              tester.widget<SliverOpacity>(find.byType(SliverOpacity)).opacity;

          fakeOwnerRepo.periodGate = Completer<void>();
          await tester.tap(inFilter(filterDate, 'This week'));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();

          expect(find.byType(LineChart), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          // No page-wide dimming, and the other cards are untouched.
          expect(opacity(), 1.0);
          expect(find.text('Collected vs expenses'), findsOneWidget);
          expect(find.text('Wash & Fold'), findsOneWidget);

          fakeOwnerRepo.periodGate!.complete();
          fakeOwnerRepo.periodGate = null;
          await pumpDashboard(tester);
          expect(find.byType(LineChart), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );

      testWidgets('a failed period says so and Retry asks again', (
        tester,
      ) async {
        await bigPhone(tester);
        fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        fakeOwnerRepo.periodShouldThrow = true;
        await tester.tap(inFilter(filterService, 'This week'));
        await pumpDashboard(tester);
        expect(find.text('Could not load this period'), findsOneWidget);
        // Never the month-to-date figures under a 7-day label.
        expect(find.text('Wash & Fold'), findsNothing);

        fakeOwnerRepo.periodShouldThrow = false;
        await tester.tap(find.text('Retry'));
        await pumpDashboard(tester);
        expect(fakeOwnerRepo.periodRequests.length, 3);
        expect(find.text('Could not load this period'), findsNothing);
        expect(find.text('Wash & Fold'), findsOneWidget);
      });

      testWidgets('an outlet switch resets both cards to the default', (
        tester,
      ) async {
        await bigPhone(tester);
        fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
        final signal = ValueNotifier<int>(0);
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<OwnerBloc>.value(value: ownerBloc),
                BlocProvider<OrdersBloc>.value(value: ordersBloc),
                BlocProvider<AuthBloc>.value(value: authBloc),
              ],
              child: MaterialApp(
                home: OwnerDashboardScreen(resetSignal: signal),
              ),
            ),
          ),
        );
        await pumpDashboard(tester);

        await tester.tap(inFilter(filterService, 'This week'));
        await pumpDashboard(tester);
        expect(
          ownerBloc.state.cards.containsKey(DashboardCard.salesByService),
          isTrue,
        );

        // Leaving the tab uses the same reset an outlet switch does.
        signal.value++;
        await pumpDashboard(tester);
        expect(
          ownerBloc.state.cards.containsKey(DashboardCard.salesByService),
          isFalse,
        );
        expect(
          tester.widget<PeriodFilter>(find.byKey(filterService)).value,
          PeriodRange.thisMonth,
        );
        // Sales by date goes back to its own default, this week.
        expect(
          tester.widget<PeriodFilter>(find.byKey(filterDate)).value,
          PeriodRange.last7,
        );
      });
    });

    group('Refresh, single-point chart and narrow large-text screens', () {
      Future<void> phone(
        WidgetTester tester, {
        Size size = const Size(800, 1600),
        double textScale = 1,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }

      testWidgets(
        'Refresh reloads a card that is on a non-default period too',
        (tester) async {
          await phone(tester);
          fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
          await tester.pumpWidget(buildTestWidget());
          await pumpDashboard(tester);

          expect(fakeOwnerRepo.periodRequests.length, 1); // the opening week
          await tester.tap(
            inFilter(filterDate, PeriodRange.previousMonthLabel()),
          );
          await pumpDashboard(tester);
          expect(fakeOwnerRepo.periodRequests.length, 2);

          await tester.tap(find.byTooltip('Refresh'));
          await pumpDashboard(tester);
          // The page reloaded, and so did the card on last month (only it).
          expect(fakeOwnerRepo.requests, isNotEmpty);
          expect(fakeOwnerRepo.periodRequests.length, 3);
          expect(
            fakeOwnerRepo.periodRequests.last.from,
            fakeOwnerRepo.periodRequests[1].from,
          );
        },
      );

      testWidgets('a one-point sales trend draws without errors', (
        tester,
      ) async {
        await phone(tester);
        fakeOwnerRepo.cachedDefault = DashboardMetrics(
          bars: [DashboardBar(label: '23 Sep', amount: 4000)],
          serviceMix: [ServiceMixItem(label: 'Only Ironing', amount: 4000)],
        );
        fakeOwnerRepo.periodMetrics = fakeOwnerRepo.cachedDefault;
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // One day starts the line at zero instead of drawing a lone dot.
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final spots = chart.data.lineBarsData.single.spots;
        expect(spots.length, 2);
        expect(spots.first.y, 0);
        expect(spots.last.y, 40);
        expect(chart.data.maxX, greaterThan(chart.data.minX));
        expect(tester.takeException(), isNull);
      });

      for (final dark in [false, true]) {
        testWidgets(
          '320x568 at 1.5x text (${dark ? 'dark' : 'light'}): every card, '
          'per-card filter and Recent orders lay out without overflow',
          (tester) async {
            await phone(tester, size: const Size(320, 568), textScale: 1.5);
            fakeOwnerRepo.cachedDefault = fakeOwnerRepo.metrics;
            await tester.pumpWidget(
              buildTestWidget(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
              ),
            );
            await pumpDashboard(tester);
            expect(tester.takeException(), isNull);

            // Walk down the whole page, then open a per-card range.
            final scroll = find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first;
            var openedRange = false;
            var sawRecentOrders = false;
            for (var i = 0; i < 12; i++) {
              await tester.drag(scroll, const Offset(0, -300));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final seven = inFilter(filterService, 'This week');
              if (!openedRange && seven.evaluate().isNotEmpty) {
                await tester.ensureVisible(seven);
                await tester.pumpAndSettle();
                await tester.tap(seven);
                await pumpDashboard(tester);
                expect(tester.takeException(), isNull);
                openedRange = true;
              }
              sawRecentOrders =
                  sawRecentOrders ||
                  find.text('Recent orders').evaluate().isNotEmpty;
            }
            expect(openedRange, isTrue);
            expect(sawRecentOrders, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    });

    group('Bloc: failed page load', () {
      test('with nothing cached, a failed load for a new outlet drops the old outlet\'s figures and is no longer "stale"', () async {
        final repo = FakeDashboardOwnerRepository(
          metrics: DashboardMetrics(todaySales: 5000),
        );
        final bloc = OwnerBloc(ownerRepository: repo);

        bloc.add(LoadDashboardEvent(requestKey: 'outlet-a'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.dashboardKey, 'outlet-a');
        expect(bloc.state.metrics.todaySales, 5000);

        repo.shouldThrow = true;
        bloc.add(LoadDashboardEvent(requestKey: 'outlet-b', refresh: true));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // The screen compares this key with the selection: equal means it
        // stops dimming; the old outlet's ₹50 is not shown under outlet B.
        expect(bloc.state.dashboardKey, 'outlet-b');
        expect(bloc.state.metrics.todaySales, 0);
        expect(bloc.state.error, isNotNull);
        await bloc.close();
      });

      test(
        'a failed refresh of the same selection keeps its figures',
        () async {
          final repo = FakeDashboardOwnerRepository(
            metrics: DashboardMetrics(todaySales: 5000),
          );
          final bloc = OwnerBloc(ownerRepository: repo);
          bloc.add(LoadDashboardEvent(requestKey: 'outlet-a'));
          await Future<void>.delayed(const Duration(milliseconds: 20));

          repo.shouldThrow = true;
          bloc.add(LoadDashboardEvent(requestKey: 'outlet-a', refresh: true));
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(bloc.state.metrics.todaySales, 5000);
          await bloc.close();
        },
      );
    });

    // The stale-card-reply tests (two separate gates) live in
    // owner_data_layer_test.dart.
  });
}
