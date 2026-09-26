import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/step_progress_header.dart';
import '../../shell/bloc/outlet_scope_cubit.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import '../bloc/cart_state.dart';
import 'dialogs/discard_order_dialog.dart';
import 'order_placed_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String? _selectedMethodId;
  bool _isDelivery = false;

  void _handleBack(BuildContext context) {
    DiscardOrderDialog.show(
      context,
      onDiscard: () {
        context.read<CartBloc>().add(ResetSaleEvent());
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
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

          final hasSelection = _isDelivery ||
              state.paymentMethods.any((m) => m.id == _selectedMethodId);

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
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: AppColors.text,
                                  ),
                                  onPressed: () => _handleBack(context),
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
                              onPressed: () => _handleBack(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const StepProgressHeader(currentStep: 3),
                      ],
                    ),
                  ),

                  // Body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
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
                            padding: const EdgeInsets.all(16),
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
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 12),
                                ...state.items.values.map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
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

                          const SizedBox(height: 22),

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
                            const SizedBox(height: 16),
                          ],

                          Text('PAYMENT METHOD', style: AppTextStyles.label),
                          const SizedBox(height: 10),

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
                          else
                            ...state.paymentMethods.map((method) {
                              final isSelected = !_isDelivery &&
                                  _selectedMethodId == method.id;
                              final icon = (method.type == 'UPI' ||
                                      method.name
                                          .toUpperCase()
                                          .contains('UPI'))
                                  ? Icons.qr_code_scanner_outlined
                                  : (method.name.toLowerCase().contains('card')
                                      ? Icons.credit_card_outlined
                                      : Icons.payments_outlined);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildPaymentOption(
                                  id: method.id,
                                  title: method.name,
                                  subtitle: 'Pay full amount now',
                                  icon: icon,
                                  isSelected: isSelected,
                                  onTap: () => setState(() {
                                    _selectedMethodId = method.id;
                                    _isDelivery = false;
                                  }),
                                ),
                              );
                            }),

                          // Pay on delivery Choice (always present)
                          _buildPaymentOption(
                            id: 'delivery',
                            title: 'Pay on delivery',
                            subtitle: 'Collect full amount at handover',
                            icon: Icons.schedule_outlined,
                            isSelected: _isDelivery,
                            onTap: () => setState(() {
                              _selectedMethodId = null;
                              _isDelivery = true;
                            }),
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
                      label: _isDelivery
                          ? 'Place order · Pay on delivery'
                          : 'Place order · ${CurrencyFormatter.format(totalAmount)}',
                      isLoading: state.isSubmitting,
                      onPressed: (state.isSubmitting || !hasSelection)
                          ? null
                          : () {
                              if (_isDelivery) {
                                context.read<CartBloc>().add(
                                  SubmitOrderEvent(
                                    paymentChoice: 'delivery',
                                  ),
                                );
                              } else if (_selectedMethodId != null) {
                                final method = state.paymentMethods
                                    .where((m) => m.id == _selectedMethodId)
                                    .firstOrNull;
                                if (method != null) {
                                  context.read<CartBloc>().add(
                                    SubmitOrderEvent(
                                      paymentChoice: 'prepaid',
                                      paymentMethodName: method.name,
                                    ),
                                  );
                                }
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

  Widget _buildPaymentOption({
    required String id,
    required String title,
    required String subtitle,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.primary : AppColors.mutedText,
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.hint),
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
