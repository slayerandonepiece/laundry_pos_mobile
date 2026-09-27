import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/order_pdf_builder.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

const _tag = 'READY_BILL_SHARE';

/// Shown right after an order is marked "Ready", once the user confirms
/// they want to notify the customer. Shares a PDF bill — not the delivery
/// invoice, which doesn't exist yet at this stage — with a message telling
/// the customer their order is ready to collect.
class ReadyBillActionsSheet extends StatelessWidget {
  final Order order;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  const ReadyBillActionsSheet({
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
      builder: (_) => ReadyBillActionsSheet(
        order: order,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      ),
    );
  }

  String get _message =>
      'Hello ${order.name.isNotEmpty ? order.name : "Customer"}, '
      'your order ${order.displayCode} is ready! Your total bill is '
      '${CurrencyFormatter.format(order.totalAmount)}. '
      'Please come and collect your order at your convenience. '
      'Thank you for choosing $storeName!';

  @override
  Widget build(BuildContext context) {
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
          const Text(
            'Notify customer',
            style: TextStyle(
              fontFamily: AppTextStyles.fontDisplay,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${order.displayCode} · ${order.name.isNotEmpty ? order.name : order.phone} · Bill ${CurrencyFormatter.format(order.totalAmount)}',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 20),

          _buildActionRow(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.success,
            title: 'Send on WhatsApp',
            subtitle: 'Share the bill PDF with customer',
            onTap: (context) => _shareBill(context),
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.share_outlined,
            iconColor: AppColors.mutedText,
            title: 'Share',
            subtitle: 'Bill PDF to any app on this phone',
            onTap: (context) => _shareBill(context),
          ),
          const SizedBox(height: 10),

          _buildActionRow(
            icon: Icons.print_outlined,
            iconColor: AppColors.mutedText,
            title: 'Print',
            subtitle: 'To a connected printer',
            onTap: (context) async {
              Navigator.pop(context);
              await _printBillPdf();
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

  Future<void> _shareBill(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    try {
      AppLogger.log(_tag, 'starting share for order ${order.displayCode}');
      final bytes = await buildOrderPdfBytes(
        order: order,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        isFinalInvoice: false,
      );
      final fileName = 'Bill-${order.displayCode}.pdf';
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
          ],
          fileNameOverrides: [fileName],
          text: _message,
          subject: 'Order ${order.displayCode} ready - $storeName',
        ),
      );
      AppLogger.log(_tag, 'share sheet result: ${result.status}');
    } catch (e) {
      AppLogger.log(_tag, 'share failed', error: e);
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('Could not share bill — try again'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _printBillPdf() async {
    final bytes = await buildOrderPdfBytes(
      order: order,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      isFinalInvoice: false,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'Bill-${order.displayCode}',
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required void Function(BuildContext context) onTap,
  }) {
    return Builder(
      builder: (context) => InkWell(
        onTap: () => onTap(context),
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
      ),
    );
  }
}
