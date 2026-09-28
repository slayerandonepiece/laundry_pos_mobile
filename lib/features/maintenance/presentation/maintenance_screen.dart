import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/firebase_service.dart';

/// Full-screen, non-dismissible maintenance mode blocking screen.
class MaintenanceScreen extends StatefulWidget {
  final String? message;
  final String? eta;
  final Future<void> Function()? onCheckAgain;

  const MaintenanceScreen({
    super.key,
    this.message,
    this.eta,
    this.onCheckAgain,
  });

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _isChecking = false;

  Future<void> _handleCheckAgain() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      if (widget.onCheckAgain != null) {
        await widget.onCheckAgain!();
      } else {
        await FirebaseService.refreshRemoteConfig();
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveMessage = widget.message?.trim().isNotEmpty == true
        ? widget.message!
        : FirebaseService.maintenanceMessage;

    final effectiveEta = widget.eta ?? FirebaseService.maintenanceEta;
    final showEta = effectiveEta.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.brandDeepHydro,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Circular icon badge
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.brandCrispMint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.build_rounded,
                      size: 38,
                      color: AppColors.brandDeepHydro,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Heading
                  const Text(
                    'Down for maintenance.',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Body text (sourced from Remote Config)
                  Text(
                    effectiveMessage,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      color: Color(0xD9FFFFFF), // 85% white
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // ETA caption — rendered ONLY if non-empty; no hardcoded fallback text
                  if (showEta) ...[
                    const SizedBox(height: 16),
                    Text(
                      effectiveEta.trim(),
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: Colors.white54,
                        letterSpacing: 0.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 36),

                  // "Check again" button
                  OutlinedButton(
                    onPressed: _isChecking ? null : _handleCheckAgain,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandCrispMint,
                      side: const BorderSide(
                        color: AppColors.brandCrispMint,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brandCrispMint,
                            ),
                          )
                        : const Text(
                            'Check again',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
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
