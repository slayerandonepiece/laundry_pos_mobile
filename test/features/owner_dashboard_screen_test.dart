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

  FakeDashboardOwnerRepository({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    if (shouldThrow) throw Exception('Network error');
    return metrics;
  }

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOrdersRepository implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

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

    Widget buildTestWidget() {
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
          child: const MaterialApp(home: OwnerDashboardScreen()),
        ),
      );
    }

    Future<void> pumpDashboard(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets(
      '1. Two hero money cards render correct values and "Sales today" card is visually distinguished',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        expect(todayValueText.style?.fontSize, 28);
        expect(todayValueText.style?.fontWeight, FontWeight.w500);

        // Card 2: "Sales this month" (default period is now '30d')
        expect(find.text('Sales this month'), findsOneWidget);
        expect(find.text('₹1,200'), findsOneWidget);
        expect(find.text('5 orders'), findsOneWidget);

        // Assert period sales value is styled with AppColors.text (not accent)
        final periodValueText = tester.widget<Text>(find.text('₹1,200'));
        expect(periodValueText.style?.color, AppColors.text);
        expect(periodValueText.style?.fontSize, 28);
        expect(periodValueText.style?.fontWeight, FontWeight.w500);
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
      '3. Period selector pill displays current selection and changes on selection',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // Initial period defaults to '30d', rendered as 'This month'
        expect(find.text('This month'), findsOneWidget);

        // Tap period pill to open menu
        await tester.tap(find.text('This month'));
        await tester.pumpAndSettle();

        // PopupMenu shows all 3 options
        expect(find.text('Today'), findsWidgets);
        expect(find.text('This week'), findsOneWidget);

        // Tap 'Today'
        await tester.tap(find.text('Today').last);
        await pumpDashboard(tester);

        // Pill label updates to 'Today'
        expect(find.text('Today'), findsOneWidget);

        // Card 2 title updates to 'Sales yesterday'
        expect(find.text('Sales yesterday'), findsOneWidget);
      },
    );

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
        expect(find.text('How your sales moved this month'), findsOneWidget);
        expect(find.byType(LineChart), findsOneWidget);

        // Check line color matches app theme (AppColors.primary)
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(lineChart.data.lineBarsData.first.color, AppColors.primary);

        // Empty cash case
        fakeOwnerRepo.metrics = DashboardMetrics(todaySales: 10000, cash: []);
        ownerBloc.add(LoadDashboardEvent());
        await pumpDashboard(tester);

        expect(find.text('Sales by date'), findsNothing);
        expect(find.byType(LineChart), findsNothing);
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
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Ready'), findsOneWidget);
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

        expect(find.text('Sales by service'), findsNothing);
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

        // Neither section header nor "View all" exists
        expect(find.text('Orders to finish'), findsNothing);
        expect(find.text('View all'), findsNothing);

        // Order cards are not present on dashboard
        expect(find.text('Bob Jones'), findsNothing);
        expect(find.text('Alice Smith'), findsNothing);
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
      '11. "Collected vs expenses — this month" net cash-flow chart renders net total, received/spent, and grouped BarChart',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Collected vs expenses — this month'), findsOneWidget);
        expect(find.text('payments collected this month'), findsOneWidget);
        expect(find.byType(BarChart), findsOneWidget);

        // cash fixture: income: 300+500+400 = 1200 (₹1,200), expenses: 100+200+150 = 450 (₹450), net = 750 (₹750)
        expect(find.text('₹750'), findsOneWidget);
        expect(find.text('₹1,200 received'), findsOneWidget);
        expect(find.text('₹450 spent'), findsOneWidget);

        final barChart = tester.widget<BarChart>(find.byType(BarChart));
        expect(barChart.data.barGroups.length, 3);
        expect(barChart.data.barGroups.first.barRods.length, 2);
        expect(
          barChart.data.barGroups.first.barRods[0].color,
          AppColors.primary,
        );
        expect(
          barChart.data.barGroups.first.barRods[1].color,
          AppColors.warning,
        );
      },
    );

    testWidgets(
      '12. Selecting "This quarter" and "Custom dates" in period selector pill',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        // Tap period selector pill
        await tester.tap(find.text('This month'));
        await tester.pumpAndSettle();

        // Check options
        expect(find.text('This quarter'), findsOneWidget);
        expect(find.text('Custom dates'), findsOneWidget);

        // Tap This quarter
        await tester.tap(find.text('This quarter'));
        await pumpDashboard(tester);

        expect(find.text('This quarter'), findsOneWidget);
        expect(find.text('Sales this quarter'), findsOneWidget);

        // Tap period selector pill again and select Custom dates
        await tester.tap(find.text('This quarter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom dates'));
        await pumpDashboard(tester);

        // Inline From / To selector appears
        expect(find.text('FROM'), findsOneWidget);
        expect(find.text('TO'), findsOneWidget);
      },
    );

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
        expect(formatChartLabel('1 Sept 2026–6 Sept 2026'), equals('1–6 Sep'));
        expect(
          formatChartLabel('7 Sept 2026 - 12 Sept 2026'),
          equals('7–12 Sep'),
        );
        expect(
          formatChartLabel('13 September 2026–18 September 2026'),
          equals('13–18 Sep'),
        );
        expect(
          formatChartLabel('28 Aug 2026–3 Sep 2026'),
          equals('28 Aug–3 Sep'),
        );
      });

      test('formats single dates and weekdays cleanly', () {
        expect(formatChartLabel('1 Sept 2026'), equals('1 Sep'));
        expect(formatChartLabel('28 September'), equals('28 Sep'));
        expect(formatChartLabel('2026-09-15'), equals('15 Sep'));
        expect(formatChartLabel('Monday'), equals('Mon'));
        expect(formatChartLabel('Mon'), equals('Mon'));
        expect(formatChartLabel('September 2026'), equals('Sep'));
        expect(formatChartLabel(''), equals(''));
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
  });
}
