import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/dialogs/collect_payment_dialog.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class MockCollectOrdersRepository implements OrdersRepository {
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
  Future<InvoiceInfo> getOrCreateInvoice(String orderCode) async {
    return InvoiceInfo(exists: true, invoiceSeq: 101);
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

class FakeDialogPosRepository implements PosRepository {
  List<StorePaymentMethod> methods;
  int listCalls = 0;

  // Null = never synced, so the dialog fetches.
  List<StorePaymentMethod>? cachedMethods;

  FakeDialogPosRepository(this.methods);

  @override
  List<StorePaymentMethod>? getCachedPaymentMethodsList() => cachedMethods;

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    listCalls++;
    return methods;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CollectPaymentDialog Tests', () {
    late MockCollectOrdersRepository mockRepo;
    late OrdersBloc ordersBloc;
    late FakeDialogPosRepository fakePosRepo;

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
      fakePosRepo = FakeDialogPosRepository([
        StorePaymentMethod(id: 'pm_cash', name: 'Cash', type: 'Cash', active: true),
        StorePaymentMethod(id: 'pm_upi', name: 'Upi', type: 'UPI', active: true),
      ]);
    });

    tearDown(() {
      ordersBloc.close();
    });

    Widget createTestDialog({Order? order}) {
      return RepositoryProvider<PosRepository>.value(
        value: fakePosRepo,
        child: MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: ordersBloc,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    CollectPaymentDialog.show(
                      context,
                      order: order ?? testOrder,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Renders methods from PosRepository, nothing pre-selected, button disabled until tap, submits tapped name verbatim',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Collect payment & deliver'), findsOneWidget);
        expect(find.text('EL-350 · Ramesh Patel'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Upi'), findsOneWidget);

        // Nothing pre-selected: no check icon inside option circles, button disabled
        expect(find.byIcon(Icons.check), findsNothing);
        var submitBtn = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Collect & deliver'),
        );
        expect(submitBtn.onPressed, isNull);

        // Select 'Upi' (exact case from server)
        await tester.tap(find.text('Upi'));
        await tester.pumpAndSettle();

        submitBtn = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Collect & deliver'),
        );
        expect(submitBtn.onPressed, isNotNull);

        // Tap Collect & deliver
        await tester.tap(find.widgetWithText(PrimaryButton, 'Collect & deliver'));
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        expect(mockRepo.recordedOrderCode, 'EL-350');
        expect(mockRepo.recordedAmount, 35000);
        expect(mockRepo.recordedMethod, 'Upi');

        // Dialog dismissed
        expect(find.text('Collect payment & deliver'), findsNothing);
      },
    );

    testWidgets('Uses cached payment methods without the network', (
      tester,
    ) async {
      fakePosRepo.cachedMethods = [
        StorePaymentMethod.fromJson({'id': 'pm_c', 'name': 'Card', 'enabled': true}),
      ];
      await tester.pumpWidget(createTestDialog());

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      expect(fakePosRepo.listCalls, 0);
    });

    testWidgets(
      'Empty payment methods list shows warning copy and disables Collect & deliver button',
      (tester) async {
        fakePosRepo.methods = [];
        await tester.pumpWidget(createTestDialog());

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'No payment methods are enabled. Ask the owner to enable one in Profile → Payment methods.',
          ),
          findsOneWidget,
        );
        final submitBtn = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Collect & deliver'),
        );
        expect(submitBtn.onPressed, isNull);
      },
    );

    testWidgets(
      'Already-paid order (balanceDue == 0) delivers without requiring a payment method',
      (tester) async {
        fakePosRepo.methods = [];
        final paidOrder = Order(
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
              id: 'pay_upfront',
              amount: 35000,
              date: '2026-09-10',
              method: 'Cash',
            ),
          ],
        );

        await tester.pumpWidget(createTestDialog(order: paidOrder));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('ALREADY PAID'), findsOneWidget);
        final deliverBtn = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Deliver order'),
        );
        expect(deliverBtn.onPressed, isNotNull);
        // Nothing to collect, so no payment-method fetch.
        expect(fakePosRepo.listCalls, 0);
      },
    );

    testWidgets(
      'Does not overflow on narrow mobile screens (360x800 and 402x874)',
      (tester) async {
        // Test on standard iPhone 17 Pro width (402)
        tester.view.physicalSize = const Size(402 * 3, 874 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestDialog());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Collect & deliver'), findsOneWidget);

        // Also test on even narrower screen (360dp width)
        tester.view.physicalSize = const Size(360 * 3, 800 * 3);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Collect & deliver'), findsOneWidget);
      },
    );
  });
}
