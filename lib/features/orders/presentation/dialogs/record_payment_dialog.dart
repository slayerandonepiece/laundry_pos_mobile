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
import 'package:myshop/shared/widgets/app_text_field.dart';

class RecordPaymentDialog extends StatefulWidget {
  final Order order;

  const RecordPaymentDialog({super.key, required this.order});

  static Future<void> show(BuildContext context, {required Order order}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
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
  final TextEditingController _amountController = TextEditingController();
  String? _selectedMethodName;
  List<StorePaymentMethod> _methods = const [];
  bool _loadingMethods = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final repo = context.read<PosRepository>();
      final methods =
          repo.getCachedPaymentMethodsList() ?? await repo.listPaymentMethods();
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

  int? get _parsedPaise {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    final val = double.tryParse(text);
    if (val == null) return null;
    return (val * 100).round();
  }

  String? get _amountError {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    final val = double.tryParse(text);
    if (val == null) return 'Enter a valid amount';
    final paise = (val * 100).round();
    if (paise <= 0) return 'Amount must be greater than zero';
    if (paise > widget.order.balanceDue) {
      return 'Amount cannot exceed balance (${CurrencyFormatter.format(widget.order.balanceDue)})';
    }
    return null;
  }

  bool get _isAmountValid {
    final paise = _parsedPaise;
    if (paise == null) return false;
    return paise > 0 && paise <= widget.order.balanceDue;
  }

  void _payBalance() {
    final rupees = widget.order.balanceDue / 100.0;
    final text = (widget.order.balanceDue % 100 == 0)
        ? rupees.toInt().toString()
        : rupees.toStringAsFixed(2);
    _amountController.text = text;
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    setState(() {});
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
            _isAmountValid &&
            !_loadingMethods &&
            _selectedMethodName != null;

        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
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
                          'BALANCE DUE',
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

                  // Amount Input
                  AppTextField(
                    label: 'Amount (₹)',
                    controller: _amountController,
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    errorText: _amountError,
                    onChanged: (_) => setState(() {}),
                    suffixIcon: TextActionButton(
                      label: 'Pay balance',
                      height: AppButtonHeight.compact,
                      onPressed: isBusy ? null : _payBalance,
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
                    const SizedBox(height: 20),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: isBusy
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Record payment',
                          isLoading: isBusy,
                          onPressed: !canSubmit
                              ? null
                              : () {
                                  context.read<OrdersBloc>().add(
                                    RecordPaymentEvent(
                                      orderCode: widget.order.orderCode,
                                      amount: _parsedPaise!,
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
