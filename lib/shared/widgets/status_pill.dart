import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';

enum PillVariant {
  pending,
  inProgress,
  ready,
  delivered,
  paid,
  danger,
  balanceDue,
  neutral,
}

class StatusPill extends StatelessWidget {
  final String label;
  final PillVariant variant;
  final Widget? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.variant,
    this.icon,
  });

  factory StatusPill.fromStatus(String status) {
    final lower = status.toLowerCase().trim();
    if (lower == 'pending') {
      return StatusPill(label: 'Pending', variant: PillVariant.pending);
    } else if (lower == 'in progress') {
      return StatusPill(label: 'In progress', variant: PillVariant.inProgress);
    } else if (lower == 'ready') {
      return StatusPill(label: 'Ready', variant: PillVariant.ready);
    } else if (lower == 'delivered' || lower == 'completed') {
      return StatusPill(label: 'Delivered', variant: PillVariant.delivered);
    } else if (lower.contains('paid')) {
      return StatusPill(label: status, variant: PillVariant.paid);
    } else if (lower.contains('overdue') || lower.contains('due')) {
      return StatusPill(label: status, variant: PillVariant.danger);
    }
    return StatusPill(label: status, variant: PillVariant.neutral);
  }

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color bgColor;

    switch (variant) {
      case PillVariant.pending:
      case PillVariant.neutral:
        textColor = AppColors.neutralText;
        bgColor = AppColors.neutralBg;
        break;
      case PillVariant.inProgress:
        textColor = AppColors.primary;
        bgColor = AppColors.primaryTint;
        break;
      case PillVariant.ready:
        textColor = AppColors.warning;
        bgColor = AppColors.warningBg;
        break;
      case PillVariant.delivered:
      case PillVariant.paid:
        textColor = AppColors.success;
        bgColor = AppColors.successBg;
        break;
      case PillVariant.danger:
      case PillVariant.balanceDue:
        textColor = AppColors.danger;
        bgColor = AppColors.dangerBg;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 5)],
          Text(label, style: AppTextStyles.pill.copyWith(color: textColor)),
        ],
      ),
    );
  }
}
