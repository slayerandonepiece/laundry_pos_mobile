import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../storage/local_cache.dart';
import 'connectivity_service.dart';
import 'sync_manager.dart';
import '../../features/orders/data/orders_repository.dart';

const _tag = 'SYNC';

/// Single entry point for every background sync attempt (reconnect, app
/// resume, pull-to-refresh, a manual "Sync now" tap). Guarantees only one
/// sync runs at a time — a second trigger while one is in flight just joins
/// it instead of firing a concurrent request — and tracks consecutive
/// whole-request failures so a flaky connection stops retrying silently
/// after a few tries and asks the user to retry manually instead.
class SyncEngine {
  @visibleForTesting
  SyncEngine.internal({
    OrdersRepository? ordersRepository,
    LocalCacheService? localCache,
  }) : _ordersRepository = ordersRepository ?? OrdersRepository(),
       _localCache = localCache ?? LocalCacheService();

  SyncEngine._()
    : _ordersRepository = OrdersRepository(),
      _localCache = LocalCacheService();

  static SyncEngine _instance = SyncEngine._();
  static SyncEngine get instance => _instance;
  @visibleForTesting
  static set instance(SyncEngine value) => _instance = value;

  static const int _maxSilentFailures = 3;

  final OrdersRepository _ordersRepository;
  final LocalCacheService _localCache;

  Future<void>? _inFlight;
  Completer<void>? _pendingGenerationCompleter;
  bool _retriggerRequested = false;
  int _failureStreak = 0;
  bool _invoiceRetryInFlight = false;

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
      AppLogger.log(_tag, 'trigger(): sync already in flight -> coalescing');
      _retriggerRequested = true;
      _pendingGenerationCompleter ??= Completer<void>();
      return _pendingGenerationCompleter!.future;
    }

    AppLogger.log(_tag, 'trigger(): starting new sync run');
    final future = _runSync();
    _inFlight = future;
    future.whenComplete(() {
      _inFlight = null;
      if (_retriggerRequested) {
        _retriggerRequested = false;
        AppLogger.log(
          _tag,
          'trigger(): follow-up run requested while syncing -> re-triggering',
        );
        final completerToResolve = _pendingGenerationCompleter;
        _pendingGenerationCompleter = null;
        trigger().whenComplete(() {
          if (completerToResolve != null && !completerToResolve.isCompleted) {
            completerToResolve.complete();
          }
        });
      }
    });
    return future;
  }

  Future<void> _runSync() async {
    AppLogger.log(_tag, '_runSync(): start');
    if (ConnectivityService.instance.isOffline) {
      var count = 0;
      try {
        count = _localCache.getPendingSyncQueue().length;
      } catch (_) {}
      AppLogger.log(
        _tag,
        '_runSync(): ConnectivityService reports offline -> setOffline($count)',
      );
      SyncManager.instance.setOffline(count);
      return;
    }

    // Nothing from here should ever escape as an unhandled Future rejection
    // — callers fire this and forget, so an unexpected local error (not
    // just a network failure) must degrade to "treat this as a failed
    // sync attempt", never crash whatever called trigger().
    var ok = false;
    try {
      final pushOk = await _ordersRepository.processPendingSyncQueue();
      AppLogger.log(_tag, '_runSync(): push outcome=$pushOk');
      // Only attempt to pull remote changes if push reached the server —
      // otherwise we're offline/unreachable and a pull would just fail too.
      final pullOk = pushOk ? await _ordersRepository.syncOrdersDelta() : true;
      AppLogger.log(_tag, '_runSync(): pull outcome=$pullOk');
      ok = pushOk && pullOk;
    } catch (e) {
      AppLogger.log(_tag, '_runSync(): unexpected error during sync', error: e);
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
        AppLogger.log(
          _tag,
          '_runSync(): success, nothing pending -> completeSync()',
        );
        SyncManager.instance.completeSync();
        // Fire-and-forget, never blocks the banner: catch up any order that
        // reached paid+delivered but never got a real invoice (e.g. the
        // one-shot invoice call after payment/handover ran while offline
        // and had nothing to retry it). Never runs two scans at once.
        _retryMissingInvoicesInBackground();
      } else {
        final currentQueue = _localCache.getPendingSyncQueue();
        final hasExhaustedFailures = currentQueue.any(
          (a) => ((a['failCount'] as num?)?.toInt() ?? 0) >= _maxSilentFailures,
        );
        if (hasExhaustedFailures) {
          AppLogger.log(
            _tag,
            '_runSync(): success but $pendingCount item(s) exhausted retries -> setSyncPaused',
          );
          SyncManager.instance.setSyncPaused(pendingCount);
        } else {
          AppLogger.log(
            _tag,
            '_runSync(): success, $pendingCount item(s) still pending -> setPendingOnline',
          );
          SyncManager.instance.setPendingOnline(pendingCount);
        }
      }
      return;
    }

    _failureStreak++;
    AppLogger.log(_tag, '_runSync(): failed, failureStreak=$_failureStreak');
    if (_failureStreak >= _maxSilentFailures) {
      AppLogger.log(
        _tag,
        '_runSync(): failure streak exhausted -> setSyncPaused',
      );
      SyncManager.instance.setSyncPaused(pendingCount);
    }
  }

  /// Called after a user-initiated "Sync now" / "Retry" tap — gives the
  /// failure streak a fresh start so a single manual success clears the
  /// paused banner instead of requiring 3 more successes.
  ///
  /// Also forces a fresh reachability probe first: _runSync() gates on
  /// ConnectivityService.instance.isOffline, a cached flag that only the OS
  /// connectivity listener normally refreshes. If that flag went stale —
  /// e.g. a probe failed once at cold start and the OS never fires another
  /// change event because the interface itself never dropped — a manual
  /// retry must not inherit that stale "offline" reading and give up before
  /// ever touching the network.
  Future<void> retryNow() async {
    _failureStreak = 0;
    await _ordersRepository.reviveDeadLetterQueue();
    await ConnectivityService.instance.checkIsOffline();
    return trigger();
  }

  Future<void> _retryMissingInvoicesInBackground() async {
    if (_invoiceRetryInFlight) return;
    _invoiceRetryInFlight = true;
    try {
      await _ordersRepository.retryMissingInvoices();
    } catch (e) {
      AppLogger.log(_tag, 'retryMissingInvoices(): unexpected error', error: e);
    } finally {
      _invoiceRetryInFlight = false;
    }
  }
}
