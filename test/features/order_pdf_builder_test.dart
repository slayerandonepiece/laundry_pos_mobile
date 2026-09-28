import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/order_pdf_builder.dart';

String extractPdfText(Uint8List bytes) {
  final buffer = StringBuffer();
  final streamMarker = ascii.encode('stream');
  final endStreamMarker = ascii.encode('endstream');

  var searchStart = 0;
  while (true) {
    var streamIdx = -1;
    for (var i = searchStart; i <= bytes.length - streamMarker.length; i++) {
      var match = true;
      for (var j = 0; j < streamMarker.length; j++) {
        if (bytes[i + j] != streamMarker[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        streamIdx = i;
        break;
      }
    }
    if (streamIdx == -1) break;

    var contentStart = streamIdx + streamMarker.length;
    while (contentStart < bytes.length &&
        (bytes[contentStart] == 10 || bytes[contentStart] == 13)) {
      contentStart++;
    }

    var endStreamIdx = -1;
    for (
      var i = contentStart;
      i <= bytes.length - endStreamMarker.length;
      i++
    ) {
      var match = true;
      for (var j = 0; j < endStreamMarker.length; j++) {
        if (bytes[i + j] != endStreamMarker[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        endStreamIdx = i;
        break;
      }
    }
    if (endStreamIdx == -1) break;

    var contentEnd = endStreamIdx;
    while (contentEnd > contentStart &&
        (bytes[contentEnd - 1] == 10 || bytes[contentEnd - 1] == 13)) {
      contentEnd--;
    }

    final streamBytes = bytes.sublist(contentStart, contentEnd);
    try {
      final decompressed = zlib.decode(streamBytes);
      final decompressedText = utf8.decode(decompressed, allowMalformed: true);
      // Extract all strings in parentheses e.g. (Elite), (Laundromat)
      final words = RegExp(r'\(([^)]*)\)')
          .allMatches(decompressedText)
          .map((m) => m.group(1)!)
          .where((w) => w.isNotEmpty)
          .join(' ');
      buffer.write('$words\n');
    } catch (_) {
      // ignore
    }

    searchStart = endStreamIdx + endStreamMarker.length;
  }

  return buffer.toString();
}

void main() {
  group('InvoiceInfo generatedAt tests', () {
    test('parses generatedAt from json and issuedAt uses it', () {
      final json = {
        'exists': true,
        'invoiceSeq': 123,
        'accessToken': 'token123',
        'canGenerate': true,
        'generatedAt': '2026-09-28T10:30:00.000Z',
      };

      final info = InvoiceInfo.fromJson(json);
      expect(info.exists, isTrue);
      expect(info.invoiceSeq, 123);
      expect(info.formattedInvoiceNumber, 'INV-000123');
      expect(info.generatedAt, isNotNull);
      expect(info.issuedAt, info.generatedAt);

      final encoded = info.toJson();
      expect(encoded['generatedAt'], isNotNull);
    });

    test('issuedAt falls back to now when generatedAt is null', () {
      final info = InvoiceInfo(exists: false);
      expect(info.generatedAt, isNull);
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final issued = info.issuedAt;
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(issued.isAfter(before) && issued.isBefore(after), isTrue);
    });
  });

  group('buildOrderPdfBytes tests', () {
    test(
      'generates PDF with 2+ payments and both PIECE and WEIGHT lines',
      () async {
        final order = Order(
          id: 'ORD-101',
          name: 'Rahul Sharma',
          phone: '9876543210',
          date: '2026-09-20',
          due: '2026-09-25',
          status: 'Delivered',
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Dry Clean Suit',
              quantity: 2.0,
              unit: 'PIECE',
              amount: 50000, // Rs. 500 total, Rs. 250 each
            ),
            OrderLine(
              productId: 'p2',
              name: 'Wash & Fold Laundry',
              quantity: 3.5,
              unit: 'WEIGHT',
              amount: 35000, // Rs. 350
            ),
          ],
          payments: [
            OrderPayment(
              id: 'pay-1',
              amount: 50000,
              date: '2026-09-20',
              method: 'CASH',
            ),
            OrderPayment(
              id: 'pay-2',
              amount: 35000,
              date: '2026-09-25',
              method: 'UPI',
            ),
          ],
          invoice: InvoiceInfo(
            exists: true,
            invoiceSeq: 42,
            generatedAt: DateTime(2026, 9, 25, 14, 0),
          ),
        );

        final bytes = await buildOrderPdfBytes(
          order: order,
          storeName: 'Elite Laundromat',
          storeAddress: '123 MG Road, Bangalore',
          storePhone: '+91 99999 88888',
          isFinalInvoice: true,
        );

        expect(bytes, isNotEmpty);
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');

        final text = extractPdfText(bytes);
        expect(text, contains('Elite Laundromat'));
        expect(text, contains('Invoice: INV-000042'));
        expect(text, contains('Order: ORD-101'));

        // Verify Billed to & Order section
        expect(text, contains('BILLED TO'));
        expect(text, contains('Rahul Sharma'));
        expect(text, contains('9876543210'));
        expect(text, contains('ORDER'));
        expect(text, contains('Order number'));
        expect(text, contains('Order date'));
        expect(text, contains('20 Sep 2026'));
        expect(text, contains('Delivery date'));
        expect(text, contains('25 Sep 2026'));

        // Verify Items table and columns
        expect(text, contains('ITEMS'));
        expect(text, contains('Service'));
        expect(text, contains('Qty'));
        expect(text, contains('Rate'));
        expect(text, contains('Amount'));
        expect(text, contains('Dry Clean Suit'));
        expect(text, contains('2 pcs'));
        expect(text, contains('Rs. 250'));
        expect(text, contains('Wash & Fold Laundry'));
        expect(text, contains('3.5 kg'));
        expect(text, contains('Slab pricing'));

        // Verify Order total
        expect(text, contains('Order total'));
        expect(text, contains('Rs. 850'));

        // Verify Payment section
        expect(text, contains('PAYMENT'));
        expect(text, contains('Method'));
        expect(text, contains('Multiple')); // Cash + UPI
        expect(text, contains('Amount paid'));
        expect(text, contains('Balance due'));

        // Verify Payments received table (2 payments)
        expect(text, contains('PAYMENTS RECEIVED'));
        expect(text, contains('Cash'));
        expect(text, contains('UPI'));
        expect(text, contains('Rs. 500'));
        expect(text, contains('Rs. 350'));

        // Verify Footer
        expect(
          text,
          contains('Generated 25 Sep 2026 - this is not a tax invoice.'),
        );
      },
    );

    test(
      'generates pre-delivery bill when invoice is null and zero payments',
      () async {
        final order = Order(
          id: 'ORD-102',
          name: '',
          phone: '9876543210',
          date: '2026-09-28',
          due: '2026-09-30',
          status: 'Ready',
          lines: [
            OrderLine(
              productId: 'p1',
              name: 'Ironing Shirt',
              quantity: 5.0,
              unit: 'PIECE',
              amount: 10000,
            ),
          ],
          payments: [],
          invoice: null,
        );

        final bytes = await buildOrderPdfBytes(
          order: order,
          storeName: 'Elite Laundromat',
          storeAddress: '123 MG Road',
          storePhone: '9999988888',
          isFinalInvoice: false,
        );

        expect(bytes, isNotEmpty);
        final text = extractPdfText(bytes);

        // Pre-delivery bill header
        expect(text, contains('Bill for: ORD-102'));
        expect(text, contains('Walk-in customer'));

        // Method label for zero payments should be '-'
        expect(text, contains('PAYMENT'));
        expect(text, contains('Method'));

        // Payments received section should NOT be rendered when empty
        expect(text, isNot(contains('PAYMENTS RECEIVED')));

        // Footer should fall back gracefully to today's date
        expect(text, contains('this is not a tax invoice.'));
      },
    );

    test('shows single method name when exactly one distinct payment method is used', () async {
      final order = Order(
        id: 'ORD-103',
        name: 'Amit Patel',
        phone: '9123456780',
        date: '2026-09-27',
        due: '2026-09-29',
        status: 'In Progress',
        lines: [
          OrderLine(
            productId: 'p1',
            name: 'Blanket Wash',
            quantity: 1.0,
            unit: 'PIECE',
            amount: 20000,
          ),
        ],
        payments: [
          OrderPayment(
            id: 'pay-1',
            amount: 10000,
            date: '2026-09-27',
            method: 'CASH',
          ),
          OrderPayment(
            id: 'pay-2',
            amount: 10000,
            date: '2026-09-28',
            method: 'CASH',
          ),
        ],
      );

      final bytes = await buildOrderPdfBytes(
        order: order,
        storeName: 'Elite Laundromat',
        storeAddress: '',
        storePhone: '',
        isFinalInvoice: true,
      );

      final text = extractPdfText(bytes);
      // Both payments were CASH -> should display 'Cash', NOT 'Multiple'
      expect(text, contains('Cash'));
      expect(text, isNot(contains('Multiple')));
      expect(text, contains('PAYMENTS RECEIVED'));
    });
  });
}
