import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/dialogs/status_dialog.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';

class MockOrdersRepository implements OrdersRepository {
  String? updatedOrderCode;
  String? updatedNextStatus;

  @override
  Future<Order> updateStatus(String orderCode, String status) async {
    updatedOrderCode = orderCode;
    updatedNextStatus = status;
    return Order(
      id: orderCode,
      name: 'Vikram Shetty',
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
    return InvoiceInfo(exists: true, invoiceSeq: 123);
  }

  @override
  Future<Order> getOrderDetail(
    String orderCode, {
    bool fallbackToCache = true,
  }) async {
    return Order(
      id: orderCode,
      name: 'Vikram Shetty',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: updatedNextStatus ?? 'Pending',
      lines: [],
      payments: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StatusDialog (Screen 9d) Tests', () {
    late MockOrdersRepository mockRepo;
    late OrdersBloc ordersBloc;

    final testOrder = Order(
      id: 'EL-248',
      name: 'Vikram Shetty',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Pending',
      lines: [
        OrderLine(
          productId: 'p1',
          name: 'Wash & Fold',
          quantity: 2,
          unit: 'kg',
          amount: 30000,
        ),
      ],
      payments: [], // balanceDue = 30000 (₹300)
    );

    setUp(() {
      mockRepo = MockOrdersRepository();
      ordersBloc = OrdersBloc(ordersRepository: mockRepo);
    });

    tearDown(() {
      ordersBloc.close();
    });

    Widget createTestDialog({Order? order}) {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: ordersBloc,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  StatusDialog.show(context, order: order ?? testOrder);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Renders Cancel and Update buttons, includes Delivered option, and updates standard status',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Check header and customer info
        expect(find.text('Update status'), findsOneWidget);
        expect(find.text('EL-248 · Vikram Shetty'), findsOneWidget);

        // Check status options exist including Delivered
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Ready'), findsOneWidget);
        expect(find.text('Delivered'), findsOneWidget);

        // Warning banner is NOT rendered for initial Pending status
        expect(
          find.text(
            'An outstanding balance remains. Marking delivered will ask for confirmation.',
          ),
          findsNothing,
        );

        // Verify Cancel and Update buttons are present
        expect(find.widgetWithText(SecondaryButton, 'Cancel'), findsOneWidget);
        expect(find.widgetWithText(PrimaryButton, 'Update'), findsOneWidget);

        // "Update" button should initially be disabled because "Pending" is current status
        final updateBtnBefore = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Update'),
        );
        expect(updateBtnBefore.onPressed, isNull);

        // Select "Ready"
        await tester.tap(find.text('Ready'));
        await tester.pumpAndSettle();

        // "Update" button should now be enabled
        final updateBtnAfter = tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Update'),
        );
        expect(updateBtnAfter.onPressed, isNotNull);

        // Tap "Update"
        await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
        await tester.pumpAndSettle();

        // Dialog is dismissed and updateStatus was called
        expect(mockRepo.updatedOrderCode, 'EL-248');
        expect(mockRepo.updatedNextStatus, 'Ready');
      },
    );

    testWidgets(
      'Selecting Delivered with balanceDue > 0 shows warning banner, confirms via CentredDialog, and dispatches Handover on confirm',
      (tester) async {
        await tester.pumpWidget(createTestDialog(order: testOrder));

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Select "Delivered"
        await tester.tap(find.text('Delivered'));
        await tester.pumpAndSettle();

        // Warning notice banner is now visible
        expect(
          find.text(
            'An outstanding balance remains. Marking delivered will ask for confirmation.',
          ),
          findsOneWidget,
        );

        // Tap "Update"
        await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
        await tester.pumpAndSettle();

        // Confirmation dialog is shown
        expect(find.byType(CentredDialog), findsOneWidget);
        expect(find.text('Deliver with balance due?'), findsOneWidget);
        final expectedSubtitle =
            '${testOrder.displayCode} still has ${CurrencyFormatter.format(testOrder.balanceDue)} due. Mark it delivered anyway?';
        expect(find.text(expectedSubtitle), findsOneWidget);
        final dialogCancelFinder = find.descendant(
          of: find.byType(CentredDialog),
          matching: find.widgetWithText(SecondaryButton, 'Cancel'),
        );
        expect(dialogCancelFinder, findsOneWidget);
        expect(
          find.widgetWithText(PrimaryButton, 'Deliver anyway'),
          findsOneWidget,
        );

        // Cancel confirmation
        await tester.tap(dialogCancelFinder);
        await tester.pumpAndSettle();

        // Confirmation dismissed, status dialog is still open, Handover was NOT dispatched
        expect(find.byType(CentredDialog), findsNothing);
        expect(find.byType(StatusDialog), findsOneWidget);
        expect(mockRepo.updatedNextStatus, isNull);

        // Tap "Update" again
        await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
        await tester.pumpAndSettle();

        // Confirm delivery anyway
        await tester.tap(find.widgetWithText(PrimaryButton, 'Deliver anyway'));
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        // Handover dispatched -> status updated to Delivered
        expect(mockRepo.updatedOrderCode, 'EL-248');
        expect(mockRepo.updatedNextStatus, 'Delivered');
      },
    );

    testWidgets(
      'Selecting Delivered with balanceDue == 0 dispatches HandoverOrderEvent directly without confirmation dialog',
      (tester) async {
        final paidOrder = Order(
          id: 'EL-248',
          name: 'Vikram Shetty',
          phone: '9876543210',
          date: '2026-09-10',
          due: '2026-09-12',
          status: 'Ready',
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Wash & Fold',
              quantity: 2,
              unit: 'kg',
              amount: 30000,
            ),
          ],
          payments: [
            OrderPayment(
              id: 'pay_1',
              amount: 30000,
              date: '2026-09-10',
              method: 'Cash',
            ),
          ], // balanceDue = 0
        );

        await tester.pumpWidget(createTestDialog(order: paidOrder));

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Select "Delivered"
        await tester.tap(find.text('Delivered'));
        await tester.pumpAndSettle();

        // Warning banner is NOT shown since balanceDue == 0
        expect(
          find.text(
            'An outstanding balance remains. Marking delivered will ask for confirmation.',
          ),
          findsNothing,
        );

        // Tap "Update"
        await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
        await tester.runAsync(() async {
          await ordersBloc.stream.firstWhere(
            (s) => s.actionSuccessMessage != null,
          );
        });
        await tester.pumpAndSettle();

        // No confirmation dialog was shown
        expect(find.byType(CentredDialog), findsNothing);

        // Directly dispatches HandoverOrderEvent -> Delivered
        expect(mockRepo.updatedOrderCode, 'EL-248');
        expect(mockRepo.updatedNextStatus, 'Delivered');
      },
    );

    testWidgets('Cancel button dismisses dialog without updating', (
      tester,
    ) async {
      await tester.pumpWidget(createTestDialog());

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update status'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.widgetWithText(SecondaryButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dialog is closed
      expect(find.text('Update status'), findsNothing);
      expect(mockRepo.updatedOrderCode, isNull);
    });
  });
}
