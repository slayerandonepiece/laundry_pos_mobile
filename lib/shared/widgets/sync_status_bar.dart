import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  SyncState _state = SyncManager.instance.value;
  Timer? _syncedTimer;

  // "Syncing…" and "All data synced" come and go on their own, so they float
  // over the content from this bar's slot instead of pushing it down and back
  // up. States that stay (offline, pending, error, paused) do take the space.
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  @override
  void initState() {
    super.initState();
    SyncManager.instance.addListener(_handleSyncChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  void dispose() {
    SyncManager.instance.removeListener(_handleSyncChange);
    _syncedTimer?.cancel();
    super.dispose();
  }

  void _handleSyncChange() {
    if (!mounted) return;
    // A notify that lands mid-build (layout/paint) cannot setState; apply it
    // right after the frame instead.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applySyncState();
      });
      return;
    }
    _applySyncState();
  }

  void _applySyncState() {
    // Each change replaces the pending hide, so an earlier "synced" timer can
    // never hide a later banner.
    _syncedTimer?.cancel();
    _syncedTimer = null;
    final synced = SyncManager.instance.value.status == SyncStatus.synced;
    setState(() {
      _state = SyncManager.instance.value;
      _showSyncedBanner = synced;
    });
    if (synced) {
      _syncedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showSyncedBanner = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final persistent =
        state.isOffline ||
        state.isPendingOnline ||
        state.hasError ||
        state.isSyncPaused;
    final floating = !persistent && (state.isSyncing || _showSyncedBanner);
    // Full width even when idle (the collapsed bar is zero-wide and a
    // Column would centre it), so the floating bar lines up with the
    // screen's left edge.
    return CompositedTransformTarget(
      link: _link,
      child: SizedBox(
        width: double.infinity,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (overlayContext) => floating
              ? CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(overlayContext).width,
                      child: IgnorePointer(
                        child: Material(
                          type: MaterialType.transparency,
                          child: _bar(state, visible: true),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          child: _bar(state, visible: persistent),
        ),
      ),
    );
  }

  Widget _bar(SyncState state, {required bool visible}) {
    final isSyncing = state.isSyncing;
    final isOffline = state.isOffline;
    final isPendingOnline = state.isPendingOnline;
    final isError = state.hasError;
    final isSyncPaused = state.isSyncPaused;
    final isVisible = visible;
    // A bar with a retry action is the tap target (44 high) — the small
    // "Sync now"/"Retry" label alone would be too fiddly to hit.
    final actionable =
        isVisible &&
        widget.onSyncNow != null &&
        (isPendingOnline || isSyncPaused || isError);

    final bar = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: isVisible ? (actionable ? 44.0 : 36.0) : 0.0,
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
                          Builder(
                            builder: (context) {
                              final msg = (state.message ?? '').toLowerCase();
                              final isPush =
                                  msg.contains('saving') ||
                                  msg.contains('offline changes') ||
                                  msg.contains('push');
                              final isPull =
                                  msg.contains('fetching') ||
                                  msg.contains('latest') ||
                                  msg.contains('pull');
                              IconData? dirIcon;
                              if (isPush) {
                                dirIcon = Icons.cloud_upload_rounded;
                              } else if (isPull || msg.contains('cloud')) {
                                dirIcon = Icons.cloud_download_rounded;
                              }
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (dirIcon != null) ...[
                                    Icon(
                                      dirIcon,
                                      size: 15,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
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
                                ],
                              );
                            },
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
    return actionable
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSyncNow,
            child: bar,
          )
        : bar;
  }
}
