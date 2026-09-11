import 'package:flutter/foundation.dart';

import '../storage/local_cache.dart';
import 'sync_manager.dart';
import '../../features/orders/data/orders_repository.dart';

/// Single entry point for every background sync attempt (reconnect, app
/// resume, pull-to-refresh, a manual "Sync now" tap). Guarantees only one
/// sync runs at a time — a second trigger while one is in flight just joins
/// it instead of firing a concurrent request — and tracks consecutive
/// whole-request failures so a flaky connection stops retrying silently
/// after a few tries and asks the user to retry manually instead.
class SyncEngine {
  @visibleForTesting
  SyncEngine.internal();

  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const int _maxSilentFailures = 3;

  final OrdersRepository _ordersRepository = OrdersRepository();
  final LocalCacheService _localCache = LocalCacheService();

  Future<void>? _inFlight;
  bool _retriggerRequested = false;
  int _failureStreak = 0;

  bool get isSyncing => _inFlight != null;

  /// Runs a sync cycle: push queued local changes, then pull remote changes.
  /// Safe to call from anywhere, anytime — overlapping callers share one run.
  /// If something is enqueued after a run already started (so it can't be
  /// part of that run's request), a trigger during that window schedules
  /// exactly one follow-up run once the current one finishes, instead of
  /// silently doing nothing — otherwise whatever was queued in that window
  /// would only sync on the next unrelated trigger, if any.
  Future<void> trigger() {
    final existing = _inFlight;
    if (existing != null) {
      _retriggerRequested = true;
      return existing;
    }

    final future = _runSync();
    _inFlight = future;
    future.whenComplete(() {
      _inFlight = null;
      if (_retriggerRequested) {
        _retriggerRequested = false;
        trigger();
      }
    });
    return future;
  }

  Future<void> _runSync() async {
    // Nothing from here should ever escape as an unhandled Future rejection
    // — callers fire this and forget, so an unexpected local error (not
    // just a network failure) must degrade to "treat this as a failed
    // sync attempt", never crash whatever called trigger().
    var ok = false;
    try {
      final pushOk = await _ordersRepository.processPendingSyncQueue();
      // Only attempt to pull remote changes if push reached the server —
      // otherwise we're offline/unreachable and a pull would just fail too.
      final pullOk = pushOk ? await _ordersRepository.syncOrdersDelta() : true;
      ok = pushOk && pullOk;
    } catch (_) {
      ok = false;
    }

    // The actual queue length, read fresh after push+pull both finished, is
    // the single source of truth for the banner — not whatever partial
    // state processPendingSyncQueue happened to leave behind mid-cycle.
    // This is what makes the banner reliably clear once nothing is left
    // to sync, instead of getting stuck on a stale offline/paused state.
    var pendingCount = 0;
    try {
      pendingCount = _localCache.getPendingSyncQueue().length;
    } catch (_) {
      // ignore — best-effort count for the banner text only
    }

    if (ok) {
      _failureStreak = 0;
      if (pendingCount == 0) {
        SyncManager.instance.completeSync();
      } else {
        SyncManager.instance.setOffline(pendingCount);
      }
      return;
    }

    _failureStreak++;
    if (_failureStreak >= _maxSilentFailures) {
      SyncManager.instance.setSyncPaused(pendingCount);
    }
  }

  /// Called after a user-initiated "Sync now" / "Retry" tap — gives the
  /// failure streak a fresh start so a single manual success clears the
  /// paused banner instead of requiring 3 more successes.
  Future<void> retryNow() {
    _failureStreak = 0;
    return trigger();
  }
}
