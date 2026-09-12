import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_colors.dart';
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
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';

class FakeDashboardOwnerRepository implements OwnerRepository {
  DashboardMetrics metrics;

  FakeDashboardOwnerRepository({required this.metrics});

  @override
  Future<DashboardMetrics> getDashboardMetrics({String? from, String? to}) async => metrics;

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

class MockOrdersBloc extends Bloc<OrdersEvent, OrdersState> implements OrdersBloc {
  MockOrdersBloc([List<Order> orders = const []]) : super(OrdersState(allOrders: orders)) {
    on<LoadOrdersEvent>((event, emit) {});
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

      ownerBloc = OwnerBloc(ownerRepository: fakeOwnerRepo);
      ordersBloc = OrdersBloc(ordersRepository: mockOrdersRepo);
      authBloc = MockAuthBloc();
    });

    Widget buildTestWidget() {
      return MultiRepositoryProvider(
        providers: [RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo)],
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

    testWidgets('1. Two hero money cards render correct values and "Sales today" card is visually distinguished', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SliverAppBar), findsOneWidget);

      // Eyebrow and expanded title
      expect(find.text('MYSHOP WORKSPACE'), findsOneWidget);
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
            .ancestor(
              of: find.text('₹500'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (todayCardContainer.decoration as BoxDecoration).color,
        AppColors.primary,
      );
      expect(todayValueText.style?.fontSize, 28);
      expect(todayValueText.style?.fontWeight, FontWeight.w500);

      // Card 2: "Sales yesterday" (when 'today' selected)
      expect(find.text('Sales yesterday'), findsOneWidget);
      expect(find.text('₹1,200'), findsOneWidget);
      expect(find.text('5 orders'), findsOneWidget);

      // Assert period sales value is styled with AppColors.text (not accent)
      final periodValueText = tester.widget<Text>(find.text('₹1,200'));
      expect(periodValueText.style?.color, AppColors.text);
      expect(periodValueText.style?.fontSize, 28);
      expect(periodValueText.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('2. Compact 3-chip row shows correct operational counts', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      // Operational chips
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // metrics.todo

      expect(find.text('Completed'), findsWidgets); // chip + donut legend
      expect(find.text('7'), findsOneWidget); // metrics.completed

      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // metrics.dueToday: 2
    });

    testWidgets('3. Period selector pill displays current selection and changes on selection', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      // Initial period is 'today', rendered as 'Today'
      expect(find.text('Today'), findsOneWidget);

      // Tap period pill to open menu
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // PopupMenu shows all 3 options
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);

      // Tap 'This week'
      await tester.tap(find.text('This week').last);
      await pumpDashboard(tester);

      // Pill label updates to 'This week'
      expect(find.text('This week'), findsOneWidget);

      // Card 2 title updates to 'Sales this week'
      expect(find.text('Sales this week'), findsOneWidget);
    });

    testWidgets('4. "Sales by date" trend chart renders with muted color and empty-guard works', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      expect(find.text('Sales by date'), findsOneWidget);
      expect(find.text('How your sales moved today'), findsOneWidget);
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
    });

    testWidgets(
      '5. "How orders are moving" donut/legend has exactly 3 buckets summing to allOrders.length with StatusPill matching colors',
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

        // 3 buckets derived from mockOrdersRepo (4 orders total: 1 Pending, 1 Ready, 1 Delivered, 1 In Progress)
        // Ready + In Progress = 2 in 'In progress'
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Completed'), findsWidgets);

        // Check PieChart sections count, sum, and matching colors
        final pieChart = tester.widget<PieChart>(find.byType(PieChart));
        final sections = pieChart.data.sections;
        expect(sections.length, 3);

        // Pending: value 1, color AppColors.neutralText
        expect(sections[0].value, 1.0);
        expect(sections[0].color, AppColors.neutralText);

        // In progress: value 2, color AppColors.primary
        expect(sections[1].value, 2.0);
        expect(sections[1].color, AppColors.primary);

        // Completed: value 1, color AppColors.success
        expect(sections[2].value, 1.0);
        expect(sections[2].color, AppColors.success);

        // Sum of counts equals mockOrdersRepo.cachedOrders.length (1 + 2 + 1 = 4)
        final totalOrderCount = sections.fold<double>(0, (sum, s) => sum + s.value);
        expect(totalOrderCount.toInt(), mockOrdersRepo.cachedOrders.length);
      },
    );

    testWidgets('6. When allOrders is empty, "How orders are moving" section is not rendered', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyOrdersBloc = MockOrdersBloc([]);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo)],
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
    });

    testWidgets('7. "Sales by service" chart renders with muted bar color and empty-guard works', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      expect(find.text('Sales by service'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);

      final barChart = tester.widget<BarChart>(find.byType(BarChart));
      expect(barChart.data.barGroups.first.barRods.first.color, AppColors.primary);

      // Empty serviceMix
      fakeOwnerRepo.metrics = DashboardMetrics(todaySales: 10000, serviceMix: []);
      ownerBloc.add(LoadDashboardEvent());
      await pumpDashboard(tester);

      expect(find.text('Sales by service'), findsNothing);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('8. "Orders to finish" section is completely removed from widget tree', (tester) async {
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
    });

    testWidgets('9. Custom SliverAppBar collapses on scroll and reveals avatar + title in toolbar', (tester) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      await pumpDashboard(tester);

      // Drag up to scroll down and trigger collapse
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Collapsed toolbar row shows store initials avatar
      expect(find.text('MY'), findsOneWidget); // Initials of MyShop
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Dashboard' && w.style?.fontSize == 18),
        findsOneWidget,
      );
    });
  });
}
