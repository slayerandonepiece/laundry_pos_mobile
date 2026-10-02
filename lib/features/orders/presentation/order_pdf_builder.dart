import 'dart:typed_data';

import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the PDF shown/shared for an order — shared by the post-delivery
/// invoice (InvoiceActionsSheet) and the pre-collection "order ready" bill
/// (ReadyBillActionsSheet), matching the server-rendered invoice PDF structure
/// and labels.
Future<Uint8List> buildOrderPdfBytes({
  required Order order,
  required String storeName,
  required String storeAddress,
  required String storePhone,
  required bool isFinalInvoice,
}) async {
  final pdf = pw.Document();
  final invoiceNo = order.invoice?.invoiceNumber ?? 'INV-${order.displayCode}';
  // The server invoice dates the order, not the day the PDF was made.
  final dateStr = order.date.isNotEmpty
      ? DateFormatter.formatFull(order.date)
      : DateFormatter.formatFull(DateTime.now());
  final headerTitle = isFinalInvoice ? invoiceNo : 'Bill';

  // Distinct payment methods calculation
  String formatMethod(String method) {
    final trimmed = method.trim();
    if (trimmed.toUpperCase() == 'CASH') return 'Cash';
    return trimmed;
  }

  final distinctMethods = order.payments
      .map((p) => formatMethod(p.method))
      .where((m) => m.isNotEmpty)
      .toSet()
      .toList();

  final String methodLabel;
  if (distinctMethods.isEmpty) {
    methodLabel = '-';
  } else if (distinctMethods.length == 1) {
    methodLabel = distinctMethods.first;
  } else {
    methodLabel = 'Multiple';
  }

  // Footer date: order.invoice?.generatedAt if present, falling back to DateTime.now()
  final footerDate = order.invoice?.generatedAt ?? DateTime.now();
  final footerDateStr = DateFormatter.formatFull(footerDate);

  final storeContact = [
    storeAddress.trim(),
    storePhone.trim(),
  ].where((s) => s.isNotEmpty).join(' · ');

  const textDark = PdfColor.fromInt(0xff1a2233);
  const textMuted = PdfColor.fromInt(0xff565f6e);
  const labelColor = PdfColor.fromInt(0xff8a93a3);
  const borderColor = PdfColor.fromInt(0xffdde2e9);
  const rowBorderColor = PdfColor.fromInt(0xffeef1f5);
  const tableHeadBg = PdfColor.fromInt(0xfff6f8fb);
  const kvBorderColor = PdfColor.fromInt(0xfff0f2f5);
  const footerColor = PdfColor.fromInt(0xff9aa4b2);
  const headerMuted = PdfColor.fromInt(0xff6b7684);

  pw.Widget kvRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: kvBorderColor, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9.5, color: textMuted),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: textDark,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget sectionLabel(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        label.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 8.5,
          color: labelColor,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  const thStyle = pw.TextStyle(
    fontSize: 8.5,
    color: labelColor,
    letterSpacing: 0.4,
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
      footer: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Generated $footerDateStr - this is not a tax invoice.',
            style: const pw.TextStyle(fontSize: 8, color: footerColor),
          ),
        );
      },
      build: (pw.Context context) => [
        // 1. Header — same layout as the server invoice: store on the left,
        // number and order/date on the right.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              flex: 58,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      storeName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    if (storeContact.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        storeContact,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: headerMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            pw.Expanded(
              flex: 42,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    headerTitle,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Order ${order.displayCode} - $dateStr',
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 9, color: headerMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 24),

        // 2. Two-column "Billed to" / "Order" section
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionLabel('Billed to'),
                  pw.Text(
                    order.name.trim().isNotEmpty
                        ? order.name.trim()
                        : 'Walk-in customer',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  if (order.phone.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      order.phone.trim(),
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionLabel('Order'),
                  kvRow('Order number', order.displayCode),
                  kvRow(
                    'Order date',
                    order.date.isNotEmpty
                        ? DateFormatter.formatFull(order.date)
                        : '-',
                  ),
                  kvRow(
                    'Delivery date',
                    order.due.isNotEmpty
                        ? DateFormatter.formatFull(order.due)
                        : '-',
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 24),

        // 3. Items table with FOUR columns: Service, Qty, Rate, Amount
        sectionLabel('Items'),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: borderColor, width: 1),
              bottom: pw.BorderSide(color: borderColor, width: 1),
            ),
          ),
          child: pw.Column(
            children: [
              pw.Container(
                color: tableHeadBg,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 0,
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 46,
                      child: pw.Text('Service', style: thStyle),
                    ),
                    pw.Expanded(
                      flex: 18,
                      child: pw.Text(
                        'Qty',
                        textAlign: pw.TextAlign.right,
                        style: thStyle,
                      ),
                    ),
                    pw.Expanded(
                      flex: 18,
                      child: pw.Text(
                        'Rate',
                        textAlign: pw.TextAlign.right,
                        style: thStyle,
                      ),
                    ),
                    pw.Expanded(
                      flex: 18,
                      child: pw.Text(
                        'Amount',
                        textAlign: pw.TextAlign.right,
                        style: thStyle,
                      ),
                    ),
                  ],
                ),
              ),
              ...order.lines.map((line) {
                final isPiece =
                    line.unit.toUpperCase() == 'PIECE' ||
                    line.unit.toLowerCase() == 'pcs';
                final String rateText = (isPiece && line.quantity > 0)
                    ? CurrencyFormatter.formatPdf(
                        (line.amount / line.quantity).round(),
                      )
                    : 'Slab pricing';

                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 0,
                  ),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: rowBorderColor, width: 1),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 46,
                        child: pw.Text(
                          line.productName,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 18,
                        child: pw.Text(
                          line.displayQuantity,
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(
                            fontSize: 10.5,
                            color: textDark,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 18,
                        child: pw.Text(
                          rateText,
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(
                            fontSize: 10.5,
                            color: textDark,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 18,
                        child: pw.Text(
                          CurrencyFormatter.formatPdf(line.totalAmount),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        // 4. "Order total" line
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: textDark, width: 1)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Order total',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
              pw.Text(
                CurrencyFormatter.formatPdf(order.totalAmount),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
            ],
          ),
        ),

        // 5. "Payment" section
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sectionLabel('Payment'),
              kvRow('Method', methodLabel),
              kvRow(
                'Amount paid',
                CurrencyFormatter.formatPdf(order.paidAmount),
              ),
              kvRow(
                'Balance due',
                CurrencyFormatter.formatPdf(order.balanceDue),
              ),
            ],
          ),
        ),

        // 6. "Payments received" table (only rendered when order.payments.isNotEmpty)
        if (order.payments.isNotEmpty) ...[
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionLabel('Payments received'),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: borderColor, width: 1),
                      bottom: pw.BorderSide(color: borderColor, width: 1),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Container(
                        color: tableHeadBg,
                        padding: const pw.EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 0,
                        ),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 40,
                              child: pw.Text('Date', style: thStyle),
                            ),
                            pw.Expanded(
                              flex: 30,
                              child: pw.Text('Method', style: thStyle),
                            ),
                            pw.Expanded(
                              flex: 30,
                              child: pw.Text(
                                'Amount',
                                textAlign: pw.TextAlign.right,
                                style: thStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...order.payments.map((payment) {
                        final paymentDateStr = payment.date.isNotEmpty
                            ? DateFormatter.formatFull(payment.date)
                            : '-';
                        return pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 0,
                          ),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              top: pw.BorderSide(
                                color: rowBorderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Expanded(
                                flex: 40,
                                child: pw.Text(
                                  paymentDateStr,
                                  style: const pw.TextStyle(
                                    fontSize: 10.5,
                                    color: textDark,
                                  ),
                                ),
                              ),
                              pw.Expanded(
                                flex: 30,
                                child: pw.Text(
                                  formatMethod(payment.method),
                                  style: const pw.TextStyle(
                                    fontSize: 10.5,
                                    color: textDark,
                                  ),
                                ),
                              ),
                              pw.Expanded(
                                flex: 30,
                                child: pw.Text(
                                  CurrencyFormatter.formatPdf(payment.amount),
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  return pdf.save();
}
