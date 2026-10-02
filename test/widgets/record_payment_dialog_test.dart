import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/dialogs/record_payment_dialog.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class MockRecordPaymentOrdersRepository implements OrdersRepository {
  String? recordedOrderCode;
  int? recordedAmount;
  String? recordedMethod;
  String? updatedStatusOrderCode;
  String? updatedStatus;

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
      status: 'Ready', // Does NOT change status to Delivered
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
    updatedStatusOrderCode = orderCode;
    updatedStatus = status;
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
  Future<Order> getOrderDetail(
    String orderCode, {
    bool fallbackToCache = true,
  }) async {
    return Order(
      id: orderCode,
      name: 'Ramesh Patel',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Ready',
      lines: [],
      payments: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRecordPosRepository implements PosRepository {
  List<StorePaymentMethod> methods;
  List<StorePaymentMethod>? cachedMethods;

  FakeRecordPosRepository(this.methods);

  @override
  List<StorePaymentMethod>? getCachedPaymentMethodsList() => cachedMethods;

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async => methods;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RecordPaymentDialog Tests', () {
    late MockRecordPaymentOrdersRepository mockRepo;
    late OrdersBloc ordersBloc;
    late FakeRecordPosRepository fakePosRepo;

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
          amount: 35000, // ₹350 balanceDue
        ),
      ],
      payments: [], // balanceDue = 35000 (₹350)
    );

    setUp(() {
      mockRepo = MockRecordPaymentOrdersRepository();
      ordersBloc = OrdersBloc(ordersRepository: mockRepo);
      fakePosRepo = FakeRecordPosRepository([
        StorePaymentMethod(
          id: 'pm_cash',
          name: 'Cash',
          type: 'Cash',
          active: true,
        ),
        StorePaymentMethod(
          id: 'pm_upi',
          name: 'Upi',
          type: 'UPI',
          active: true,
        ),
        StorePaymentMethod(
          id: 'pm_cod',
          name: 'Cash On Delivery',
          code: 'COD',
          active: true,
        ),
      ]);
    });

    tearDown(() {
      ordersBloc.close();
    });

    Widget createTestDialog({Order? order}) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<PosRepository>.value(
            value: fakePosRepo,
            child: BlocProvider<OrdersBloc>.value(
              value: ordersBloc,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    RecordPaymentDialog.show(
                      context,
                      order: order ?? testOrder,
                    );
                  },
                  child: const Text('Open Record Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Shows the full balance with no amount field; choosing a method records it',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open Record Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(RecordPaymentDialog), findsOneWidget);
        expect(find.text('EL-350 · Ramesh Patel'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Pay balance'), findsNothing);
        // Pay-on-delivery is not money received, so it is not offered here.
        expect(find.text('Cash On Delivery'), findsNothing);
        expect(find.text('₹350'), findsWidgets);

        // Nothing can be submitted until a method is chosen.
        final submitFinder = find.widgetWithText(PrimaryButton, 'Record ₹350');
        expect(submitFinder, findsOneWidget);
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNull);

        await tester.tap(find.text('Upi'));
        await tester.pumpAndSettle();
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNotNull);

        await tester.tap(submitFinder);
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        // The whole balance (35000 paise) goes out with the chosen method.
        expect(mockRepo.recordedOrderCode, 'EL-350');
        expect(mockRepo.recordedAmount, 35000);
        expect(mockRepo.recordedMethod, 'Upi');
        // Order status is NOT changed
        expect(mockRepo.updatedStatus, isNull);
        expect(mockRepo.updatedStatusOrderCode, isNull);

        // Sheet closed
        expect(find.byType(RecordPaymentDialog), findsNothing);
      },
    );

    testWidgets('After a part payment, only that same method is offered', (
      tester,
    ) async {
      final partPaid = Order(
        id: 'EL-351',
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
            amount: 35000,
          ),
        ],
        payments: [
          OrderPayment(
            id: 'pay_0',
            amount: 10000,
            date: '2026-09-10',
            method: 'Upi',
          ),
        ],
      );
      await tester.pumpWidget(createTestDialog(order: partPaid));
      await tester.tap(find.text('Open Record Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Upi'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      final submit = find.widgetWithText(PrimaryButton, 'Record ₹250');
      expect(tester.widget<PrimaryButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.runAsync(() async {
        await ordersBloc.stream.firstWhere(
          (s) => s.actionSuccessMessage != null,
        );
      });
      await tester.pumpAndSettle();
      expect(mockRepo.recordedAmount, 25000);
      expect(mockRepo.recordedMethod, 'Upi');
    });
  });
}
