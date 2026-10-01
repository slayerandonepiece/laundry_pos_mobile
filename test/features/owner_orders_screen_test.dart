import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/presentation/orders_drill_down.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/period_filter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/owner/presentation/owner_orders_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

class FailingApiClient extends ApiClient {
  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    throw Exception('Network unreachable');
  }
}

class FakeLocalCache extends LocalCacheService {
  List<Map<String, dynamic>>? allowedOutlets = [
    {
      'id': 'outlet_main',
      'outletCode': 'O01',
      'displayName': 'Main Outlet',
      'isDefault': true,
      'status': 'ACTIVE',
    },
  ];
  String? activeOutletId;
  List<Map<String, dynamic>>? cachedOrdersJson;

  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'OWNER'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => allowedOutlets;
  @override
  String? getActiveOutletId() => activeOutletId;
  @override
  bool isAllOutletsScope() => activeOutletId == null;
  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
  // OutletScopeCubit.hydrate persists the resolved scope; keep it in memory.
  @override
  Future<void> setActiveOutletId(String outletId) async {}
  @override
  Future<void> clearActiveOutletId() async {}
  @override
  Future<void> setAllOutletsScope(bool value) async {}
  @override
  Future<void> clearAllOutletsScope() async {}
  @override
  List<Map<String, dynamic>>? getCachedOrders({
    String? outletId,
    bool? allOutlets,
  }) => cachedOrdersJson;
}

