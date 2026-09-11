import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/shell/presentation/store_switcher_dialog.dart';

import 'change_password_screen.dart';

/// The only place logout lives — no other screen carries a sign-out control.
class ProfileScreen extends StatelessWidget {
  final ConnectivityService? connectivityService;
  final LocalCacheService? localCache;
  final SyncEngine? syncEngine;
  final AuthRepository? authRepository;

  const ProfileScreen({
    super.key,
    this.connectivityService,
    this.localCache,
    this.syncEngine,
    this.authRepository,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final connectivity = connectivityService ?? ConnectivityService.instance;
    final cache = localCache ?? LocalCacheService();
    final sync = syncEngine ?? SyncEngine.instance;
    final authRepo = authRepository ?? context.read<AuthRepository>();
    final authBloc = context.read<AuthBloc>();

    // Step 1: No internet guard
    final isOffline = await connectivity.checkIsOffline();
    if (!context.mounted) return;
    if (isOffline) {
      await _showOfflineDialog(context);
      return;
    }

    // Step 2: Unsynced local changes guard
    final pendingQueue = cache.getPendingSyncQueue();
    if (pendingQueue.isNotEmpty) {
      final syncSuccess = await _showPendingSyncDialog(context, sync, cache);
      if (syncSuccess != true) {
        return;
      }
    }

    if (!context.mounted) return;

    // Step 3: Confirm logout dialog
    await _showLogoutConfirmDialog(context, authRepo, authBloc);
  }

  Future<void> _showOfflineDialog(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("You're offline", style: AppTextStyles.h2),
              const SizedBox(height: 8),
              const Text(
                "You're offline. Connect to the internet to log out.",
                style: AppTextStyles.hint,
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: const Text('OK', style: AppTextStyles.button),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showPendingSyncDialog(
    BuildContext context,
    SyncEngine syncEngine,
    LocalCacheService cache,
  ) {
    return showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (dialogContext) {
        bool isSyncing = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: !isSyncing,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Unsynced orders', style: AppTextStyles.h2),
                      const SizedBox(height: 8),
                      const Text(
                        'You have unsynced orders. Please sync them first.',
                        style: AppTextStyles.hint,
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSyncing
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                side: const BorderSide(color: AppColors.controlBorder),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: AppTextStyles.buttonSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSyncing
                                  ? null
                                  : () async {
                                      setState(() {
                                        isSyncing = true;
                                        errorMessage = null;
                                      });
                                      try {
                                        await syncEngine.retryNow();
                                      } catch (_) {}
                                      final remaining = cache.getPendingSyncQueue().length;
                                      if (remaining > 0) {
                                        if (dialogContext.mounted) {
                                          setState(() {
                                            isSyncing = false;
                                            errorMessage =
                                                'Sync failed. Check your connection and try again.';
                                          });
                                        }
                                      } else {
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop(true);
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              child: isSyncing
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text('Syncing…', style: AppTextStyles.button),
                                      ],
                                    )
                                  : const Text('Sync now', style: AppTextStyles.button),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLogoutConfirmDialog(
    BuildContext context,
    AuthRepository authRepo,
    AuthBloc authBloc,
  ) {
    return showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (dialogContext) {
        bool isLoggingOut = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: !isLoggingOut,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Log out?', style: AppTextStyles.h2),
                      const SizedBox(height: 8),
                      const Text(
                        'You\'ll need to sign in again to take sales or manage orders.',
                        style: AppTextStyles.hint,
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isLoggingOut
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                side: const BorderSide(color: AppColors.controlBorder),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: AppTextStyles.buttonSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isLoggingOut
                                  ? null
                                  : () async {
                                      setState(() {
                                        isLoggingOut = true;
                                        errorMessage = null;
                                      });
                                      try {
                                        await authRepo.logout();
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                        authBloc.add(LogoutRequestedEvent());
                                      } catch (_) {
                                        if (dialogContext.mounted) {
                                          setState(() {
                                            isLoggingOut = false;
                                            errorMessage =
                                                "Couldn't log out. Please try again.";
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: AppColors.danger,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              child: isLoggingOut
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Log out', style: AppTextStyles.button),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isAuthenticated = authState is AuthenticatedState;
    final name = isAuthenticated ? authState.user.displayName : '';
    final roleLabel = isAuthenticated && authState.isOwner ? 'Owner' : 'Employee';
    final storeName = isAuthenticated ? authState.currentStore.storeName : '';
    final hasMultipleStores = isAuthenticated && authState.hasMultipleStores;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is! AuthenticatedState && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Profile', style: AppTextStyles.h3),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.border, height: 1),
          ),
        ),
        body: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(name, style: AppTextStyles.h3),
            const SizedBox(height: 3),
            Text('$roleLabel · $storeName', style: AppTextStyles.hint),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border, height: 1),
            if (hasMultipleStores)
              _ProfileRow(
                icon: Icons.store_outlined,
                label: 'Switch store',
                onTap: () => StoreSwitcherDialog.show(context),
              ),
            _ProfileRow(
              icon: Icons.lock_outline,
              label: 'Change password',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
            ),
            const Spacer(),
            const Divider(color: AppColors.border, height: 1),
            _ProfileRow(
              icon: Icons.logout,
              label: 'Log out',
              labelColor: AppColors.danger,
              iconColor: AppColors.danger,
              onTap: () => _confirmLogout(context),
            ),
            const SizedBox(height: 8),
            const Text('v1.0.0', style: AppTextStyles.hint, textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final Color? iconColor;

  const _ProfileRow({required this.icon, required this.label, required this.onTap, this.labelColor, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 19, color: iconColor ?? AppColors.mutedText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? AppColors.text,
                ),
              ),
            ),
            if (iconColor == null) const Icon(Icons.chevron_right, size: 18, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}
