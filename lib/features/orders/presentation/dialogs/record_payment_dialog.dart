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

class RecordPaymentDialog extends StatefulWidget {
  final Order order;

  const RecordPaymentDialog({super.key, required this.order});

  /// Collects the whole balance: nothing to type, only the method to choose.
  static Future<void> show(BuildContext context, {required Order order}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => RepositoryProvider.value(
        value: context.read<PosRepository>(),
        child: BlocProvider.value(
          value: context.read<OrdersBloc>(),
          child: RecordPaymentDialog(order: order),
        ),
      ),
    );
  }

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  String? _selectedMethodName;
  List<StorePaymentMethod> _methods = const [];
  bool _loadingMethods = true;

  /// One payment method per order for now: once something was paid, the rest
  /// goes through the same method.
  String? get _lockedMethod {
    for (final p in widget.order.payments) {
      if (p.method.trim().isNotEmpty) return p.method.trim();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedMethodName = _lockedMethod;
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final repo = context.read<PosRepository>();
      final methods =
          repo.getCachedPaymentMethodsList() ?? await repo.listPaymentMethods();
      if (!mounted) return;
      setState(() {
        // Cash on delivery is not money received; it is how the order was placed.
        _methods = methods.where((m) => !m.isCashOnDelivery).toList();
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
    return BlocConsumer<OrdersBloc, OrdersState>(
      listener: (context, state) {
        if (state.actionSuccessMessage != null &&
            state.selectedOrder?.isSameOrder(widget.order) == true) {
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
        final isBusy = state.isCollectingPayment;
        final canSubmit =
            !isBusy &&
            widget.order.balanceDue > 0 &&
            (_lockedMethod != null || !_loadingMethods) &&
            _selectedMethodName != null;

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                const Text(
                  'Record payment',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.order.displayCode} · ${widget.order.name.isNotEmpty ? widget.order.name : widget.order.phone}',
                  style: AppTextStyles.hint,
                ),
                const SizedBox(height: 18),

                // Balance Due Reference Box
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
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
                        'AMOUNT TO COLLECT',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontBody,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.mutedText,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(widget.order.balanceDue),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontDisplay,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Payment Options
                if (_lockedMethod != null) ...[
                  _buildOption(
                    name: _lockedMethod!,
                    icon: Icons.payments_outlined,
                    isSelected: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Same method as the earlier payment on this order.',
                    style: AppTextStyles.hint,
                  ),
                  const SizedBox(height: 20),
                ] else if (_loadingMethods) ...[
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
                  const SizedBox(height: 20),
                ],

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
                        label:
                            'Record ${CurrencyFormatter.format(widget.order.balanceDue)}',
                        isLoading: isBusy,
                        onPressed: !canSubmit
                            ? null
                            : () {
                                context.read<OrdersBloc>().add(
                                  RecordPaymentEvent(
                                    orderCode: widget.order.orderCode,
                                    amount: widget.order.balanceDue,
                                    method: _selectedMethodName!,
                                  ),
                                );
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
