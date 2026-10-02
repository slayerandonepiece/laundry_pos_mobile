import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../shell/bloc/outlet_scope_cubit.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import '../bloc/cart_state.dart';
import '../../owner/data/models/payment_method_model.dart';
import 'dialogs/discard_order_dialog.dart';
import 'order_placed_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String? _selectedMethodId;
  late DateTime _selectedDueDate;
  late final TextEditingController _notesController;
  final TextEditingController _receivedController = TextEditingController();
  String? _dueDateError;

  /// Paise typed in "Received now". Null when blank (the full total is taken),
  /// -1 when the text is not a number.
  int? get _receivedPaise {
    final text = _receivedController.text.trim();
    if (text.isEmpty) return null;
    final rupees = double.tryParse(text);
    return rupees == null ? -1 : (rupees * 100).round();
  }

  @override
  void initState() {
    super.initState();
    final cartState = context.read<CartBloc>().state;
    _selectedDueDate = cartState.dueDate;
    _notesController = TextEditingController(text: cartState.notes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _receivedController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate.isBefore(today) ? today : _selectedDueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final pickedDate = DateTime(picked.year, picked.month, picked.day);
    if (pickedDate.isBefore(today)) {
      setState(() {
        _dueDateError = 'Due date cannot be in the past';
      });
    } else {
      setState(() {
        _selectedDueDate = pickedDate;
        _dueDateError = null;
      });
    }
  }

  /// Back returns to the items to edit them; what was typed here is kept.
  void _goBack(BuildContext context) {
    context.read<CartBloc>().add(
      UpdateOrderDetailsEvent(
        dueDate: _selectedDueDate,
        notes: _notesController.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  /// Closing (X) abandons the whole sale, so it asks first.
  void _discard(BuildContext context) {
    DiscardOrderDialog.show(
      context,
      onDiscard: () {
        context.read<CartBloc>().add(ResetSaleEvent());
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  void _pickQuickDate(int daysFromToday) {
    final now = DateTime.now();
    setState(() {
      _selectedDueDate = DateTime(now.year, now.month, now.day + daysFromToday);
      _dueDateError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack(context);
      },
      child: BlocConsumer<CartBloc, CartState>(
        listener: (context, state) {
          if (state.placedOrder != null) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => OrderPlacedScreen(order: state.placedOrder!),
              ),
              (route) => route.isFirst,
            );
          }
        },
        builder: (context, state) {
          final totalAmount = state.totalAmount;
          final outletScope = context.watch<OutletScopeCubit>().state;
          final outletId = state.outletId;
          final outlet = outletId != null
              ? outletScope.allowed.where((o) => o.id == outletId).firstOrNull
              : null;
          final outletName = outlet?.displayName;

          final selectedMethod = state.paymentMethods
              .where((m) => m.id == _selectedMethodId)
              .firstOrNull;
          final hasSelection = selectedMethod != null;
          final takesPaymentNow =
              selectedMethod != null && !selectedMethod.isCashOnDelivery;
          final receivedPaise = takesPaymentNow ? _receivedPaise : null;
          final receivedError =
              receivedPaise != null &&
                  (receivedPaise <= 0 || receivedPaise > totalAmount)
              ? 'Enter an amount between ₹1 and ${CurrencyFormatter.format(totalAmount)}'
              : null;

          return Scaffold(
            backgroundColor: AppColors.surface,
            body: SafeArea(
              child: Column(
                children: [
                  // App Bar (Step 3 of 3)
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        bottom: BorderSide(color: AppColors.border, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: AppColors.text,
                              ),
                              onPressed: () => _goBack(context),
                            ),
                            const SizedBox(width: 4),
                            const Text('Checkout', style: AppTextStyles.h3),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.mutedText,
                          ),
                          onPressed: () => _discard(context),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Submission Error Banner if any
                          if (state.submissionError != null) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: AppColors.dangerBorder,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 18,
                                    color: AppColors.danger,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      state.submissionError!,
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontBody,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Order Summary Card
                          AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            state.customerName.isNotEmpty
                                                ? state.customerName
                                                : 'Walk-in customer',
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontBody,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '+91 ${state.customerPhone} · ${state.totalItemCount} services',
                                            style: AppTextStyles.hint,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      CurrencyFormatter.format(totalAmount),
                                      style: AppTextStyles.moneyLarge.copyWith(
                                        fontSize: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(),
                                const SizedBox(height: 10),
                                ...state.items.values.map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${item.product.name} · ${item.displayQuantity}',
                                          style: AppTextStyles.bodySmall,
                                        ),
                                        Text(
                                          CurrencyFormatter.format(
                                            item.computedAmount,
                                          ),
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.text,
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          if (outletName != null) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.storefront_outlined,
                                  size: 16,
                                  color: AppColors.mutedText,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    outletName,
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontBody,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],

                          _buildDueDateSection(),
                          const SizedBox(height: 16),

                          Text('PAYMENT METHOD', style: AppTextStyles.label),
                          const SizedBox(height: 8),

                          if (state.paymentMethods.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text(
                                'No payment methods are enabled. Ask the owner to enable one in Profile → Payment methods.',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 13,
                                  color: AppColors.mutedText,
                                  height: 1.4,
                                ),
                              ),
                            )
                          else ...[
                            _buildMethodGrid(
                              state.paymentMethods
                                  .where((m) => !m.isCashOnDelivery)
                                  .toList(),
                            ),
                            for (final cod in state.paymentMethods.where(
                              (m) => m.isCashOnDelivery,
                            )) ...[
                              const SizedBox(height: 10),
                              _buildCodButton(cod),
                            ],
                          ],

                          const SizedBox(height: 10),

                          if (takesPaymentNow) ...[
                            AppTextField(
                              key: const Key('checkout_received_field'),
                              controller: _receivedController,
                              label: 'Received now',
                              hintText:
                                  'Full amount ${CurrencyFormatter.format(totalAmount)}',
                              errorText: receivedError,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),
                          ],

                          AppTextField(
                            key: const Key('checkout_notes_field'),
                            controller: _notesController,
                            label: 'Notes',
                            hintText:
                                'Add special instructions or notes (optional)',
                            maxLines: 3,
                            keyboardType: TextInputType.multiline,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Button
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(color: AppColors.border, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: PrimaryButton(
                      label: selectedMethod?.isCashOnDelivery == true
                          ? 'Place order · Pay on delivery'
                          : receivedPaise != null && receivedError == null
                          ? 'Place order · ${CurrencyFormatter.format(receivedPaise)} received now'
                          : 'Place order · ${CurrencyFormatter.format(totalAmount)}',
                      isLoading: state.isSubmitting,
                      onPressed:
                          (state.isSubmitting ||
                              !hasSelection ||
                              receivedError != null)
                          ? null
                          : () {
                              if (selectedMethod.isCashOnDelivery) {
                                context.read<CartBloc>().add(
                                  SubmitOrderEvent(
                                    paymentChoice: 'delivery',
                                    dueDate: _selectedDueDate,
                                    notes: _notesController.text.trim(),
                                  ),
                                );
                              } else {
                                context.read<CartBloc>().add(
                                  SubmitOrderEvent(
                                    paymentChoice: 'prepaid',
                                    paymentMethodName: selectedMethod.name,
                                    receivedNow: receivedPaise,
                                    dueDate: _selectedDueDate,
                                    notes: _notesController.text.trim(),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDueDateSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool isDay(int offset) {
      final d = DateTime(today.year, today.month, today.day + offset);
      return _selectedDueDate.year == d.year &&
          _selectedDueDate.month == d.month &&
          _selectedDueDate.day == d.day;
    }

    final quick = isDay(0) || isDay(1) || isDay(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DUE DATE', style: AppTextStyles.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _dateChip('Today', isDay(0), () => _pickQuickDate(0)),
            _dateChip('Tomorrow', isDay(1), () => _pickQuickDate(1)),
            _dateChip('In 2 days', isDay(2), () => _pickQuickDate(2)),
            _dateChip(
              'Pick date',
              !quick,
              _pickDueDate,
              key: const Key('checkout_due_date_picker'),
              icon: Icons.calendar_today_outlined,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Due date: ${DateFormatter.formatDate(_selectedDueDate)}',
          style: AppTextStyles.hint,
        ),
        if (_dueDateError != null) ...[
          const SizedBox(height: 3),
          Text(
            _dueDateError!,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    Key? key,
    IconData? icon,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.controlBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : AppColors.mutedText,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _methodIcon(StorePaymentMethod method) {
    switch ((method.code.isNotEmpty ? method.code : method.type)
        .toUpperCase()) {
      case 'UPI':
        return Icons.qr_code_scanner_outlined;
      case 'CARD':
        return Icons.credit_card_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  /// Whatever the store has enabled, two to a row.
  Widget _buildMethodGrid(List<StorePaymentMethod> methods) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final m in methods)
              SizedBox(
                width: width,
                child: _buildPaymentOption(
                  id: m.id,
                  title: m.name,
                  icon: _methodIcon(m),
                  isSelected: _selectedMethodId == m.id,
                  onTap: () => setState(() => _selectedMethodId = m.id),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Pay later is a different choice from taking money now, so it stands apart.
  Widget _buildCodButton(StorePaymentMethod method) {
    final selected = _selectedMethodId == method.id;
    return InkWell(
      onTap: () => setState(() => _selectedMethodId = method.id),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.controlBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 20,
              color: selected ? AppColors.primary : AppColors.mutedText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.text,
                    ),
                  ),
                  const Text(
                    'Customer pays at delivery',
                    style: AppTextStyles.hint,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 20,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.selectedSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.controlBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.primary : AppColors.mutedText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected ? AppColors.primary : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.controlBorder,
                  width: 2,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
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
