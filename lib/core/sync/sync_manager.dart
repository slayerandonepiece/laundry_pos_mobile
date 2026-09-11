import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

const _tag = 'BANNER';

enum SyncStatus { synced, syncing, offline, error, syncPaused, pendingOnline }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final String? message;
  final DateTime lastSyncedAt;

  const SyncState({
    this.status = SyncStatus.synced,
    this.pendingCount = 0,
    this.message,
    required this.lastSyncedAt,
  });

  bool get isSyncing => status == SyncStatus.syncing;
  bool get isOffline => status == SyncStatus.offline;
  bool get isSynced => status == SyncStatus.synced;
  bool get hasError => status == SyncStatus.error;
  bool get isSyncPaused => status == SyncStatus.syncPaused;
  bool get isPendingOnline => status == SyncStatus.pendingOnline;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    String? message,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      message: message ?? this.message,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class SyncManager extends ValueNotifier<SyncState> {
  static final SyncManager instance = SyncManager._();

  SyncManager._() : super(SyncState(lastSyncedAt: DateTime.now()));

  void _logTransition(
    SyncStatus newStatus, {
    String? message,
    int? pendingCount,
  }) {
    AppLogger.log(
      _tag,
      '${value.status} -> $newStatus'
      '${message != null ? ' | message="$message"' : ''}'
      '${pendingCount != null ? ' | pendingCount=$pendingCount' : ''}',
    );
  }

  void startSync([String message = 'Syncing data...']) {
    _logTransition(SyncStatus.syncing, message: message);
    value = value.copyWith(status: SyncStatus.syncing, message: message);
  }

  void completeSync() {
    _logTransition(
      SyncStatus.synced,
      message: 'All data synced',
      pendingCount: 0,
    );
    value = value.copyWith(
      status: SyncStatus.synced,
      pendingCount: 0,
      message: 'All data synced',
      lastSyncedAt: DateTime.now(),
    );
  }

  void setOffline(int pendingCount, [String? message]) {
    final resolvedMessage =
        message ??
        (pendingCount > 0
            ? 'Offline · $pendingCount ${pendingCount == 1 ? "change" : "changes"} saved locally'
            : 'Offline mode');
    _logTransition(
      SyncStatus.offline,
      message: resolvedMessage,
      pendingCount: pendingCount,
    );
    value = value.copyWith(
      status: SyncStatus.offline,
      pendingCount: pendingCount,
      message: resolvedMessage,
    );
  }

  void setPendingOnline(int pendingCount, [String? message]) {
    final resolvedMessage =
        message ??
        (pendingCount > 0
            ? '$pendingCount ${pendingCount == 1 ? "change" : "changes"} pending'
            : 'Changes pending');
    _logTransition(
      SyncStatus.pendingOnline,
      message: resolvedMessage,
      pendingCount: pendingCount,
    );
    value = value.copyWith(
      status: SyncStatus.pendingOnline,
      pendingCount: pendingCount,
      message: resolvedMessage,
    );
  }

  void setError(String error) {
    _logTransition(SyncStatus.error, message: error);
    value = value.copyWith(status: SyncStatus.error, message: error);
  }

  /// Several sync attempts in a row failed to even reach the server (not a
  /// per-action validation failure — the whole request didn't go through).
  /// Auto-retry stops here; the user has to tap "Sync now" to try again, so
  /// a flaky connection doesn't retry silently forever without ever telling
  /// anyone changes aren't going through.
  void setSyncPaused(int pendingCount) {
    final resolvedMessage = pendingCount > 0
        ? 'Sync paused · $pendingCount ${pendingCount == 1 ? "change" : "changes"} waiting — tap to retry'
        : 'Sync paused — tap to retry';
    _logTransition(
      SyncStatus.syncPaused,
      message: resolvedMessage,
      pendingCount: pendingCount,
    );
    value = value.copyWith(
      status: SyncStatus.syncPaused,
      pendingCount: pendingCount,
      message: resolvedMessage,
    );
  }
}
