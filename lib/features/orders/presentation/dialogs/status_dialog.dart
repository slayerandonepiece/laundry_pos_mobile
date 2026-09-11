import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class StatusDialog extends StatefulWidget {
  final Order order;
  final VoidCallback? onCollectPaymentRequested;

  const StatusDialog({
    super.key,
    required this.order,
    this.onCollectPaymentRequested,
  });

  static Future<void> show(
    BuildContext context, {
    required Order order,
    VoidCallback? onCollectPaymentRequested,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => BlocProvider.value(
        value: context.read<OrdersBloc>(),
        child: StatusDialog(
          order: order,
          onCollectPaymentRequested: onCollectPaymentRequested,
        ),
      ),
    );
  }

  @override
  State<StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<StatusDialog> {
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    final current = widget.order.status.trim().toLowerCase();
    if (current == 'in progress') {
      _selectedStatus = 'In Progress';
    } else if (current == 'ready') {
      _selectedStatus = 'Ready';
    } else {
      _selectedStatus = 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBalanceDue = widget.order.balanceDue > 0;
    final statuses = ['Pending', 'In Progress', 'Ready'];
    final customerName = widget.order.name.isNotEmpty
        ? widget.order.name
        : widget.order.phone;

    final isChanged =
        _selectedStatus.toLowerCase() !=
        widget.order.status.trim().toLowerCase();

    return BlocConsumer<OrdersBloc, OrdersState>(
      listener: (context, state) {
        if (state.actionSuccessMessage != null) {
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
        final isUpdating = state.isUpdatingStatus;

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
                // Title & Order Code
                const Text(
                  'Update status',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.order.orderCode} · $customerName',
                  style: AppTextStyles.hint,
                ),
                const SizedBox(height: 18),

                // Status Options
                ...statuses.map((status) {
                  final isSelected =
                      _selectedStatus.toLowerCase() == status.toLowerCase();
                  final label = status == 'In Progress'
                      ? 'In progress'
                      : status;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: isUpdating
                          ? null
                          : () {
                              setState(() => _selectedStatus = status);
                            },
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        constraints: const BoxConstraints(minHeight: 54),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.selectedSurface
                              : AppColors.surface,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.controlBorder,
                            width: isSelected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontBody,
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.text,
                                ),
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                border: isSelected
                                    ? null
                                    : Border.all(
                                        color: const Color(0xFFC8D2E0),
                                        width: 2,
                                      ),
                              ),
                              child: isSelected
                                  ? const Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // Warning Notice Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningNoticeBg,
                    border: Border.all(color: AppColors.warningBorder),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasBalanceDue
                              ? 'Delivered is not set here — collecting the payment marks the order delivered.'
                              : 'Delivered is not set here — handing over the order marks it delivered.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.warning,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Actions: Cancel & Update
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: isUpdating
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Update',
                        isLoading: isUpdating,
                        onPressed: (isChanged && !isUpdating)
                            ? () {
                                context.read<OrdersBloc>().add(
                                  UpdateOrderStatusEvent(
                                    orderCode: widget.order.orderCode,
                                    nextStatus: _selectedStatus,
                                  ),
                                );
                              }
                            : null,
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
}
