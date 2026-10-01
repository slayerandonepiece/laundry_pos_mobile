import 'package:myshop/shared/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';

enum CheckpointState { pending, active, done, error }

class LogoutDialog extends StatefulWidget {
  final OrdersRepository? ordersRepository;
  final LocalCacheService? localCache;
  final AuthBloc? authBloc;

  const LogoutDialog({
    super.key,
    this.ordersRepository,
    this.localCache,
    this.authBloc,
  });

  static Future<void> show(
    BuildContext context, {
    OrdersRepository? ordersRepository,
    LocalCacheService? localCache,
    AuthBloc? authBloc,
  }) {
    return showDialog(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: 0.42),
      builder: (_) => LogoutDialog(
        ordersRepository: ordersRepository,
        localCache: localCache,
        authBloc: authBloc,
      ),
    );
  }

  @override
  State<LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<LogoutDialog> {
  late final LocalCacheService _localCache;
  late final AuthBloc _authBloc;

  int _pendingCount = 0;
  bool _isSyncing = false;
  bool _syncFailed = false;

  CheckpointState _step1 = CheckpointState.pending;
  CheckpointState _step2 = CheckpointState.pending;
  CheckpointState _step3 = CheckpointState.pending;

  @override
  void initState() {
    super.initState();
    // Sync itself is no longer driven from a repository reference held
    // here — it always goes through SyncEngine.instance (see
    // _handleLogoutAndSync) so it shares SyncEngine's single-flight guard
    // instead of racing any sync already in flight. widget.ordersRepository
    // is kept only for API compatibility; tests should inject via
    // SyncEngine.instance instead.
    _localCache = widget.localCache ?? LocalCacheService();
    _authBloc = widget.authBloc ?? context.read<AuthBloc>();

    final currentStoreId = _localCache.getActiveStoreId();
    final queue = _localCache.getPendingSyncQueue();
    _pendingCount = queue
        .where((a) => a['storeId'] == null || a['storeId'] == currentStoreId)
        .length;
  }

  Future<void> _handleLogoutAndSync() async {
    setState(() {
      _isSyncing = true;
      _syncFailed = false;
      _step1 = CheckpointState.active;
      _step2 = CheckpointState.pending;
      _step3 = CheckpointState.pending;
    });

    try {
      // Checkpoints 1 & 2: push + pull, both via SyncEngine — never call
      // OrdersRepository.processPendingSyncQueue()/syncOrdersDelta() directly
      // from UI code. SyncEngine owns the single-flight guard; a sync
      // already in flight from a recent action (fire-and-forget after any
      // status/payment update) can otherwise race a direct call here, and
      // both would independently push the same queued action to the server
      // — the backend isn't reliably idempotent for that, so it lands twice.
      await SyncEngine.instance.retryNow();

      final currentStoreId = _localCache.getActiveStoreId();
      final remaining = _localCache
          .getPendingSyncQueue()
          .where((a) => a['storeId'] == null || a['storeId'] == currentStoreId)
          .length;

      if (remaining > 0) {
        if (!mounted) return;
        setState(() {
          _step1 = CheckpointState.error;
          _isSyncing = false;
          _syncFailed = true;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _step1 = CheckpointState.done;
        _step2 = CheckpointState.done;
        _step3 = CheckpointState.active;
      });

      // Checkpoint 3: Complete logout
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _step3 = CheckpointState.done;
      });

      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _authBloc.add(LogoutRequestedEvent());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step1 = CheckpointState.error;
        _isSyncing = false;
        _syncFailed = true;
      });
    }
  }

  void _performDirectLogout() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _authBloc.add(LogoutRequestedEvent());
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingOrders = _pendingCount > 0;

    return PopScope(
      canPop: !_isSyncing,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(6, 27, 58, 0.28),
                blurRadius: 44,
                offset: Offset(0, 18),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hasPendingOrders ? 'Log out & sync?' : 'Log out?',
                style: AppTextStyles.h2,
              ),
              const SizedBox(height: 8),
              Text(
                hasPendingOrders
                    ? 'You have $_pendingCount unsynced change${_pendingCount > 1 ? 's' : ''} saved locally. Sync now to ensure your store data is updated.'
                    : 'You\'ll need to sign in again to take sales or manage orders.',
                style: AppTextStyles.hint,
              ),

              // Pending warning badge if unsynced changes exist
              if (hasPendingOrders && !_isSyncing && !_syncFailed) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 20,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$_pendingCount unsynced order${_pendingCount > 1 ? 's' : ''}/update${_pendingCount > 1 ? 's' : ''} pending sync',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Checkpoints progression when syncing
              if (_isSyncing || _syncFailed) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.inset,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildCheckpointRow(
                        title: 'Syncing pending orders to server',
                        state: _step1,
                      ),
                      const SizedBox(height: 10),
                      _buildCheckpointRow(
                        title: 'Pulling latest store data',
                        state: _step2,
                      ),
                      const SizedBox(height: 10),
                      _buildCheckpointRow(title: 'Signing out', state: _step3),
                    ],
                  ),
                ),
                if (_syncFailed) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Unable to reach server. Changes remain saved locally on this device.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 22),

              // Action buttons
              if (_isSyncing) ...[
                PrimaryButton(
                  label: 'Syncing & Logging out...',
                  height: AppButtonHeight.inline,
                  onPressed: null,
                  isLoading: true,
                  loadingLabel: 'Syncing & Logging out...',
                ),
              ] else if (_syncFailed) ...[
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Log out anyway',
                        height: AppButtonHeight.inline,
                        onPressed: _performDirectLogout,
                        textColor: AppColors.danger,
                        borderColor: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Retry Sync',
                        height: AppButtonHeight.inline,
                        onPressed: _handleLogoutAndSync,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        height: AppButtonHeight.inline,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: hasPendingOrders ? 'Logout & Sync' : 'Log out',
                        height: AppButtonHeight.inline,
                        onPressed: hasPendingOrders
                            ? _handleLogoutAndSync
                            : _performDirectLogout,
                        backgroundColor: hasPendingOrders
                            ? AppColors.primary
                            : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckpointRow({
    required String title,
    required CheckpointState state,
  }) {
    Widget indicator;
    Color textColor;

    switch (state) {
      case CheckpointState.pending:
        indicator = Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.controlBorder, width: 1.5),
          ),
        );
        textColor = AppColors.mutedText;
        break;
      case CheckpointState.active:
        indicator = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        );
        textColor = AppColors.text;
        break;
      case CheckpointState.done:
        indicator = Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.successBg,
          ),
          child: const Center(
            child: Icon(Icons.check, size: 11, color: AppColors.success),
          ),
        );
        textColor = AppColors.text;
        break;
      case CheckpointState.error:
        indicator = Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.dangerBg,
          ),
          child: const Center(
            child: Icon(Icons.close, size: 11, color: AppColors.danger),
          ),
        );
        textColor = AppColors.danger;
        break;
    }

    return Row(
      children: [
        indicator,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 13,
              fontWeight: state == CheckpointState.active
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
