import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_inset.dart';
import '../data/auth_repository.dart';

/// Shown after sign-in while the account is scheduled for deletion. The only
/// choices are to restore it or to leave it scheduled and sign out.
class AccountRestoreScreen extends StatefulWidget {
  final String scheduledFor;
  final bool isOwner;
  final AuthRepository authRepository;
  final VoidCallback onRestored;
  final VoidCallback onSignOut;

  const AccountRestoreScreen({
    super.key,
    required this.scheduledFor,
    required this.isOwner,
    required this.authRepository,
    required this.onRestored,
    required this.onSignOut,
  });

  @override
  State<AccountRestoreScreen> createState() => _AccountRestoreScreenState();
}

class _AccountRestoreScreenState extends State<AccountRestoreScreen> {
  bool _restoring = false;
  String? _error;

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await widget.authRepository.restoreAccount();
      if (!mounted) return;
      widget.onRestored();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = 'Could not restore your account. Please try again.';
      });
    }
  }

  int? _daysLeft() {
    final date = DateFormatter.parseCalendarDate(widget.scheduledFor);
    if (date == null) return null;
    final left = date.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft();
    final date = DateFormatter.formatFull(widget.scheduledFor);
    final what = widget.isOwner
        ? 'Your store and all its data'
        : 'Your mobile number';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.warningBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule,
                    size: 32,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your account is scheduled for deletion',
                style: AppTextStyles.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$what will be permanently deleted on $date.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedText,
                ),
                textAlign: TextAlign.center,
              ),
              if (days != null) ...[
                const SizedBox(height: 16),
                Text(
                  '$days ${days == 1 ? 'day' : 'days'} left to restore',
                  style: AppTextStyles.hint.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              AppInset(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  widget.isOwner
                      ? 'Restore now and everything comes back as you left it: orders, customers, staff, and settings.'
                      : 'Restore now and you can use the app again as before.',
                  style: AppTextStyles.hint.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.danger,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              PrimaryButton(
                label: 'Restore my account',
                isLoading: _restoring,
                loadingLabel: 'Restoring…',
                onPressed: _restoring ? null : _restore,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Continue with deletion',
                onPressed: _restoring ? null : widget.onSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
