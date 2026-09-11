import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/invoice_viewer_screen.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class InvoiceActionsSheet extends StatelessWidget {
  final Order order;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  const InvoiceActionsSheet({
    super.key,
    required this.order,
    this.storeName = 'MyShop Laundry',
    this.storeAddress = 'Bengaluru, India',
    this.storePhone = '',
  });

  static Future<void> show(
    BuildContext context, {
    required Order order,
    String storeName = 'MyShop Laundry',
    String storeAddress = 'Bengaluru, India',
    String storePhone = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InvoiceActionsSheet(
        order: order,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceNo = order.invoice?.invoiceNumber ?? 'INV-${order.orderCode}';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.controlBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),

          // Title
          Text(
            'Invoice $invoiceNo',
            style: const TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${order.orderCode} · ${order.name.isNotEmpty ? order.name : order.phone}',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 20),

          // Options
          _buildActionRow(
            icon: Icons.visibility_outlined,
            iconColor: AppColors.primary,
            title: 'View',
            subtitle: 'Open it in the app',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceViewerScreen(
                    order: order,
                    storeName: storeName,
                    storeAddress: storeAddress,
                    storePhone: storePhone,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.success,
            title: 'Send on WhatsApp',
            subtitle: 'Message customer with invoice details',
            onTap: () async {
              Navigator.pop(context);
              final text = Uri.encodeComponent(
                'Hello ${order.name.isNotEmpty ? order.name : "Customer"},\n'
                'Your laundry order ${order.orderCode} ($invoiceNo) has been completed and paid in full (${CurrencyFormatter.format(order.totalAmount)}).\n'
                'Thank you for choosing $storeName!',
              );
              final cleanPhone = order.phone.replaceAll(RegExp(r'[^0-9]'), '');
              final url = Uri.parse('https://wa.me/91$cleanPhone?text=$text');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.share_outlined,
            iconColor: AppColors.mutedText,
            title: 'Share',
            subtitle: 'Any app on this phone',
            onTap: () {
              Navigator.pop(context);
              // ignore: deprecated_member_use
              Share.share(
                'Invoice $invoiceNo for order ${order.orderCode}: ${CurrencyFormatter.format(order.totalAmount)} paid in full at $storeName.',
                subject: 'Invoice $invoiceNo - $storeName',
              );
            },
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.print_outlined,
            iconColor: AppColors.mutedText,
            title: 'Print',
            subtitle: 'To a connected printer',
            onTap: () async {
              Navigator.pop(context);
              await _printInvoicePdf();
            },
          ),
          const SizedBox(height: 18),

          SecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 11,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.faintText,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printInvoicePdf() async {
    final pdf = pw.Document();
    final invoiceNo = order.invoice?.invoiceNumber ?? 'INV-${order.orderCode}';
    final dateStr = order.invoice != null
        ? DateFormatter.formatDate(order.invoice!.issuedAt)
        : DateFormatter.formatDate(DateTime.now());

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
                    pw.Text(
                      'Invoice: $invoiceNo',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.Text(
                      'Order: ${order.orderCode}',
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
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '$invoiceNo-${order.orderCode}',
    );
  }
}
