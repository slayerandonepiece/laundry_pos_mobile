import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/presentation/order_pdf_builder.dart';
import 'package:printing/printing.dart';

class InvoiceViewerScreen extends StatelessWidget {
  final Order order;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  const InvoiceViewerScreen({
    super.key,
    required this.order,
    this.storeName = '',
    this.storeAddress = '',
    this.storePhone = '',
  });

  @override
  Widget build(BuildContext context) {
    final invoiceNumber =
        order.invoice?.invoiceNumber ?? 'INV-${order.displayCode}';

    return Scaffold(
      backgroundColor: const Color(0xFF41474F),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invoiceNumber,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Order ${order.displayCode} · ${order.name.isNotEmpty ? order.name : order.phone}',
              style: AppTextStyles.hint,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.mutedText, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      // The same PDF that is shared and sent on WhatsApp, so what the owner
      // sees here is exactly what the customer receives.
      body: PdfPreview(
        build: (_) => buildOrderPdfBytes(
          order: order,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          isFinalInvoice: true,
        ),
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: 900,
        padding: EdgeInsets.zero,
        previewPageMargin: EdgeInsets.zero,
        scrollViewDecoration: const BoxDecoration(color: Color(0xFF41474F)),
      ),
    );
  }
}
