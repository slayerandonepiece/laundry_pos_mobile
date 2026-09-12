import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/owner/presentation/owner_orders_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';

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
          date: yesterdayStr,
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

    Widget createScreen() {
      final ordersBloc = OrdersBloc(ordersRepository: mockOrdersRepo);
      final cartBloc = CartBloc(posRepository: mockPosRepo);
      final authBloc = MockAuthBloc();

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
          ],
          child: const MaterialApp(home: OwnerOrdersScreen()),
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

      // Today orders placed are ORD-101 (₹200, balance ₹50) and ORD-102 (₹300, balance ₹0).
      // Order value = ₹500, matching orders = 2
      // Collected = ₹450 (₹150 + ₹300)
      // To collect = ₹50 (₹50 + ₹0)
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('2 matching orders'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
      expect(find.text('₹50'), findsOneWidget);

      // Both orders are visible in the list
      expect(find.text('ORD-101'), findsOneWidget);
      expect(find.text('ORD-102'), findsOneWidget);
      expect(
        find.text('ORD-103'),
        findsNothing,
      ); // ORD-103 was placed yesterday
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

        // Default: 'Selected dates' is active
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-103'), findsNothing);

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
        expect(find.text('1 matching order'), findsOneWidget);
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
        expect(find.text('ORD-103'), findsNothing);
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
      expect(find.text('1 matching order'), findsOneWidget);

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
      'Tapping + button in app bar navigates to CustomerDetailsScreen',
      (tester) async {
        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        final addButton = find.byIcon(Icons.add);
        expect(addButton, findsOneWidget);

        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(find.byType(CustomerDetailsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Work status and payment status dropdown filters work as expected',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createScreen());
        await tester.pumpAndSettle();

        // Initially ORD-101 (Pending, Partial) and ORD-102 (Ready, Paid) are visible
        expect(find.text('ORD-101'), findsOneWidget);
        expect(find.text('ORD-102'), findsOneWidget);

        // Filter by payment status: Paid
        await tester.tap(find.text('All payment statuses'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid').last);
        await tester.pumpAndSettle();

        // Only ORD-102 is paid
        expect(find.text('ORD-102'), findsOneWidget);
        expect(find.text('ORD-101'), findsNothing);

        // Filter by work status: Ready
        await tester.tap(find.text('All work statuses'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ready').last);
        await tester.pumpAndSettle();

        expect(find.text('ORD-102'), findsOneWidget);
      },
    );
  });
}
