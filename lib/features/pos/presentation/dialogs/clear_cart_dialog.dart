import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_button.dart';

class ClearCartDialog extends StatelessWidget {
  final int itemCount;
  final int totalAmount;
  final VoidCallback onClear;

  const ClearCartDialog({
    super.key,
    required this.itemCount,
    required this.totalAmount,
    required this.onClear,
  });

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
              alignment: Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(
                    Icons.delete_outline,
                    size: 26,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Clear this sale?', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
              '$itemCount services worth ${CurrencyFormatter.format(totalAmount)} will be removed. The customer details you entered are cleared too.',
              style: AppTextStyles.hint,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Keep it',
                    height: 48,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Clear',
                    height: 48,
                    backgroundColor: AppColors.danger,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onClear();
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
