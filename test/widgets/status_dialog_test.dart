import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/dialogs/status_dialog.dart';
import 'package:myshop/shared/widgets/app_button.dart';

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

    Widget createTestDialog() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: ordersBloc,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  StatusDialog.show(context, order: testOrder);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Renders Cancel and Update buttons, never shows Collect button',
      (tester) async {
        await tester.pumpWidget(createTestDialog());

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Check header and customer info
        expect(find.text('Update status'), findsOneWidget);
        expect(find.text('EL-248 · Vikram Shetty'), findsOneWidget);

        // Check status options exist
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Ready'), findsOneWidget);

        // Check warning notice banner is rendered
        expect(
          find.text(
            'Delivered is not set here — collecting the payment marks the order delivered.',
          ),
          findsOneWidget,
        );

        // Verify Cancel and Update buttons are present
        expect(find.widgetWithText(SecondaryButton, 'Cancel'), findsOneWidget);
        expect(find.widgetWithText(PrimaryButton, 'Update'), findsOneWidget);

        // Verify "Collect ₹..." is NOT shown in this dialog
        expect(find.textContaining('Collect'), findsNothing);

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
