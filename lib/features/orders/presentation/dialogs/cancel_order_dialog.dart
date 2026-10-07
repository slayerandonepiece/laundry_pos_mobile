import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';

/// Owner-only. Asks for a reason (3 to 500 characters) before cancelling an
/// order that has not been delivered. Money already collected is not refunded.
class CancelOrderDialog extends StatefulWidget {
  final Order order;

  const CancelOrderDialog({super.key, required this.order});

  static Future<void> show(BuildContext context, {required Order order}) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<OrdersBloc>(),
        child: CancelOrderDialog(order: order),
      ),
    );
  }

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().length >= 3;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cancel ${widget.order.displayCode}?',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Money already collected is not refunded here. This cannot be undone.',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              maxLength: 500,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Why is this order being cancelled?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Keep order',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Cancel order',
                    onPressed: valid
                        ? () {
                            context.read<OrdersBloc>().add(
                              CancelOrderEvent(
                                orderCode: widget.order.orderCode,
                                reason: _reason.text.trim(),
                              ),
                            );
                            Navigator.pop(context);
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
  }
}
