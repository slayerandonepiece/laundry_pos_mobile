import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/shared/widgets/empty_state.dart';

class MockOrdersRepository implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDashboardOwnerRepository extends OwnerRepository {
  DashboardMetrics metrics;

  FakeDashboardOwnerRepository({required this.metrics})
      : super(apiClient: ApiClient());

  @override
  Future<DashboardMetrics> getDashboardMetrics(
      {String? from, String? to}) async {
    return metrics;
  }
}

void main() {
  group('OwnerDashboardScreen Slivers & fl_chart Tests', () {
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
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Dry Clean Saree',
              quantity: 1,
              unit: 'PIECE',
              amount: 25000,
            ),
          ],
          payments: [],
        ),
        Order(
          id: 'ORD-002',
          name: 'Bob Jones',
          phone: '9876543211',
          date: '2026-09-10',
          due: '2026-09-11',
          status: 'Ready',
          lines: [
            OrderLine(
              productId: 'p2',
              name: 'Wash & Iron',
              quantity: 2,
              unit: 'PIECE',
              amount: 15000,
            ),
          ],
          payments: [],
        ),
        Order(
          id: 'ORD-003',
          name: 'Charlie Delivered',
          phone: '9876543212',
          date: '2026-09-08',
          due: '2026-09-09',
          status: 'Delivered',
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Dry Clean Saree',
              quantity: 1,
              unit: 'PIECE',
              amount: 25000,
            ),
          ],
          payments: [],
        ),
        Order(
          id: 'ORD-004',
          name: 'David Later',
          phone: '9876543213',
          date: '2026-09-12',
          due: '2026-09-15',
          status: 'In Progress',
          lines: [
            OrderLine(
              productId: 'p2',
              name: 'Wash & Iron',
              quantity: 1,
              unit: 'PIECE',
              amount: 10000,
            ),
          ],
          payments: [],
        ),
      ];

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
          child: const MaterialApp(
            home: OwnerDashboardScreen(),
          ),
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
      '1. Four stat cards render correct metric values in the new SliverGrid layout',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(find.byType(SliverGrid), findsOneWidget);

        // Check stat card labels & values in SliverGrid
        expect(find.text("Today's sales"), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverGrid),
            matching: find.text('₹500'),
          ),
          findsOneWidget,
        );
        expect(find.text('2 orders'), findsOneWidget);

        expect(find.text('Yesterday'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverGrid),
            matching: find.text('₹1,200'),
          ),
          findsOneWidget,
        );
        expect(find.text('5 orders'), findsOneWidget);

        expect(find.text('To collect'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverGrid),
            matching: find.text('₹300'),
          ),
          findsOneWidget,
        );
        expect(find.text('3 orders waiting'), findsOneWidget);

        expect(find.text('To finish'), findsWidgets);
        expect(
          find.descendant(
            of: find.byType(SliverGrid),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(find.text('1 overdue · '), findsOneWidget);
        expect(find.text('2 due today'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Sales trend chart renders when cash is non-empty and hides when cash is empty',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Non-empty case:
        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Sales trend'), findsOneWidget);
        expect(find.byType(LineChart), findsOneWidget);

        // Empty case:
        fakeOwnerRepo.metrics = DashboardMetrics(
          todaySales: 10000,
          cash: [], // empty cash
        );
        ownerBloc.add(LoadDashboardEvent());
        await pumpDashboard(tester);

        expect(find.text('Sales trend'), findsNothing);
        expect(find.byType(LineChart), findsNothing);
      },
    );

    testWidgets(
      '3. Order status donut shows correct completed and todo counts with legend',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Order status'), findsOneWidget);
        expect(find.byType(PieChart), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('To finish'), findsWidgets); // Stat card + donut legend
      },
    );

    testWidgets(
      '4. "Orders to finish" sliver list displays non-delivered orders sorted by due date and navigates on tap',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Orders to finish'), findsOneWidget);

        // Delivered order Charlie must NOT be present
        expect(find.text('Charlie Delivered'), findsNothing);

        // Remaining 3 orders should be present
        expect(find.text('Bob Jones'), findsOneWidget);
        expect(find.text('Alice Smith'), findsOneWidget);
        expect(find.text('David Later'), findsOneWidget);

        // Tap Bob Jones order card -> should push OrderDetailScreen
        await tester.tap(find.text('Bob Jones'));
        await tester.pumpAndSettle();

        expect(find.byType(OrderDetailScreen), findsOneWidget);
        expect(find.text('ORD-002'), findsWidgets);
      },
    );

    testWidgets(
      '5. "Orders to finish" displays empty state when all orders are delivered or list is empty',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Set all orders delivered
        mockOrdersRepo.cachedOrders = [
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
        ];

        await tester.pumpWidget(buildTestWidget());
        await pumpDashboard(tester);

        expect(find.text('Orders to finish'), findsOneWidget);
        expect(find.byType(EmptyState), findsOneWidget);
        expect(find.text('Nothing here yet'), findsOneWidget);
        expect(
          find.text("Nothing due today or overdue, you're all caught up"),
          findsOneWidget,
        );
      },
    );
  });
}
