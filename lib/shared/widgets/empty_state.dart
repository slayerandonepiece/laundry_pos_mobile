import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

class EmptyState extends StatelessWidget {
  final dynamic icon; // Widget or IconData
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    String? description,
    String? subtitle,
    this.actionLabel,
    this.onAction,
  }) : description = description ?? subtitle ?? '';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: icon is Widget
                      ? (icon as Widget)
                      : Icon(
                          icon as IconData,
                          size: 28,
                          color: AppColors.primary,
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(title, style: AppTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              description,
              style: AppTextStyles.hint,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
