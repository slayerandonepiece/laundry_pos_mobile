import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../storage/local_cache.dart';

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

  /// Unsent local changes and dead-lettered ones. Read straight from the
  /// cache so any caller of [completeSync] (a plain successful read anywhere
  /// in the app) cannot report "All data synced" over them.
  ({int pending, int deadLetter}) _localUnresolved() {
    try {
      final cache = LocalCacheService();
      return (
        pending: cache.getTotalPendingCount(),
        deadLetter: cache.getTotalDeadLetterCount(),
      );
    } catch (_) {
      // Cache not open (e.g. before init) — nothing known to be unsynced.
      return (pending: 0, deadLetter: 0);
    }
  }

  /// [force] is for the sync engine's push (it owns the pending/paused/error
  /// states); any other caller must not replace them with a transient
  /// "syncing" state.
  void startSync([String message = 'Syncing data...', bool force = false]) {
    if (!force &&
        (value.hasError || value.isSyncPaused || value.isPendingOnline)) {
      AppLogger.log(
        _tag,
        'startSync("$message") ignored while ${value.status}',
      );
      return;
    }
    _logTransition(SyncStatus.syncing, message: message);
    value = value.copyWith(status: SyncStatus.syncing, message: message);
  }

  /// Marks everything synced. Unless [force] (the engine, which has just
  /// verified the queues are empty), this never clears pending/dead-lettered
  /// state: a read finishing elsewhere says nothing about unsent changes.
  void completeSync({bool force = false}) {
    if (!force) {
      final unresolved = _localUnresolved();
      if (unresolved.pending > 0 || unresolved.deadLetter > 0) {
        AppLogger.log(
          _tag,
          'completeSync() ignored: pending=${unresolved.pending} '
          'deadLetter=${unresolved.deadLetter}',
        );
        // Only a transient "syncing" needs replacing; keep any other
        // pending/paused/error/offline state exactly as it is.
        if (value.isSyncing) {
          if (unresolved.deadLetter > 0) {
            setDeadLettered(unresolved.deadLetter);
          } else {
            setPendingOnline(unresolved.pending);
          }
        }
        return;
      }
    }
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

  /// Changes the server rejected repeatedly and that are now parked; they
  /// are not retried on their own, so the banner must stay until the user
  /// taps retry (which revives them).
  void setDeadLettered(int count) {
    final resolvedMessage =
        "$count ${count == 1 ? "change" : "changes"} couldn't be saved — tap to retry";
    _logTransition(
      SyncStatus.syncPaused,
      message: resolvedMessage,
      pendingCount: count,
    );
    value = value.copyWith(
      status: SyncStatus.syncPaused,
      pendingCount: count,
      message: resolvedMessage,
    );
  }

  void setError(String error) {
    _logTransition(SyncStatus.error, message: error);
    value = value.copyWith(status: SyncStatus.error, message: error);
  }

  void clearError(String messagePrefix) {
    if (!value.hasError ||
        !(value.message?.startsWith(messagePrefix) ?? false)) {
      return;
    }
    final unresolved = _localUnresolved();
    if (unresolved.deadLetter > 0) {
      setDeadLettered(unresolved.deadLetter);
    } else if (unresolved.pending > 0) {
      setPendingOnline(unresolved.pending);
    } else {
      completeSync();
    }
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
