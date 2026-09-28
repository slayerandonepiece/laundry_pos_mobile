import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';
import 'app_inset.dart';

class BlockedScreen extends StatelessWidget {
  final String? reason; // 'membership_inactive' | 'store_locked' | 'store_archived' | 'payment_lapsed' | 'no_outlet_assigned'
  final bool isOwner;
  final String? paidThroughDate;
  final String? ownerPhone;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;
  final int? pendingCount;

  const BlockedScreen({
    super.key,
    required this.reason,
    required this.isOwner,
    this.paidThroughDate,
    this.ownerPhone,
    required this.onRetry,
    required this.onSignOut,
    this.pendingCount,
  });

  void _callOwner(BuildContext context) async {
    if (ownerPhone == null || ownerPhone!.isEmpty) return;
    final uri = Uri.parse('tel:$ownerPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Access blocked';
    String description;
    Widget? extraNotice;

    final normReason = reason?.toLowerCase().trim() ?? '';

    if (normReason == 'membership_inactive') {
      title = 'Account inactive';
      description = 'Your store access has been deactivated. Please contact your store owner to reactivate your login.';
    } else if (normReason == 'store_locked') {
      title = 'Store locked';
      description = isOwner
          ? 'This store has been locked by platform administration. Please contact support.'
          : 'Store access is temporarily locked. Please check with your store owner.';
    } else if (normReason == 'no_outlet_assigned') {
      title = 'No outlet assigned';
      description = "Your account isn't assigned to an outlet yet, so orders can't be loaded. Ask your store owner to assign you to one, then sign in again.";
    } else if (normReason == 'store_archived') {
      title = 'Store archived';
      description =
          'This store has been archived. All access has been discontinued.';
    } else if (normReason == 'payment_lapsed') {
      title = isOwner ? 'Plan expired' : 'Access paused';
      if (isOwner) {
        description =
            'Your subscription expired on ${paidThroughDate ?? "recently"}. Access will resume automatically once payment is renewed.';
        extraNotice = Container(
          decoration: BoxDecoration(
            color: AppColors.warningBg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.warningBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Access resumes immediately after renewal',
                  style: AppTextStyles.hint.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Staff never sees figures or dates (Non-negotiable #4)
        description = 'Store operations are paused. Please check with your store owner to resume access.';
      }
    } else {
      description = 'You do not have access to this store. Please contact your store administrator.';
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.dangerBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 32,
                    color: AppColors.danger,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: AppTextStyles.h1, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                description,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedText,
                ),
                textAlign: TextAlign.center,
              ),
              if (extraNotice != null) ...[
                const SizedBox(height: 20),
                extraNotice,
              ],
              if (pendingCount != null && pendingCount! > 0) ...[
                const SizedBox(height: 16),
                AppInset(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_rounded,
                        size: 20,
                        color: AppColors.mutedText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$pendingCount ${pendingCount == 1 ? "action" : "actions"} saved on this device haven\'t synced yet. They\'ll go through automatically once your access is restored.',
                          style: AppTextStyles.hint.copyWith(
                            color: AppColors.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (!isOwner && ownerPhone != null && ownerPhone!.isNotEmpty) ...[
                PrimaryButton(
                  label: 'Call store owner',
                  icon: const Icon(Icons.call, size: 18, color: Colors.white),
                  onPressed: () => _callOwner(context),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(label: 'Try again', onPressed: onRetry),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Sign out', onPressed: onSignOut),
            ],
          ),
        ),
      ),
    );
  }
}
