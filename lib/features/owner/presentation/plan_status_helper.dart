import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../auth/data/models/user_model.dart';

enum PlanStatusTone { neutral, warning, success, unavailable }

class PlanStatusInfo {
  final PlanStatusTone tone;
  final String? badgeLabel;
  final String title;
  final String subtitle;
  final Color bgColor;
  final Color textColor;
  final Color borderColor;
  final IconData icon;

  const PlanStatusInfo({
    required this.tone,
    this.badgeLabel,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.textColor,
    required this.borderColor,
    required this.icon,
  });

  bool get isWarning => tone == PlanStatusTone.warning;
  bool get isSuccess => tone == PlanStatusTone.success;
  bool get isNeutral => tone == PlanStatusTone.neutral;
  bool get isUnavailable => tone == PlanStatusTone.unavailable;
}

PlanStatusInfo resolvePlanStatus(StoreSummary? store) {
  if (store == null) {
    return const PlanStatusInfo(
      tone: PlanStatusTone.unavailable,
      badgeLabel: null,
      title: 'Plan status unavailable',
      subtitle: "Plan status isn't available right now.",
      bgColor: AppColors.surface,
      textColor: AppColors.text,
      borderColor: AppColors.controlBorder,
      icon: Icons.info_outline,
    );
  }

  final subState = store.subscriptionState?.toUpperCase();

  if (subState == 'TRIAL') {
    final ends = store.trialEndsAt;
    final subtitle = (ends != null && ends.isNotEmpty)
        ? 'Trial ends on $ends'
        : 'Your plan is on trial';
    return PlanStatusInfo(
      tone: PlanStatusTone.neutral,
      badgeLabel: 'Trial',
      title: 'Trial',
      subtitle: subtitle,
      bgColor: AppColors.neutralBg,
      textColor: AppColors.neutralText,
      borderColor: AppColors.controlBorder,
      icon: Icons.info_outline,
    );
  }

  if (subState == 'TRIAL_ENDING') {
    final ends = store.trialEndsAt;
    final dateText = (ends != null && ends.isNotEmpty)
        ? 'Trial ends on $ends.'
        : 'Your trial is ending.';
    return PlanStatusInfo(
      tone: PlanStatusTone.warning,
      badgeLabel: 'Trial ending',
      title: 'Trial ending',
      subtitle: 'Please keep payment updated. $dateText',
      bgColor: AppColors.warningNoticeBg,
      textColor: AppColors.warning,
      borderColor: AppColors.warningBorder,
      icon: Icons.warning_amber_rounded,
    );
  }

  if (subState == 'SUBSCRIPTION_ENDING') {
    final renews = store.paidThroughDate;
    final dateText = (renews != null && renews.isNotEmpty)
        ? 'Renews on $renews.'
        : 'Renewal is due soon.';
    return PlanStatusInfo(
      tone: PlanStatusTone.warning,
      badgeLabel: 'Renews soon',
      title: 'Your plan renews soon',
      subtitle: 'Please keep payment updated. $dateText',
      bgColor: AppColors.warningNoticeBg,
      textColor: AppColors.warning,
      borderColor: AppColors.warningBorder,
      icon: Icons.warning_amber_rounded,
    );
  }

  if (subState == 'RESTRICTED') {
    return const PlanStatusInfo(
      tone: PlanStatusTone.unavailable,
      badgeLabel: null,
      title: 'Plan status unavailable',
      subtitle: "Plan status isn't available right now.",
      bgColor: AppColors.surface,
      textColor: AppColors.text,
      borderColor: AppColors.controlBorder,
      icon: Icons.info_outline,
    );
  }

  // ACTIVE or subscriptionState absent/null -> fallback to paidThroughDate logic
  final paidThroughDate = store.paidThroughDate;
  if (paidThroughDate == null) {
    return const PlanStatusInfo(
      tone: PlanStatusTone.unavailable,
      badgeLabel: null,
      title: 'Plan status unavailable',
      subtitle: "Plan status isn't available right now.",
      bgColor: AppColors.surface,
      textColor: AppColors.text,
      borderColor: AppColors.controlBorder,
      icon: Icons.info_outline,
    );
  }

  final parsedDate = DateTime.tryParse(paidThroughDate);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final isNearOrPast =
      parsedDate == null || parsedDate.difference(today).inDays <= 7;

  if (isNearOrPast) {
    return PlanStatusInfo(
      tone: PlanStatusTone.warning,
      badgeLabel: 'Renews soon',
      title: 'Your plan renews soon',
      subtitle: 'Please keep payment updated. Renews on $paidThroughDate.',
      bgColor: AppColors.warningNoticeBg,
      textColor: AppColors.warning,
      borderColor: AppColors.warningBorder,
      icon: Icons.warning_amber_rounded,
    );
  }

  return PlanStatusInfo(
    tone: PlanStatusTone.success,
    badgeLabel: 'Active plan',
    title: 'Your plan is active',
    subtitle: 'Renews on $paidThroughDate',
    bgColor: AppColors.successBg,
    textColor: AppColors.success,
    borderColor: AppColors.success.withValues(alpha: 0.3),
    icon: Icons.check_circle_outline,
  );
}
