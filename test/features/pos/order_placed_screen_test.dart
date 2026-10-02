import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/pos/presentation/order_placed_screen.dart';

/// Swallows the screen's LoadOrdersEvent so no repository is needed.
class _NoopOrdersBloc extends Bloc<OrdersEvent, OrdersState>
    implements OrdersBloc {
  _NoopOrdersBloc() : super(OrdersState()) {
    on<LoadOrdersEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Order _order({required int paid}) => Order(
  id: '',
  name: '',
  phone: '9000000004',
  date: '2026-10-02',
  due: '2026-10-02',
  status: 'Pending',
  lines: [
    OrderLine(
      productId: 'p1',
      name: 'Shirt Press',
      quantity: 1,
      unit: 'PIECE',
      amount: 4000,
    ),
  ],
  payments: paid > 0
      ? [
          OrderPayment(
            id: 'pay_optimistic',
            amount: paid,
            date: '2026-10-02',
            method: 'Cash',
          ),
        ]
      : [],
  isSynced: false,
);

void main() {
  late _NoopOrdersBloc ordersBloc;

  setUp(() => ordersBloc = _NoopOrdersBloc());
  tearDown(() => ordersBloc.close());

  Future<void> show(WidgetTester tester, Order order) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      BlocProvider<OrdersBloc>.value(
        value: ordersBloc,
        child: MaterialApp(home: OrderPlacedScreen(order: order)),
      ),
    );
    await tester.pump();
  }

  testWidgets('a part payment shows what was received and the balance due', (
    tester,
  ) async {
    await show(tester, _order(paid: 1500));

    expect(find.text('Received ₹15 · Cash'), findsOneWidget);
    expect(find.text('Due: ₹25'), findsOneWidget);
    expect(find.text('Pay on delivery'), findsNothing);
  });

  testWidgets(
    'no payment still reads Pay on delivery with the full total due',
    (tester) async {
      await show(tester, _order(paid: 0));

      expect(find.text('Pay on delivery'), findsOneWidget);
      expect(find.text('Due: ₹40'), findsOneWidget);
    },
  );

  testWidgets('a full payment still reads Paid in full', (tester) async {
    await show(tester, _order(paid: 4000));

    expect(find.text('Paid in full · Cash'), findsOneWidget);
    expect(find.textContaining('Due:'), findsNothing);
  });
}
