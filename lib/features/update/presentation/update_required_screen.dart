import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_environment.dart';
import '../../../shared/widgets/app_button.dart';

/// What happened when the user asked to update.
enum UpdateAttempt { opened, offline, failed }

/// How long to wait for the App Store before giving up and offering a retry.
const Duration kUpdateAttemptTimeout = Duration(seconds: 10);

/// Full-screen, non-dismissible blocker for a mandatory update. [onUpdate]
/// checks the connection, then opens the App Store, and reports what happened.
/// Anything but [UpdateAttempt.opened] shows a short hint and the screen
/// stays, so the user can simply try again.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.onUpdate});

  final Future<UpdateAttempt> Function() onUpdate;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _busy = false;
  UpdateAttempt _result = UpdateAttempt.opened;

  Future<void> _update() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = UpdateAttempt.opened;
    });
    var result = UpdateAttempt.failed;
    try {
      result = await widget.onUpdate().timeout(
        kUpdateAttemptTimeout,
        onTimeout: () => UpdateAttempt.failed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _result = result;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update required',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This version of ${AppEnvironmentConfig.appName} is no '
                    'longer supported. Update to keep taking orders.',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      color: AppColors.mutedText,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    key: const Key('update_required_button'),
                    label: 'Update now',
                    height: AppButtonHeight.main,
                    isLoading: _busy,
                    onPressed: _update,
                  ),
                  if (_result != UpdateAttempt.opened) ...[
                    const SizedBox(height: 14),
                    Text(
                      _result == UpdateAttempt.offline
                          ? 'No internet connection. Connect and try again.'
                          : "Couldn't open the App Store. Try again.",
                      key: const Key('update_required_error'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: AppColors.mutedText,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Your orders and data stay safe.',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