class MockOrdersRepository implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList() => cachedOrders;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPosRepository implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OwnerOrdersScreen Tests', () {
    late MockOrdersRepository mockOrdersRepo;
    late MockPosRepository mockPosRepo;
    late List<Order> fakeOrders;

    final now = DateTime.now();
    final todayStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    setUp(() {
      mockOrdersRepo = MockOrdersRepository();
      mockPosRepo = MockPosRepository();

      fakeOrders = [
        Order(
          id: 'ORD-101',
          name: 'Alice Smith',
          phone: '9876543210',
          date: todayStr,
          due: todayStr,
          status: 'Pending',
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Wash & Fold',
              quantity: 2,
              unit: 'PIECE',
              amount: 20000, // ₹200
            ),
          ],
          payments: [
            OrderPayment(
              id: 'pay-1',
              amount: 15000, // ₹150
              date: todayStr,
              method: 'Cash',
            ),
          ], // total: 20000 (₹200), paid: 15000 (₹150), balance: 5000 (₹50)
        ),
        Order(
          id: 'ORD-102',
          name: 'Bob Jones',
          phone: '9123456789',
          date: todayStr,
          due: todayStr,
          status: 'Ready',
          lines: [
            OrderLine(
              productId: 'p2',
              name: 'Dry Clean',
              quantity: 1,
              unit: 'PIECE',
              amount: 30000, // ₹300
            ),
          ],
          payments: [
            OrderPayment(
              id: 'pay-2',
              amount: 30000, // ₹300
              date: todayStr,
              method: 'UPI',
            ),
          ], // total: 30000 (₹300), paid: 30000 (₹300), balance: 0
        ),
        Order(
          id: 'ORD-103',
          name: 'Charlie Brown',
          phone: '9998887776',
          // Created today so it is inside the default month-to-date period
          // even on the 1st of a month; it is late because it was due
          // yesterday.
          date: todayStr,
          due: yesterdayStr,
          status: 'In Progress',
          lines: [
            OrderLine(
              productId: 'p3',
              name: 'Ironing',
              quantity: 1,
              unit: 'PIECE',
              amount: 10000, // ₹100
            ),
          ],
          payments: [], // total: 10000 (₹100), paid: 0, balance: 10000 (₹100)
        ),
      ];

      mockOrdersRepo.cachedOrders = fakeOrders;
    });

    Widget createScreen({
      FakeLocalCache? cache,
      ValueNotifier<OrdersDrillDown?>? drillDown,
      ThemeData? theme,
    }) {
      final ordersBloc = OrdersBloc(ordersRepository: mockOrdersRepo);
      final cartBloc = CartBloc(posRepository: mockPosRepo);
      final authBloc = MockAuthBloc();
      final outletScopeCubit = OutletScopeCubit(
        localCache: cache ?? FakeLocalCache(),
      )..hydrate();

      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
          RepositoryProvider<PosRepository>.value(value: mockPosRepo),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<OrdersBloc>.value(value: ordersBloc),
            BlocProvider<CartBloc>.value(value: cartBloc),
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider<OutletScopeCubit>.value(value: outletScopeCubit),
          ],
          child: MaterialApp(
            theme: theme,
            home: OwnerOrdersScreen(drillDown: drillDown),
          ),
        ),
      );
    }

    testWidgets('Stats compute correctly from fixed fake orders', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Default period is 'This month', so today's and yesterday's orders
      // all match: order value = ₹600, collected = ₹450, to collect = ₹150
      expect(find.text('Sales summary'), findsOneWidget);
      expect(find.text('Total order value'), findsOneWidget);
      expect(find.text('₹600'), findsOneWidget);
      expect(find.text('3 orders'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
      expect(find.text('To collect'), findsOneWidget);
      expect(find.text('₹150'), findsOneWidget);

      // All three orders are visible in the list
      expect(find.text('ORD-101'), findsOneWidget);
      expect(find.text('ORD-102'), findsOneWidget);
      expect(find.text('ORD-103'), findsOneWidget);
    });

    testWidgets(
      'Quick filter chips are mutually exclusive and filter properly',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        // Default: 'Selected dates' is active, period defaults to 'This month'
        // so all three orders (today + yesterday) match.
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsOneWidget);

        // Tap 'Late'
        await tester.tap(find.text('Late'));
        await tester.pumpAndSettle();

        // ORD-103 is late (due yesterday, not delivered).
        expect(find.text('ORD-103'), findsOneWidget);
        expect(find.text('ORD-101'), findsNothing);
        expect(find.text('ORD-102'), findsNothing);

        // Stats for Late: order value ₹100, collected ₹0, to collect ₹100, 1 matching order
        // (₹100 appears in Order value stat card, To collect stat card, and ORD-103 card total)
        expect(find.text('₹100'), findsNWidgets(3));
        expect(find.text('1 order'), findsOneWidget);
        expect(find.text('₹0'), findsOneWidget); // Collected

        // Tap 'Due today'
        await tester.tap(find.text('Due today'));
        await tester.pumpAndSettle();

        // ORD-101 and ORD-102 are due today
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsNothing);

        // Tap 'Selected dates' back
        await tester.tap(find.text('Selected dates'));
        await tester.pumpAndSettle();
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsOneWidget);
      },
    );

    testWidgets('Search filters by customer name and phone', (tester) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Search by name 'Bob'
      await tester.enterText(find.byType(TextField), 'Bob');
      await tester.pumpAndSettle();

      expect(find.text('ORD-102'), findsOneWidget);
      expect(find.text('ORD-101'), findsNothing);
      expect(find.text('1 order'), findsOneWidget);

      // Search by phone '987654'
      await tester.enterText(find.byType(TextField), '987654');
      await tester.pumpAndSettle();

      expect(find.text('ORD-101'), findsOneWidget);
      expect(find.text('ORD-102'), findsNothing);

      // Search with non-matching query
      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No orders match your filters'), findsOneWidget);
      expect(find.text('ORD-101'), findsNothing);
      expect(find.text('ORD-102'), findsNothing);
    });

    testWidgets('Tapping order card navigates to OrderDetailScreen', (
      tester,
    ) async {
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      expect(find.text('ORD-101'), findsOneWidget);
      await tester.tap(find.text('ORD-101'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
    });

    testWidgets(
      'Tapping + button in allOutlets scope shows outlet sheet and navigates on selection',
      (tester) async {
        final cache = FakeLocalCache()
          ..allowedOutlets = [
            {
              'id': 'outlet_main',
              'outletCode': 'O01',
              'displayName': 'Main Outlet',
              'isDefault': true,
              'status': 'ACTIVE',
            },
            {
              'id': 'outlet_second',
              'outletCode': 'O02',
              'displayName': 'Second Outlet',
              'isDefault': false,
              'status': 'ACTIVE',
            },
          ];
        await tester.pumpWidget(createScreen(cache: cache));
        await tester.pumpAndSettle();

        final addButton = find.byIcon(Icons.add);
        expect(addButton, findsOneWidget);

        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(find.text('Select outlet'), findsOneWidget);
        expect(find.text('Main Outlet'), findsOneWidget);

        await tester.tap(find.text('Main Outlet'));
        await tester.pumpAndSettle();

        expect(find.byType(CustomerDetailsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping + button in allOutlets scope cancels when sheet is dismissed',
      (tester) async {
        final cache = FakeLocalCache()
          ..allowedOutlets = [
            {
              'id': 'outlet_main',
              'outletCode': 'O01',
              'displayName': 'Main Outlet',
              'isDefault': true,
              'status': 'ACTIVE',
            },
            {
              'id': 'outlet_second',
              'outletCode': 'O02',
              'displayName': 'Second Outlet',
              'isDefault': false,
              'status': 'ACTIVE',
            },
          ];
        await tester.pumpWidget(createScreen(cache: cache));
        await tester.pumpAndSettle();

        final addButton = find.byIcon(Icons.add);
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(find.text('Select outlet'), findsOneWidget);

        // Tap barrier to dismiss sheet
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(find.byType(CustomerDetailsScreen), findsNothing);
      },
    );

    testWidgets(
      'Tapping + button with narrowed activeOutletId navigates directly without sheet',
      (tester) async {
        final cache = FakeLocalCache()..activeOutletId = 'outlet_main';
        await tester.pumpWidget(createScreen(cache: cache));
        await tester.pumpAndSettle();

        final addButton = find.byIcon(Icons.add);
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(find.text('Select outlet'), findsNothing);
        expect(find.byType(CustomerDetailsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Work status and payment status dropdown filters work as expected with Part-paid',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        // Initially ORD-101 (Pending, Partial/Part-paid) and ORD-102 (Ready, Paid) are visible
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);

        // Filter by payment status: Part-paid (replaces 'Partial')
        await tester.tap(find.text('Payment status'));
        await tester.pumpAndSettle();
        expect(find.text('Part-paid'), findsWidgets);
        await tester.tap(find.text('Part-paid').last);
        await tester.pumpAndSettle();

        // Only ORD-101 is part-paid
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsNothing);

        // Filter by work status: Ready
        await tester.tap(find.text('Work status'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ready').last);
        await tester.pumpAndSettle();

        // Neither matches (ORD-101 is part-paid but Pending, ORD-102 is Ready but Paid)
        expect(find.text('ORD-101'), findsNothing);
        expect(find.text('ORD-102'), findsNothing);
      },
    );

    group('Dashboard drill-down', () {
      late String today;

      Future<void> withDeliveredOrders(WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        today = fakeOrders.first.date;
        mockOrdersRepo.cachedOrders = [
          ...fakeOrders,
          Order(
            id: 'ORD-201',
            name: 'Dina Delivered',
            phone: '9000000001',
            date: today,
            due: today,
            status: 'Delivered',
            completed: today,
            lines: [],
            payments: [],
          ),
          Order(
            id: 'ORD-202',
            name: 'Old Delivered',
            phone: '9000000002',
            date: yesterdayStr,
            due: yesterdayStr,
            status: 'Delivered',
            completed: yesterdayStr,
            lines: [],
            payments: [],
          ),
        ];
      }

      testWidgets('Open shows every undelivered order and no delivered ones', (
        tester,
      ) async {
        await withDeliveredOrders(tester);
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();

        request.value = OrdersDrillDown.open;
        await tester.pumpAndSettle();

        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsOneWidget);
        expect(find.text('ORD-201'), findsNothing);
        expect(find.text('ORD-202'), findsNothing);
        // The request is consumed, and the plain list can be restored.
        expect(request.value, isNull);
        expect(find.text('Clear'), findsOneWidget);
      });

      testWidgets('Delivered today shows only orders handed over today', (
        tester,
      ) async {
        await withDeliveredOrders(tester);
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();

        request.value = OrdersDrillDown.deliveredToday;
        await tester.pumpAndSettle();

        expect(find.text('ORD-201'), findsOneWidget);
        expect(find.text('ORD-202'), findsNothing);
        expect(find.text('ORD-101'), findsNothing);
      });

      testWidgets('Due today shows undelivered orders due today', (
        tester,
      ) async {
        await withDeliveredOrders(tester);
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();

        request.value = OrdersDrillDown.dueToday;
        await tester.pumpAndSettle();

        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsNothing);
        expect(find.text('ORD-201'), findsNothing);
      });

      testWidgets(
        'a drill-down starts from the plain list, not on top of old filters',
        (tester) async {
          await withDeliveredOrders(tester);
          final request = ValueNotifier<OrdersDrillDown?>(null);
          await tester.pumpWidget(createScreen(drillDown: request));
          await tester.pumpAndSettle();

          // An earlier search that would hide everything the tile promises.
          await tester.enterText(find.byType(TextField), 'zzz-nothing');
          await tester.pumpAndSettle();

          request.value = OrdersDrillDown.open;
          await tester.pumpAndSettle();

          expect(find.text('ORD-101'), findsOneWidget);
        },
      );

      testWidgets('the chip for the requested view is scrolled into sight', (
        tester,
      ) async {
        await withDeliveredOrders(tester);
        // A phone-width screen, where the right-hand chips start off-screen.
        tester.view.physicalSize = const Size(390, 1600);
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();

        request.value = OrdersDrillDown.deliveredToday;
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.text('Delivered today').first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(390));
      });

      testWidgets('an empty Open view says everything is delivered', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        mockOrdersRepo.cachedOrders = [
          Order(
            id: 'ORD-301',
            name: 'Only Delivered',
            phone: '9000000003',
            date: fakeOrders.first.date,
            due: fakeOrders.first.date,
            status: 'Delivered',
            completed: fakeOrders.first.date,
            lines: [],
            payments: [],
          ),
        ];
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();

        request.value = OrdersDrillDown.open;
        await tester.pumpAndSettle();

        expect(find.text('No open orders'), findsOneWidget);
        expect(find.text('Everything has been delivered.'), findsOneWidget);
      });
    });

    testWidgets(
      'Clear sits in the dropdown row, appears only with a filter, and moves nothing',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        final work = find.byKey(const ValueKey('work-status-filter'));
        final payment = find.byKey(const ValueKey('payment-status-filter'));

        // Nothing narrowed: no Clear at all.
        expect(find.text('Clear'), findsNothing);
        final workBefore = tester.getRect(work);
        final paymentBefore = tester.getRect(payment);
        expect(workBefore.height, 44);
        expect(paymentBefore.height, 44);

        // Apply a quick filter.
        await tester.tap(find.text('Late'));
        await tester.pumpAndSettle();
        expect(find.text('ORD-101'), findsNothing);

        // Clear is now offered, on the same row, same height, and the
        // dropdowns did not change width or position.
        final clear = find.text('Clear');
        expect(clear, findsOneWidget);
        final clearButton = find.ancestor(
          of: clear,
          matching: find.byType(TextActionButton),
        );
        final clearRect = tester.getRect(clearButton);
        expect(clearRect.height, 44);
        // (The quick view's subtitle now adds a line above the row, so
        // compare against the dropdowns' current position, not their old one.)
        final workNow = tester.getRect(work);
        expect(clearRect.center.dy, workNow.center.dy);
        expect(
          clearRect.left,
          greaterThanOrEqualTo(tester.getRect(payment).right),
        );
        expect(workNow.width, workBefore.width);
        expect(tester.getRect(payment).width, paymentBefore.width);

        // Tap Clear: filters reset and it goes away again.
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('Clear'), findsNothing);
      },
    );

    testWidgets('Choosing a status tints the dropdown and offers Clear', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ready').last);
      await tester.pumpAndSettle();

      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('ORD-102'), findsOneWidget);
      expect(find.text('ORD-101'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Work status'), findsOneWidget);
      expect(find.text('ORD-101'), findsOneWidget);
    });

    testWidgets(
      'Sales summary uses the shared period filter with an inline From / To row',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        final filter = find.byKey(const ValueKey('orders-period-filter'));
        expect(filter, findsOneWidget);
        // Same chips as the dashboard cards (7 days, this month, last month).
        for (final label in [
          '7 days',
          PeriodRange.currentMonthLabel(),
          PeriodRange.previousMonthLabel(),
        ]) {
          expect(
            find.descendant(of: filter, matching: find.text(label)),
            findsOneWidget,
          );
        }

        // A preset that still covers today's orders keeps them.
        await tester.tap(
          find.descendant(of: filter, matching: find.text('7 days')),
        );
        await tester.pumpAndSettle();
        expect(find.text('ORD-101'), findsOneWidget);
        // Changing the period is a filter: Clear is offered.
        expect(find.text('Clear'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: filter,
            matching: find.byIcon(Icons.calendar_today_outlined),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('FROM'), findsOneWidget);
        expect(find.text('TO'), findsOneWidget);
      },
    );

    testWidgets(
      "Shows Can't load orders instead of No orders yet when cache is empty and sync is offline or failed",
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => SyncManager.instance.completeSync());

        mockOrdersRepo.cachedOrders = [];
        SyncManager.instance.setOffline(0);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        expect(find.text("Can't load orders"), findsOneWidget);
        expect(
          find.text(
            "You're offline or the server can't be reached. Pull down to try again.",
          ),
          findsOneWidget,
        );
        expect(find.text('No orders yet'), findsNothing);
      },
    );

    group('Quick views, summary card and narrow screens', () {
      void setView(WidgetTester tester, Size size, {double textScale = 1}) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }

      Order delivered(String id, String? completed, {String? date}) => Order(
        id: id,
        name: 'Cust $id',
        phone: '9000000009',
        date: date ?? todayStr,
        due: date ?? todayStr,
        status: 'Delivered',
        completed: completed,
        lines: [],
        payments: [],
      );

      testWidgets(
        'Delivered today accepts a full timestamp and rejects null/garbage',
        (tester) async {
          setView(tester, const Size(800, 1600));
          final noon = DateTime(
            now.year,
            now.month,
            now.day,
            12,
          ).toIso8601String();
          mockOrdersRepo.cachedOrders = [
            delivered('ORD-A', noon),
            delivered('ORD-B', todayStr),
            delivered('ORD-C', null),
            delivered('ORD-D', 'not-a-date'),
            delivered('ORD-E', yesterdayStr),
          ];
          final request = ValueNotifier<OrdersDrillDown?>(null);
          await tester.pumpWidget(createScreen(drillDown: request));
          await tester.pumpAndSettle();
          request.value = OrdersDrillDown.deliveredToday;
          await tester.pumpAndSettle();

          expect(find.text('ORD-A'), findsOneWidget);
          expect(find.text('ORD-B'), findsOneWidget);
          expect(find.text('ORD-C'), findsNothing);
          expect(find.text('ORD-D'), findsNothing);
          expect(find.text('ORD-E'), findsNothing);
        },
      );

      testWidgets('orders with unparseable dates are not due today or late', (
        tester,
      ) async {
        setView(tester, const Size(800, 1600));
        mockOrdersRepo.cachedOrders = [
          ...fakeOrders,
          Order(
            id: 'ORD-BAD',
            name: 'Bad Dates',
            phone: '9000000008',
            date: 'garbage',
            due: '',
            status: 'Pending',
            lines: [],
            payments: [],
          ),
        ];
        final request = ValueNotifier<OrdersDrillDown?>(null);
        await tester.pumpWidget(createScreen(drillDown: request));
        await tester.pumpAndSettle();
        // Default period view: no valid created date, so it is not counted.
        expect(find.text('ORD-BAD'), findsNothing);

        request.value = OrdersDrillDown.dueToday;
        await tester.pumpAndSettle();
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-BAD'), findsNothing);

        await tester.tap(find.text('Late'));
        await tester.pumpAndSettle();
        expect(find.text('ORD-BAD'), findsNothing);
      });

      testWidgets(
        'a quick view dims the period filter and names itself in the summary',
        (tester) async {
          setView(tester, const Size(800, 1600));
          await tester.pumpWidget(createScreen());
          await tester.pumpAndSettle();

          final subtitle = find.byKey(
            const ValueKey('orders-summary-subtitle'),
          );
          expect(subtitle, findsNothing);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(subtitle).data,
            'Open orders · ignores the date range',
          );
          final filter = find.byKey(const ValueKey('orders-period-filter'));
          final ignore = find.ancestor(
            of: filter,
            matching: find.byType(IgnorePointer),
          );
          expect(tester.widget<IgnorePointer>(ignore.first).ignoring, isTrue);

          // Another narrowing filter is flagged too.
          await tester.tap(find.text('Work status'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ready').last);
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(subtitle).data,
            'Open orders · ignores the date range · filtered',
          );

          // Back to Selected dates: filter live again, only "Filtered" left.
          await tester.tap(find.text('Selected dates').first);
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(subtitle).data, 'Filtered');
          expect(tester.widget<IgnorePointer>(ignore.first).ignoring, isFalse);
        },
      );

      for (final dark in [false, true]) {
        testWidgets(
          '320x568 at 1.5x text (${dark ? 'dark' : 'light'}): no overflow, '
          'Clear on its own line when active',
          (tester) async {
            setView(tester, const Size(320, 568), textScale: 1.5);
            await tester.pumpWidget(
              createScreen(theme: dark ? ThemeData.dark() : ThemeData.light()),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            // Shortened labels keep the dropdowns readable at this width.
            expect(find.text('Work'), findsOneWidget);
            expect(find.text('Payment'), findsOneWidget);
            expect(find.text('Clear'), findsNothing);

            await tester.ensureVisible(find.text('Work'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Work'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Ready').last);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final clear = find.text('Clear');
            expect(clear, findsOneWidget);
            expect(
              tester.getRect(clear).top,
              greaterThan(
                tester
                    .getRect(find.byKey(const ValueKey('work-status-filter')))
                    .bottom,
              ),
            );
          },
        );
      }

      testWidgets(
        'search clear button has a tooltip and a full-height target',
        (tester) async {
          setView(tester, const Size(800, 1600));
          await tester.pumpWidget(createScreen());
          await tester.pumpAndSettle();
          expect(find.byTooltip('New order'), findsOneWidget);
          await tester.enterText(find.byType(TextField), 'ali');
          await tester.pumpAndSettle();
          final clear = find.ancestor(
            of: find.byIcon(Icons.close),
            matching: find.byType(IconButton),
          );
          expect(find.byTooltip('Clear search'), findsOneWidget);
          expect(clear, findsOneWidget);
          // The search box is 44px including its 1px border, so 42px inside.
          expect(tester.getSize(clear).width, greaterThanOrEqualTo(42));
          expect(tester.getSize(clear).height, greaterThanOrEqualTo(42));
        },
      );
    });

    test('LoadOrderDetailEvent emits cached order AND stale-cache warning when network refresh fails', () async {
      final cache = FakeLocalCache()
        ..cachedOrdersJson = [fakeOrders.first.toJson()];
      final repo = OrdersRepository(
        apiClient: FailingApiClient(),
        localCache: cache,
      );
      final bloc = OrdersBloc(ordersRepository: repo);
      addTearDown(bloc.close);

      bloc.add(LoadOrderDetailEvent('ORD-101'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.selectedOrder?.id, 'ORD-101');
      expect(bloc.state.error, 'Could not refresh — showing the saved copy');
    });
  });
}
