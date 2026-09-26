import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_inset.dart';
import '../../../core/sync/sync_manager.dart';
import '../../orders/bloc/orders_bloc.dart';
import '../../orders/bloc/orders_event.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';

import 'package:myshop/features/orders/data/models/order_model.dart';

class OrderPlacedScreen extends StatefulWidget {
  final Order order;

  const OrderPlacedScreen({super.key, required this.order});

  @override
  State<OrderPlacedScreen> createState() => _OrderPlacedScreenState();
}

class _OrderPlacedScreenState extends State<OrderPlacedScreen> {
  @override
  void initState() {
    super.initState();
    // Prime the Orders BLoC with the local cache immediately so the newly
    // placed order appears as soon as the user taps "View in orders".
    context.read<OrdersBloc>().add(LoadOrdersEvent());
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPrepaid =
        order.paidAmount >= order.totalAmount && order.totalAmount > 0;
    final paymentMethod = order.payments.isNotEmpty
        ? order.payments.first.method
        : 'Cash';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Green check circle
                      Container(
                        width: 82,
                        height: 82,
                        decoration: const BoxDecoration(
                          color: AppColors.successBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: 44,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Order placed', style: AppTextStyles.h1),
                      const SizedBox(height: 8),
                      Text(
                        '${order.name.isNotEmpty ? order.name : "+91 ${order.phone}"} · ready by ${DateFormatter.formatShort(order.due)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Sync status chip — shows "Syncing..." or "Saved offline"
                      ValueListenableBuilder<SyncState>(
                        valueListenable: SyncManager.instance,
                        builder: (context, syncState, _) {
                          if (syncState.isSynced) {
                            return const SizedBox.shrink();
                          }
                          final isSyncing = syncState.isSyncing;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSyncing
                                  ? const Color(0xFFEAF1FF)
                                  : const Color(0xFFFFF8E6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSyncing
                                    ? const Color(0xFFB5CEFA)
                                    : const Color(0xFFE9C57A),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSyncing)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: Color(0xFF1A56DB),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.cloud_off_outlined,
                                    size: 14,
                                    color: Color(0xFFB07A00),
                                  ),
                                const SizedBox(width: 7),
                                Text(
                                  isSyncing
                                      ? 'Syncing to server...'
                                      : 'Saved offline — will sync when online',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSyncing
                                        ? const Color(0xFF1A56DB)
                                        : const Color(0xFFB07A00),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Order Card
                      AppCard(
                        padding: const EdgeInsets.all(17),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Order',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                                Text(
                                  order.displayCode,
                                  style: AppTextStyles.moneyLarge.copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (isPrepaid) ...[
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_outline,
                                        size: 18,
                                        color: AppColors.success,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'Paid in full · $paymentMethod',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    CurrencyFormatter.format(order.totalAmount),
                                    style: AppTextStyles.moneyLarge.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                ] else ...[
                                  const Text(
                                    'Pay on delivery',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                  Text(
                                    'Due: ${CurrencyFormatter.format(order.totalAmount)}',
                                    style: AppTextStyles.moneyLarge.copyWith(
                                      fontSize: 16,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Inset Notice (locked invoice explanation)
                      AppInset(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: AppColors.faintText,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'The invoice is created when this order is collected in full and handed over. You can share it then.',
                                style: AppTextStyles.hint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Buttons
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              // There's only one place to go back to now — the Orders
              // screen — so a single button covers both "start a new order"
              // and "go look at orders".
              child: PrimaryButton(
                label: 'Continue billing',
                onPressed: () {
                  context.read<CartBloc>().add(ResetSaleEvent());
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
