import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../shared/widgets/app_button.dart';

/// Confirms before backing out of the new-order flow once the customer has
/// added items (or reached checkout) — prevents an accidental back-swipe or
/// tap from silently dropping a half-built order.
class DiscardOrderDialog extends StatelessWidget {
  final VoidCallback onDiscard;

  const DiscardOrderDialog({super.key, required this.onDiscard});

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDiscard,
  }) {
    return showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => DiscardOrderDialog(onDiscard: onDiscard),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(6, 27, 58, 0.28),
              blurRadius: 44,
              offset: Offset(0, 18),
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(Icons.close, size: 26, color: AppColors.danger),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Discard this order?', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            const Text(
              'The services and customer details you\'ve entered will be lost.',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Keep going',
                    height: AppButtonHeight.inline,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Discard',
                    height: AppButtonHeight.inline,
                    backgroundColor: AppColors.danger,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDiscard();
                    },
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
