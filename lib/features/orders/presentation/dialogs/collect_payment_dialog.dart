import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class CollectPaymentDialog extends StatefulWidget {
  final Order order;

  const CollectPaymentDialog({super.key, required this.order});

  static Future<void> show(BuildContext context, {required Order order}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      // barrierColor: AppColors.tr,
      builder: (_) => RepositoryProvider.value(
        value: context.read<PosRepository>(),
        child: BlocProvider.value(
          value: context.read<OrdersBloc>(),
          child: CollectPaymentDialog(order: order),
        ),
      ),
    );
  }

  @override
  State<CollectPaymentDialog> createState() => _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends State<CollectPaymentDialog> {
  String? _selectedMethodName;
  List<StorePaymentMethod> _methods = const [];
  bool _loadingMethods = true;

  @override
  void initState() {
    super.initState();
    // A fully paid order goes straight to delivery — there is no method to
    // pick, so skip the fetch.
    if (widget.order.balanceDue == 0) {
      _loadingMethods = false;
    } else {
      _loadPaymentMethods();
    }
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final methods = await context.read<PosRepository>().listPaymentMethods();
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _loadingMethods = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _methods = const [];
        _loadingMethods = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // One constant entry point for taking a ready order to delivered: if
    // there's a balance, collect it here; if it was already paid upfront,
    // skip straight to delivery — no separate "hand over" flow/dialog.
    final isPaid = widget.order.balanceDue == 0;

    return BlocConsumer<OrdersBloc, OrdersState>(
      listener: (context, state) {
        // Guard by orderCode: actionSuccessMessage/selectedOrder are shared
        // bloc-wide state, so only pop this dialog for its own order's
        // success, not any other order's action reaching the same bloc.
        if (state.actionSuccessMessage != null &&
            state.selectedOrder?.orderCode == widget.order.orderCode) {
          Navigator.pop(context);
        } else if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isBusy = isPaid
            ? state.isUpdatingStatus
            : state.isCollectingPayment;
        final canSubmit =
            !isBusy &&
            (isPaid || (!_loadingMethods && _selectedMethodName != null));

        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                const Text(
                  'Collect payment & deliver',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.order.orderCode} · ${widget.order.name.isNotEmpty ? widget.order.name : widget.order.phone}',
                  style: AppTextStyles.hint,
                ),
                const SizedBox(height: 18),

                if (isPaid) ...[
                  // Already paid upfront — nothing to collect, just confirm
                  // delivery.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      border: Border.all(color: const Color(0xFFB7E4CF)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 22,
                          color: AppColors.success,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ALREADY PAID',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(widget.order.totalAmount),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontDisplay,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  // Amount Due Box
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.inset,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'AMOUNT DUE',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.mutedText,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(widget.order.balanceDue),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontDisplay,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Options
                  if (_loadingMethods) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else if (_methods.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'No payment methods are enabled. Ask the owner to enable one in Profile → Payment methods.',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    for (int i = 0; i < _methods.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _buildOption(
                        name: _methods[i].name,
                        icon: _methods[i].type.toUpperCase() == 'UPI'
                            ? Icons.qr_code_scanner_outlined
                            : Icons.payments_outlined,
                        isSelected: _selectedMethodName == _methods[i].name,
                        onTap: isBusy
                            ? () {}
                            : () => setState(
                                  () => _selectedMethodName = _methods[i].name,
                                ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ],

                // Information note
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.inset,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontBody,
                              fontSize: 12,
                              color: AppColors.mutedText,
                              height: 1.45,
                            ),
                            children: [
                              TextSpan(text: 'Marks the order '),
                              TextSpan(
                                text: 'delivered',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              TextSpan(text: ' and creates the invoice.'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: isBusy ? null : () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: isPaid ? 'Deliver order' : 'Collect & deliver',
                        isLoading: isBusy,
                        onPressed: !canSubmit
                            ? null
                            : () {
                                if (isPaid) {
                                  context.read<OrdersBloc>().add(
                                    HandoverOrderEvent(widget.order.orderCode),
                                  );
                                } else {
                                  context.read<OrdersBloc>().add(
                                    CollectPaymentEvent(
                                      orderCode: widget.order.orderCode,
                                      amount: widget.order.balanceDue,
                                      method: _selectedMethodName!,
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOption({
    required String name,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.selectedSurface : AppColors.surface,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.controlBorder,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 21,
              color: isSelected ? AppColors.primary : AppColors.mutedText,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AppColors.primary : AppColors.text,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: isSelected
                    ? null
                    : Border.all(color: AppColors.controlBorder, width: 2),
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(Icons.check, size: 13, color: Colors.white),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
