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
      'Validates amount (rejects 0, rejects > balanceDue, accepts valid partial amount)',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open Record Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(RecordPaymentDialog), findsOneWidget);
        expect(find.text('EL-350 · Ramesh Patel'), findsOneWidget);

        // Submit button starts disabled (empty amount, no method)
        final submitFinder = find.widgetWithText(
          PrimaryButton,
          'Record payment',
        );
        expect(submitFinder, findsOneWidget);
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNull);

        // Select payment method
        await tester.tap(find.text('Cash'));
        await tester.pumpAndSettle();
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNull);

        // Enter 0 -> should show error and keep disabled
        await tester.enterText(find.byType(TextField), '0');
        await tester.pumpAndSettle();
        expect(find.text('Amount must be greater than zero'), findsOneWidget);
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNull);

        // Enter amount > balanceDue (35000 paise = 350 rupees)
        await tester.enterText(find.byType(TextField), '400');
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Amount cannot exceed balance'),
          findsOneWidget,
        );
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNull);

        // Enter valid partial amount (₹150)
        await tester.enterText(find.byType(TextField), '150');
        await tester.pumpAndSettle();
        expect(find.text('Amount must be greater than zero'), findsNothing);
        expect(
          find.textContaining('Amount cannot exceed balance'),
          findsNothing,
        );
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNotNull);

        // Submit
        await tester.tap(submitFinder);
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        // Verifies RecordPaymentEvent dispatched with right orderCode, amount (15000 paise), and method
        expect(mockRepo.recordedOrderCode, 'EL-350');
        expect(mockRepo.recordedAmount, 15000);
        expect(mockRepo.recordedMethod, 'Cash');
        // Verifies order status was NOT changed
        expect(mockRepo.updatedStatus, isNull);
        expect(mockRepo.updatedStatusOrderCode, isNull);

        // Dialog popped
        expect(find.byType(RecordPaymentDialog), findsNothing);
      },
    );

    testWidgets(
      'Pay balance quick-fill sets full balanceDue and dispatches without changing status',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open Record Dialog'));
        await tester.pumpAndSettle();

        // Tap "Pay balance"
        await tester.tap(find.text('Pay balance'));
        await tester.pumpAndSettle();

        // TextField should now contain "350"
        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, '350');

        // Select UPI
        await tester.tap(find.text('Upi'));
        await tester.pumpAndSettle();

        final submitFinder = find.widgetWithText(
          PrimaryButton,
          'Record payment',
        );
        expect(tester.widget<PrimaryButton>(submitFinder).onPressed, isNotNull);

        await tester.tap(submitFinder);
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        // Verifies full balance (35000 paise) dispatched with UPI
        expect(mockRepo.recordedOrderCode, 'EL-350');
        expect(mockRepo.recordedAmount, 35000);
        expect(mockRepo.recordedMethod, 'Upi');
        // Order status is NOT changed
        expect(mockRepo.updatedStatus, isNull);

        // Dialog popped
        expect(find.byType(RecordPaymentDialog), findsNothing);
      },
    );
  });
}
