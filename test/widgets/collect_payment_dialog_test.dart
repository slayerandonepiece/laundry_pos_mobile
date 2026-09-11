import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/dialogs/collect_payment_dialog.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class MockCollectOrdersRepository implements OrdersRepository {
  String? recordedOrderCode;
  int? recordedAmount;
  String? recordedMethod;

  @override
  Future<Order> recordPayment(
    String orderCode,
    int amount,
    String method,
  ) async {
    recordedOrderCode = orderCode;
    recordedAmount = amount;
    recordedMethod = method;
    return Order(
      id: orderCode,
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Delivered',
      lines: [],
      payments: [
        OrderPayment(
          id: 'pay_1',
          amount: amount,
          date: '2026-09-10',
          method: method,
        ),
      ],
    );
  }

  @override
  Future<Order> updateStatus(String orderCode, String status) async {
    return Order(
      id: orderCode,
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: status,
      lines: [],
      payments: [],
    );
  }

  @override
  Future<InvoiceInfo> getOrCreateInvoice(String orderCode) async {
    return InvoiceInfo(exists: true, invoiceSeq: 101);
  }

  @override
  Future<Order> getOrderDetail(String orderCode) async {
    return Order(
      id: orderCode,
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Delivered',
      lines: [],
      payments: [
        OrderPayment(
          id: 'pay_1',
          amount: recordedAmount ?? 35000,
          date: '2026-09-10',
          method: recordedMethod ?? 'Cash',
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CollectPaymentDialog Tests', () {
    late MockCollectOrdersRepository mockRepo;
    late OrdersBloc ordersBloc;

    final testOrder = Order(
      id: 'EL-350',
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Ready',
      lines: [
        OrderLine(
          productId: 'p1',
          name: 'Suit Dry Clean',
          quantity: 1,
          unit: 'pcs',
          amount: 35000, // ₹350
        ),
      ],
      payments: [], // balanceDue = 35000
    );

    setUp(() {
      mockRepo = MockCollectOrdersRepository();
      ordersBloc = OrdersBloc(ordersRepository: mockRepo);
    });

    tearDown(() {
      ordersBloc.close();
    });

    Widget createTestDialog() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: ordersBloc,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  CollectPaymentDialog.show(context, order: testOrder);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Renders amount due, switches between Cash and UPI, and records payment',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Collect payment'), findsOneWidget);
        expect(find.text('EL-350 · Ramesh Patel'), findsOneWidget);
        expect(find.text('₹350'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('UPI'), findsOneWidget);

        // Select UPI
        await tester.tap(find.text('UPI'));
        await tester.pumpAndSettle();

        // Tap Done
        await tester.tap(find.widgetWithText(PrimaryButton, 'Done'));
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        expect(mockRepo.recordedOrderCode, 'EL-350');
        expect(mockRepo.recordedAmount, 35000);
        expect(mockRepo.recordedMethod, 'UPI');

        // Dialog dismissed
        expect(find.text('Collect payment'), findsNothing);
      },
    );
  });
}
