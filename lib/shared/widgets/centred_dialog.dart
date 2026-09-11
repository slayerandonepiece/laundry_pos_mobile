import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

class CentredDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? content;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final bool isDestructive;
  final bool isLoading;

  const CentredDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.content,
    this.confirmLabel = 'Confirm',
    this.onConfirm,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.isDestructive = false,
    this.isLoading = false,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (context) => child,
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
            Text(title, style: AppTextStyles.h2),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: AppTextStyles.hint),
            ],
            if (content != null) ...[const SizedBox(height: 18), content!],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: cancelLabel,
                    height: 48,
                    onPressed: () {
                      if (onCancel != null) {
                        onCancel!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
                if (onConfirm != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: confirmLabel,
                      height: 48,
                      isLoading: isLoading,
                      backgroundColor: isDestructive
                          ? AppColors.danger
                          : AppColors.primary,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
