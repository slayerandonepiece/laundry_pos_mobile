import 'dart:typed_data';

import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the PDF shown/shared for an order — shared by the post-delivery
/// invoice (InvoiceActionsSheet) and the pre-collection "order ready" bill
/// (ReadyBillActionsSheet), since both are the same line-item layout; only
/// the header/total framing differs depending on whether the order has
/// actually been paid and delivered yet.
Future<Uint8List> buildOrderPdfBytes({
  required Order order,
  required String storeName,
  required String storeAddress,
  required String storePhone,
  required bool isFinalInvoice,
}) async {
  final pdf = pw.Document();
  final invoiceNo = order.invoice?.invoiceNumber ?? 'INV-${order.displayCode}';
  final dateStr = order.invoice != null
      ? DateFormatter.formatDate(order.invoice!.issuedAt)
      : DateFormatter.formatDate(DateTime.now());
  final headerLabel = isFinalInvoice
      ? 'Invoice: $invoiceNo'
      : 'Bill for: ${order.displayCode}';

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      storeName,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$storeAddress · $storePhone',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(headerLabel, style: const pw.TextStyle(fontSize: 11)),
                  pw.Text(
                    'Order: ${order.displayCode}',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.Text(
                    'Date: $dateStr',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Billed to: ${order.name.isNotEmpty ? order.name : "Customer"} (+91 ${order.phone})',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'SERVICE',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Text(
                    'QTY',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 30),
                  pw.Text(
                    'AMOUNT',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Divider(),
              ...order.lines.map(
                (line) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          line.productName,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                      pw.Text(
                        line.displayQuantity,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.SizedBox(width: 30),
                      pw.Text(
                        CurrencyFormatter.formatPdf(line.totalAmount),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (isFinalInvoice) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Paid:',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      CurrencyFormatter.formatPdf(order.paidAmount),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Bill:',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      CurrencyFormatter.formatPdf(order.totalAmount),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (order.balanceDue > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Balance Due:',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                      pw.Text(
                        CurrencyFormatter.formatPdf(order.balanceDue),
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    ),
  );

  return pdf.save();
}
