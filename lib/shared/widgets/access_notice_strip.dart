import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../features/auth/data/models/user_model.dart';

/// A non-blocking notice about the organization's plan, shown above the work
/// screens. Mirrors the web workspace: the trial strip and the pre-expiry
/// warning. Owners get the dates; employees never see billing specifics.
class AccessNotice {
  final String message;
  final bool isWarning;

  const AccessNotice(this.message, {this.isWarning = false});
}

AccessNotice? resolveAccessNotice(
  StoreSummary? store, {
  required bool isOwner,
}) {
  if (store == null || store.isBlocked) return null;

  switch (store.subscriptionState?.toUpperCase()) {
    case 'TRIAL':
    case 'TRIAL_ENDING':
      final ends = _formatDate(store.trialEndsAt);
      return AccessNotice(
        ends == null ? 'Free trial' : 'Free trial · Ends $ends',
        isWarning: store.subscriptionState?.toUpperCase() == 'TRIAL_ENDING',
      );
    case 'SUBSCRIPTION_ENDING':
      if (!isOwner) {
        return const AccessNotice(
          'Billing is due soon for this store. Please check with your store owner.',
          isWarning: true,
        );
      }
      final renews = _formatDate(store.paidThroughDate);
      return AccessNotice(
        renews == null
            ? 'Your subscription is due for renewal soon. Renew soon to avoid losing access to this store.'
            : 'Your subscription is due for renewal on $renews. Renew soon to avoid losing access to this store.',
        isWarning: true,
      );
  }
  return null;
}

String? _formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : DateFormat('d MMM yyyy').format(parsed);
}

class AccessNoticeStrip extends StatelessWidget {
  final AccessNotice notice;

  const AccessNoticeStrip({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final color = notice.isWarning ? AppColors.warning : AppColors.neutralText;
    return Material(
      color: notice.isWarning ? AppColors.warningNoticeBg : AppColors.neutralBg,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: notice.isWarning
                    ? AppColors.warningBorder
                    : AppColors.controlBorder,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                notice.isWarning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notice.message,
                  key: const Key('access_notice_message'),
                  style: AppTextStyles.hint.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
