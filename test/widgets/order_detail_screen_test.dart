import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/order_detail_screen.dart';
import 'package:myshop/features/orders/presentation/orders_list_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class MockOrdersRepository implements OrdersRepository {
  List<Order> cachedOrders = [];

  @override
  List<Order> getCachedOrdersList({String? outletId, bool? allOutlets}) =>
      cachedOrders;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPosRepository implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalCache extends LocalCacheService {
  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'EMPLOYEE'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => [
    {
      'id': 'outlet-1',
      'outletCode': 'O01',
      'displayName': 'Main Outlet',
      'isDefault': true,
      'status': 'ACTIVE',
    },
  ];
  @override
  String? getActiveOutletId() => 'outlet-1';
  @override
  Future<void> setActiveOutletId(String outletId) async {}
  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {}
  @override
  bool isAllOutletsScope() => false;
  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
  @override
  List<Map<String, dynamic>>? getCachedOrders({
    String? outletId,
    bool? allOutlets,
  }) => [];
}

class FakeAuthBloc extends Cubit<AuthState> implements AuthBloc {
  FakeAuthBloc()
    : super(
        AuthenticatedState(
          user: User(id: 'u1', name: 'Tester', phone: '9876543210'),
          currentStore: StoreSummary(
            storeId: 's1',
            storeName: 'Test Laundry',
            role: 'EMPLOYEE',
          ),
          availableStores: [
            StoreSummary(
              storeId: 's1',
              storeName: 'Test Laundry',
              role: 'EMPLOYEE',
            ),
          ],
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockOrdersRepository mockOrdersRepo;
  late MockPosRepository mockPosRepo;
  late OrdersBloc ordersBloc;
  late FakeAuthBloc authBloc;

  setUp(() {
    mockOrdersRepo = MockOrdersRepository();
    mockPosRepo = MockPosRepository();
    ordersBloc = OrdersBloc(ordersRepository: mockOrdersRepo);
    authBloc = FakeAuthBloc();
  });

  tearDown(() {
    ordersBloc.close();
    authBloc.close();
  });

  Widget buildTestWidget(Widget child) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OrdersRepository>.value(value: mockOrdersRepo),
        RepositoryProvider<PosRepository>.value(value: mockPosRepo),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<OutletScopeCubit>(
            create: (_) =>
                OutletScopeCubit(localCache: FakeLocalCache())..hydrate(),
          ),
          BlocProvider<CartBloc>(
            create: (_) => CartBloc(posRepository: mockPosRepo),
          ),
        ],
        child: MaterialApp(home: child),
      ),
    );
  }

  group('OrderDetailScreen & OrdersListScreen B1 bug-fix parity tests', () {
    final deliveredWithBalanceOrder = Order(
      id: 'EL-201',
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Delivered',
      lines: [
        OrderLine(
          productId: 'p1',
          name: 'Dry Clean Suit',
          quantity: 1,
          unit: 'PIECE',
          amount: 50000,
        ),
      ],
      payments: [
        OrderPayment(
          id: 'pay-1',
          amount: 20000,
          date: '2026-09-10',
          method: 'Cash',
        ),
      ], // balanceDue = 30000 paise = ₹300
    );

    final deliveredAndPaidOrder = Order(
      id: 'EL-202',
      name: 'Priya Sharma',
      phone: '9123456789',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Delivered',
      lines: [
        OrderLine(
          productId: 'p2',
          name: 'Wash & Fold',
          quantity: 2,
          unit: 'KG',
          amount: 20000,
        ),
      ],
      payments: [
        OrderPayment(
          id: 'pay-2',
          amount: 20000,
          date: '2026-09-10',
          method: 'UPI',
        ),
      ], // balanceDue = 0, isPaidInFull = true
      invoice: InvoiceInfo(
        exists: true,
        invoiceSeq: 202,
        accessToken: 'tok-abc',
        generatedAt: DateTime(2026, 9, 10),
      ),
    );

    testWidgets(
      'Delivered order with balance due shows "Record payment" and warning, hides invoice card',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            OrderDetailScreen(initialOrder: deliveredWithBalanceOrder),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Shows "Record payment" PrimaryButton
        expect(
          find.widgetWithText(PrimaryButton, 'Record payment'),
          findsOneWidget,
        );

        // 2. Shows warning inset with balance due
        expect(
          find.text('₹300 still due on this delivered order'),
          findsOneWidget,
        );

        // 3. Invoice card is hidden because order is not paid in full
        expect(find.text('INVOICE'), findsNothing);
      },
    );

    testWidgets(
      'Status stepper keeps every stage aligned even when one label wraps',
      (tester) async {
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildTestWidget(
            OrderDetailScreen(initialOrder: deliveredWithBalanceOrder),
          ),
        );
        await tester.pumpAndSettle();

        final labels = ['Pending', 'In Progress', 'Ready', 'Delivered'];
        final tops = <double>{};
        for (final l in labels) {
          final f = find.text(l).first;
          // Even if a label wraps (the test font is far wider than the real
          // one), every stage must start at the same height.
          tops.add(tester.getTopLeft(f).dy);
        }
        expect(tops.length, 1, reason: 'labels share a baseline');
      },
    );

    testWidgets(
      'Delivered and paid order shows invoice card and no payment button',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            OrderDetailScreen(initialOrder: deliveredAndPaidOrder),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Invoice card is visible
        expect(find.text('INVOICE'), findsOneWidget);
        expect(find.text('INV-000202'), findsOneWidget);

        // 2. "Record payment" button is not shown
        expect(
          find.widgetWithText(PrimaryButton, 'Record payment'),
          findsNothing,
        );
        expect(
          find.textContaining('still due on this delivered order'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Orders list card for delivered order with balance shows Collect button',
      (tester) async {
        mockOrdersRepo.cachedOrders = [deliveredWithBalanceOrder];
        ordersBloc.emit(
          ordersBloc.state.copyWith(allOrders: [deliveredWithBalanceOrder]),
        );

        await tester.pumpWidget(buildTestWidget(const OrdersListScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Collect ₹300'), findsOneWidget);
      },
    );
  });
}
