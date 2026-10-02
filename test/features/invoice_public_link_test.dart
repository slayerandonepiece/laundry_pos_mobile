import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/invoice_actions_sheet.dart';

// 43 base64url characters, the shape the backend issues and accepts.
final _token = 'A' * 43;

Order _order({
  String status = 'Delivered',
  int paid = 500,
  InvoiceInfo? invoice,
}) => Order(
  id: 'EL-7',
  name: 'Asha',
  phone: '9000000001',
  date: '2026-10-01',
  due: '2026-10-02',
  status: status,
  lines: [
    OrderLine(
      productId: 'p1',
      name: 'Shirt',
      quantity: 1,
      unit: 'PIECE',
      amount: 500,
    ),
  ],
  payments: paid > 0
      ? [
          OrderPayment(
            id: 'pay1',
            amount: paid,
            date: '2026-10-01',
            method: 'Cash',
          ),
        ]
      : [],
  invoice: invoice,
);

InvoiceInfo _invoice({bool exists = true, String? token}) =>
    InvoiceInfo(exists: exists, invoiceSeq: 7, accessToken: token ?? _token);

void main() {
  group('publicInvoiceUrl', () {
    test('final invoice links to the public view page on the API host', () {
      expect(
        InvoiceActionsSheet.publicInvoiceUrl(_order(invoice: _invoice())),
        '${ApiEndpoints.baseUrl}/i/$_token/view',
      );
    });

    test(
      'the invoice cached from the /invoice route (no exists field) links',
      () {
        // Real shape of GET /orders/{code}/invoice: token and seq, no `exists`.
        final invoice = InvoiceInfo.fromJson({
          'invoiceSeq': 7,
          'accessToken': _token,
          'generatedAt': '2026-10-01T10:00:00.000Z',
        });
        expect(invoice.exists, isFalse);

        expect(
          InvoiceActionsSheet.publicInvoiceUrl(_order(invoice: invoice)),
          '${ApiEndpoints.baseUrl}/i/$_token/view',
        );
      },
    );

    test('no link until the order is delivered', () {
      expect(
        InvoiceActionsSheet.publicInvoiceUrl(
          _order(status: 'Ready', invoice: _invoice()),
        ),
        isNull,
      );
    });

    test('no link while a balance is due', () {
      expect(
        InvoiceActionsSheet.publicInvoiceUrl(
          _order(paid: 200, invoice: _invoice()),
        ),
        isNull,
      );
    });

    test('no link without an issued invoice or with a malformed token', () {
      expect(InvoiceActionsSheet.publicInvoiceUrl(_order()), isNull);
      expect(
        InvoiceActionsSheet.publicInvoiceUrl(
          _order(invoice: InvoiceInfo(exists: true, invoiceSeq: 7)),
        ),
        isNull,
      );
      expect(
        InvoiceActionsSheet.publicInvoiceUrl(
          _order(invoice: _invoice(token: 'short')),
        ),
        isNull,
      );
    });
  });

  group('Open in browser row', () {
    Future<void> pump(WidgetTester tester, Order order) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InvoiceActionsSheet(order: order)),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows for a final invoice', (tester) async {
      await pump(tester, _order(invoice: _invoice()));
      expect(find.text('Open in browser'), findsOneWidget);
    });

    testWidgets('is hidden when the invoice is not final', (tester) async {
      await pump(tester, _order(status: 'Ready', invoice: _invoice()));
      expect(find.text('Open in browser'), findsNothing);
      expect(find.text('Print'), findsOneWidget);
    });
  });
}
