import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/status_pill.dart';

class OrderActivityScreen extends StatelessWidget {
  final Order order;

  const OrderActivityScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order activity',
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${order.orderCode} · ${order.name.isNotEmpty ? order.name : order.phone}',
              style: AppTextStyles.hint,
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Expected delivery card
          AppCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Expected delivery',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedText,
                      ),
                    ),
                    Text(
                      DateFormatter.formatFullDate(order.due),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: AppColors.border, height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Commitment',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontBody,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedText,
                      ),
                    ),
                    _buildCommitmentPill(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),

          // Care instructions card
          if (order.notes.isNotEmpty) ...[
            AppCard(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Care instructions',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order.notes,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 13,
                      color: AppColors.mutedText,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
          ],

          // Status history card
          AppCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status history',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                if (order.history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No status transitions recorded yet.',
                      style: AppTextStyles.hint,
                    ),
                  )
                else
                  ...List.generate(order.history.length, (index) {
                    final item = order.history[index];
                    final isFirst = index == 0;
                    final isLast = index == order.history.length - 1;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeline dot and connecting line
                        Column(
                          children: [
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFirst
                                    ? AppColors.primary
                                    : AppColors.controlBorder,
                              ),
                            ),
                            if (!isLast)
                              Container(
                                width: 2,
                                height: 40,
                                color: AppColors.border,
                              ),
                          ],
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.status,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontBody,
                                    fontSize: 13.5,
                                    fontWeight: isFirst
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${DateFormatter.formatDateTime(item.timestamp)}${item.actorName.isNotEmpty ? " · ${item.actorName}" : ""}',
                                  style: AppTextStyles.hint,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitmentPill() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(
      order.dueDateTime.year,
      order.dueDateTime.month,
      order.dueDateTime.day,
    );

    if (order.isDelivered) {
      return const StatusPill(
        label: 'Delivered',
        variant: PillVariant.delivered,
      );
    }

    if (dueDay.isBefore(today)) {
      final days = today.difference(dueDay).inDays;
      return StatusPill(
        label: 'Overdue · $days ${days == 1 ? "day" : "days"}',
        variant: PillVariant.balanceDue,
      );
    } else if (dueDay.isAtSameMomentAs(today)) {
      return const StatusPill(label: 'Due today', variant: PillVariant.ready);
    } else {
      final days = dueDay.difference(today).inDays;
      return StatusPill(
        label: 'In $days ${days == 1 ? "day" : "days"}',
        variant: PillVariant.neutral,
      );
    }
  }
}
