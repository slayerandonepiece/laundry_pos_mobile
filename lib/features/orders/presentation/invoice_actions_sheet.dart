import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/invoice_viewer_screen.dart';
import 'package:myshop/features/orders/presentation/order_pdf_builder.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

const _tag = 'INVOICE_SHARE';

class InvoiceActionsSheet extends StatelessWidget {
  final Order order;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  const InvoiceActionsSheet({
    super.key,
    required this.order,
    this.storeName = '',
    this.storeAddress = '',
    this.storePhone = '',
  });

  static Future<void> show(
    BuildContext context, {
    required Order order,
    String storeName = '',
    String storeAddress = '',
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
    final invoiceNo =
        order.invoice?.invoiceNumber ?? 'INV-${order.displayCode}';

    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.viewPadding.bottom > 0
        ? mediaQuery.viewPadding.bottom
        : mediaQuery.padding.bottom;
    final bottomInset = keyboardHeight > 0
        ? keyboardHeight + 16
        : (safeBottom > 0 ? safeBottom + 16 : 26.0);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: bottomInset,
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
            '${order.displayCode} · ${order.name.isNotEmpty ? order.name : order.phone}',
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
            subtitle: 'Share the invoice PDF with customer',
            onTap: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              Navigator.pop(context);
              // A wa.me deep link can only pre-fill text — it cannot carry
              // an attachment, so there is no way to jump straight into a
              // WhatsApp chat with the PDF already attached. The OS share
              // sheet is the only path that can hand WhatsApp an actual
              // file; the user picks WhatsApp (and the contact) from it.
              await _sharePdfSafely(
                messenger: messenger,
                text:
                    'Hello ${order.name.isNotEmpty ? order.name : "Customer"}, '
                    'your laundry order ${order.displayCode} ($invoiceNo) has been '
                    'completed and paid in full (${CurrencyFormatter.format(order.totalAmount)}). '
                    '${storeName.isNotEmpty ? "Thank you for choosing $storeName!" : "Thank you for your business!"}',
                subject: storeName.isNotEmpty
                    ? 'Invoice $invoiceNo - $storeName'
                    : 'Invoice $invoiceNo',
                invoiceNo: invoiceNo,
              );
            },
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.share_outlined,
            iconColor: AppColors.mutedText,
            title: 'Share',
            subtitle: 'Invoice PDF to any app on this phone',
            onTap: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              Navigator.pop(context);
              await _sharePdfSafely(
                messenger: messenger,
                text:
                    'Invoice $invoiceNo for order ${order.displayCode}: '
                    '${CurrencyFormatter.format(order.totalAmount)} paid in full'
                    '${storeName.isNotEmpty ? " at $storeName" : ""}.',
                subject: storeName.isNotEmpty
                    ? 'Invoice $invoiceNo - $storeName'
                    : 'Invoice $invoiceNo',
                invoiceNo: invoiceNo,
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

  /// Wraps [_sharePdf] so a failure is visible (SnackBar + log) instead of
  /// silently doing nothing — a bare unawaited exception from a dialog
  /// onTap is otherwise swallowed by the zone's error handler, and from the
  /// user's side the button just looks broken with no feedback at all.
  Future<void> _sharePdfSafely({
    required ScaffoldMessengerState? messenger,
    required String text,
    required String subject,
    required String invoiceNo,
  }) async {
    try {
      AppLogger.log(
        _tag,
        'starting share for invoice $invoiceNo, order ${order.displayCode}',
      );
      final result = await _sharePdf(
        text: text,
        subject: subject,
        invoiceNo: invoiceNo,
      );
      AppLogger.log(_tag, 'share sheet result: ${result.status}');
    } catch (e, st) {
      AppLogger.log(_tag, 'share failed', error: e);
      AppLogger.log(_tag, 'share failed stacktrace: $st');
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not share invoice: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Shares the invoice as an actual PDF attachment via the OS share sheet
  /// (WhatsApp, Drive, email, etc. — whatever the user picks there), instead
  /// of just a text message with no file.
  Future<ShareResult> _sharePdf({
    required String text,
    required String subject,
    required String invoiceNo,
  }) async {
    final bytes = await _buildInvoicePdfBytes();
    final fileName = '$invoiceNo-${order.displayCode}.pdf';
    return SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
        ],
        fileNameOverrides: [fileName],
        text: text,
        subject: subject,
      ),
    );
  }

  Future<void> _printInvoicePdf() async {
    final bytes = await _buildInvoicePdfBytes();
    final invoiceNo =
        order.invoice?.invoiceNumber ?? 'INV-${order.displayCode}';
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: '$invoiceNo-${order.displayCode}',
    );
  }

  Future<Uint8List> _buildInvoicePdfBytes() {
    return buildOrderPdfBytes(
      order: order,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      isFinalInvoice: true,
    );
  }
}
