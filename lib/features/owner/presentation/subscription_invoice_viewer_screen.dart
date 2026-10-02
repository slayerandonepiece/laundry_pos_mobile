import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/analytics/app_analytics.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/owner/data/models/subscription_invoice_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:printing/printing.dart';

/// Shows one subscription invoice as the server renders it, full width, with
/// share kept out of the way in the app bar.
class SubscriptionInvoiceViewerScreen extends StatefulWidget {
  final SubscriptionInvoice invoice;

  const SubscriptionInvoiceViewerScreen({super.key, required this.invoice});

  @override
  State<SubscriptionInvoiceViewerScreen> createState() =>
      _SubscriptionInvoiceViewerScreenState();
}

class _SubscriptionInvoiceViewerScreenState
    extends State<SubscriptionInvoiceViewerScreen> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _bytes = context.read<OwnerRepository>().getSubscriptionInvoicePdf(
      widget.invoice.invoiceSeq,
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    return Scaffold(
      backgroundColor: const Color(0xFF41474F),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invoice.number,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(invoice.title, style: AppTextStyles.hint),
          ],
        ),
        actions: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              return IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share, color: AppColors.mutedText),
                onPressed: bytes == null
                    ? null
                    : () async {
                        await Printing.sharePdf(
                          bytes: bytes,
                          filename: '${invoice.number}.pdf',
                        );
                        await AppAnalytics.invoiceShared(kind: 'subscription');
                      },
              );
            },
          ),
          IconButton(
            tooltip: 'Close',
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
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.surface),
            );
          }
          final bytes = snapshot.data;
          if (snapshot.hasError || bytes == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Couldn't load this invoice.",
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SecondaryButton(
                      label: 'Try again',
                      height: AppButtonHeight.inline,
                      onPressed: () => setState(_load),
                    ),
                  ],
                ),
              ),
            );
          }
          return PdfPreview(
            build: (_) async => bytes,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            maxPageWidth: 900,
            padding: EdgeInsets.zero,
            previewPageMargin: EdgeInsets.zero,
            scrollViewDecoration: const BoxDecoration(color: Color(0xFF41474F)),
          );
        },
      ),
    );
  }
}
