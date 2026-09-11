import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/sync/sync_manager.dart';

class SyncStatusBar extends StatefulWidget {
  final VoidCallback? onSyncNow;

  const SyncStatusBar({super.key, this.onSyncNow});

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  bool _showSyncedBanner = false;

  @override
  void initState() {
    super.initState();
    SyncManager.instance.addListener(_handleSyncChange);
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_handleSyncChange);
    super.dispose();
  }

  void _handleSyncChange() {
    final state = SyncManager.instance.value;
    if (state.status == SyncStatus.synced) {
      if (mounted) {
        setState(() => _showSyncedBanner = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _showSyncedBanner = false);
          }
        });
      }
    } else {
      if (mounted && _showSyncedBanner) {
        setState(() => _showSyncedBanner = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncState>(
      valueListenable: SyncManager.instance,
      builder: (context, state, _) {
        final isSyncing = state.isSyncing;
        final isOffline = state.isOffline;
        final isPendingOnline = state.isPendingOnline;
        final isError = state.hasError;
        final isSyncPaused = state.isSyncPaused;
        final isVisible =
            isSyncing ||
            isOffline ||
            isPendingOnline ||
            isError ||
            isSyncPaused ||
            _showSyncedBanner;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: isVisible ? 36.0 : 0.0,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isSyncing
                ? AppColors.primaryTint
                : (isOffline
                      ? AppColors.neutralBg
                      : (isPendingOnline
                            ? AppColors.warningNoticeBg
                            : ((isError || isSyncPaused)
                                  ? AppColors.dangerBg
                                  : AppColors.successBg))),
            border: Border(
              bottom: BorderSide(
                color: isSyncing
                    ? const Color(0xFFC7DCFC)
                    : (isOffline
                          ? AppColors.controlBorder
                          : (isPendingOnline
                                ? AppColors.warningBorder
                                : ((isError || isSyncPaused)
                                      ? AppColors.dangerBorder
                                      : const Color(0xFFB7E4CF)))),
                width: 1,
              ),
            ),
          ),
          child: isVisible
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            if (isSyncing) ...[
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.message ?? 'Syncing data...',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else if (isOffline) ...[
                              const Icon(
                                Icons.cloud_off_rounded,
                                size: 15,
                                color: AppColors.mutedText,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Internet is disconnected. Orders will be punched offline.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.mutedText,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else if (isPendingOnline) ...[
                              const Icon(
                                Icons.cloud_off_rounded,
                                size: 15,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.message ??
                                      (state.pendingCount > 0
                                          ? '${state.pendingCount} ${state.pendingCount == 1 ? "change" : "changes"} pending'
                                          : 'Changes pending'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.warning,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.onSyncNow != null)
                                InkWell(
                                  onTap: widget.onSyncNow,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Sync now',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                            ] else if (isSyncPaused) ...[
                              const Icon(
                                Icons.sync_problem_rounded,
                                size: 15,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.message ?? 'Sync paused — tap to retry',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.danger,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.onSyncNow != null)
                                InkWell(
                                  onTap: widget.onSyncNow,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Retry',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.danger,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                            ] else if (isError) ...[
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 15,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.message ?? 'Sync failed',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.danger,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 15,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'All data synced',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (isSyncing)
                      const LinearProgressIndicator(
                        minHeight: 2.0,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
