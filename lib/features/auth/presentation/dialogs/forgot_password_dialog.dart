import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_inset.dart';

class ForgotPasswordDialog extends StatelessWidget {
  final String? storePhone;

  const ForgotPasswordDialog({super.key, this.storePhone});

  static Future<void> show(BuildContext context, {String? storePhone}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => ForgotPasswordDialog(storePhone: storePhone),
    );
  }

  void _callOwner(BuildContext context) async {
    if (storePhone == null || storePhone!.isEmpty) return;
    final uri = Uri.parse('tel:$storePhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Forgot password?',
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Description
            const Text(
              'Your store owner can reset your password for you from the Staff settings.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.mutedText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Inset callout
            AppInset(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline,
                      size: 17,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'They will provide a temporary password. When you sign in with it, the app will ask you to choose a new password.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedText,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            if (storePhone != null && storePhone!.isNotEmpty) ...[
              PrimaryButton(
                label: 'Call store owner',
                icon: const Icon(Icons.call, size: 18, color: Colors.white),
                onPressed: () => _callOwner(context),
              ),
              const SizedBox(height: 10),
            ],
            SecondaryButton(
              label: 'Got it',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
