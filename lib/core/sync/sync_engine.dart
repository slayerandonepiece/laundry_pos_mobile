import 'dart:async';

import 'package:flutter/foundation.dart';

import '../analytics/app_analytics.dart';
import '../logging/app_logger.dart';
import '../network/api_exceptions.dart';
import '../storage/local_cache.dart';
import 'connectivity_service.dart';
import 'sync_freshness.dart';
import 'sync_manager.dart';
import '../../features/auth/data/models/user_model.dart';
import '../../features/orders/data/orders_repository.dart';
import '../../features/owner/data/owner_repository.dart';

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
    OwnerRepository? ownerRepository,
    LocalCacheService? localCache,
  }) : _ordersRepository = ordersRepository ?? OrdersRepository(),
       _ownerRepository = ownerRepository ?? OwnerRepository(),
       _localCache = localCache ?? LocalCacheService();

  SyncEngine._()
    : _ordersRepository = OrdersRepository(),
      _ownerRepository = OwnerRepository(),
      _localCache = LocalCacheService();

  static SyncEngine _instance = SyncEngine._();
  static SyncEngine get instance => _instance;
  @visibleForTesting
  static set instance(SyncEngine value) => _instance = value;

  static const int _maxSilentFailures = 3;

  final OrdersRepository _ordersRepository;
  final OwnerRepository _ownerRepository;
  final LocalCacheService _localCache;

  Future<void>? _inFlight;
  Completer<void>? _pendingGenerationCompleter;
  bool _retriggerRequested = false;
  int _failureStreak = 0;
  bool _invoiceRetryInFlight = false;
  bool _backfillInFlight = false;

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

  /// For triggers nobody asked for (app resume): skips the run when the phone
  /// synced within the freshness window and nothing is waiting to be sent, so
  /// switching apps back and forth doesn't re-download the same data. A
  /// non-empty dead-letter queue is unresolved state, never "nothing waiting".
  Future<void> triggerIfStale() {
    var pending = 0;
    var deadLetter = 0;
    try {
      pending = _localCache.getTotalPendingCount();
      deadLetter = _localCache.getTotalDeadLetterCount();
    } catch (e) {
      AppLogger.log(_tag, 'triggerIfStale(): cannot read queues', error: e);
    }
    if (SyncFreshness.isFresh && pending == 0 && deadLetter == 0) {
      AppLogger.log(_tag, 'triggerIfStale(): fresh and nothing queued -> skip');
      return Future.value();
    }
    return trigger();
  }

  /// Outcome of the most recent run: true when everything reached the server,
  /// false when it failed or the phone was offline, null when it was skipped
  /// (not signed in) or nothing has run yet. Lets callers tell a failed first
  /// sync from an empty account without reading the shared banner.
  bool? get lastRunSucceeded => _lastRunSucceeded;
  bool? _lastRunSucceeded;

  /// Never throws: callers fire-and-forget, so nothing (including a local
  /// cache read failing) may escape as an unhandled Future error, and the
  /// banner must never be left on the transient "syncing" state.
  Future<void> _runSync() async {
    try {
      await _runSyncImpl();
    } catch (e) {
      AppLogger.log(_tag, '_runSync(): unexpected error', error: e);
      await AppAnalytics.syncFailed(reason: _failureReason(e));
      _lastRunSucceeded = false;
      _leaveSyncingState(_safePendingCount());
    }
  }

  int _safePendingCount() {
    try {
      return _localCache.getTotalPendingCount();
    } catch (e) {
      AppLogger.log(_tag, 'cannot read pending count', error: e);
      return 0;
    }
  }

  /// A run that ends without success must not leave the non-interactive
  /// "syncing" state behind: show pending changes, or a retryable error.
  void _leaveSyncingState(int pendingCount) {
    if (!SyncManager.instance.value.isSyncing) return;
    if (pendingCount > 0) {
      SyncManager.instance.setPendingOnline(pendingCount);
    } else {
      SyncManager.instance.setError('Sync failed — tap to retry');
    }
  }

  Future<void> _runSyncImpl() async {
    final activeStoreId = _localCache.getActiveStoreId();
    if (activeStoreId == null) {
      AppLogger.log(_tag, '_runSync(): not signed in -> skipping');
      _lastRunSucceeded = null;
      return;
    }
    AppLogger.log(_tag, '_runSync(): start');
    if (ConnectivityService.instance.isOffline) {
      final count = _safePendingCount();
      AppLogger.log(
        _tag,
        '_runSync(): ConnectivityService reports offline -> setOffline($count)',
      );
      _lastRunSucceeded = false;
      SyncManager.instance.setOffline(count);
      await AppAnalytics.syncFailed(reason: 'offline');
      return;
    }

    var ok = false;
    var sessionLost = false;
    var pullAdvanced = false;
    Object? failure;
    try {
      if (_localCache.getTotalPendingCount() > 0) {
        SyncManager.instance.startSync('Saving changes to cloud...', true);
      }
      final pushOk = await _ordersRepository.processPendingSyncQueue();
      AppLogger.log(_tag, '_runSync(): push outcome=$pushOk');
      // Only attempt to pull remote changes if push reached the server —
      // otherwise we're offline/unreachable and a pull would just fail too.
      final cursorBefore = _localCache.getLastSyncCursor();
      final pullOk = pushOk ? await _ordersRepository.syncOrdersDelta() : true;
      pullAdvanced = _localCache.getLastSyncCursor() != cursorBefore;
      AppLogger.log(_tag, '_runSync(): pull outcome=$pullOk');

      final ownerOk = await _ownerRepository.processPendingOwnerActions();
      AppLogger.log(_tag, '_runSync(): owner actions drain outcome=$ownerOk');

      ok = pushOk && pullOk && ownerOk;
    } catch (e) {
      failure = e;
      AppLogger.log(_tag, '_runSync(): unexpected error during sync', error: e);
      // A dead session is handled by the auth layer (the 401 already
      // signed the user out); it says nothing about connectivity, so it
      // must not count toward the "paused" streak.
      sessionLost = e is AuthException && e.statusCode == 401;
      ok = false;
    }

    // The actual queue length, read fresh after push+pull both finished, is
    // the single source of truth for the banner — not whatever partial
    // state processPendingSyncQueue happened to leave behind mid-cycle.
    var pendingCount = 0;
    var deadLetterCount = 0;
    try {
      pendingCount = _localCache.getTotalPendingCount();
      deadLetterCount = _localCache.getTotalDeadLetterCount();
    } catch (e) {
      AppLogger.log(_tag, '_runSync(): cannot read queue sizes', error: e);
    }
    _lastRunSucceeded = ok && deadLetterCount == 0;

    if (deadLetterCount > 0) {
      // Parked actions are unsent data and are not retried on their own:
      // never "all synced" and never marked fresh, until the user retries.
      AppLogger.log(
        _tag,
        '_runSync(): $deadLetterCount dead-lettered -> setDeadLettered',
      );
      if (!ok) _failureStreak++;
      await AppAnalytics.syncFailed(
        reason: ok ? 'unknown' : _failureReason(failure),
      );
      SyncManager.instance.setDeadLettered(deadLetterCount);
      return;
    }

    if (ok) {
      _failureStreak = 0;
      SyncFreshness.mark();
      if (pendingCount == 0) {
        AppLogger.log(
          _tag,
          '_runSync(): success, nothing pending -> completeSync()',
        );
        SyncManager.instance.completeSync(force: true);
        // Fire-and-forget, never blocks the banner: catch up any order that
        // reached paid+delivered but never got a real invoice (e.g. the
        // one-shot invoice call after payment/handover ran while offline
        // and had nothing to retry it). Never runs two scans at once.
        _retryMissingInvoicesInBackground();
        _backfillScopesInBackground();
      } else {
        final currentQueue = _localCache.getPendingSyncQueue();
        final currentOwnerQueue = _localCache.getPendingOwnerActionsQueue();
        final hasExhaustedFailures =
            currentQueue.any(
              (a) =>
                  ((a['failCount'] as num?)?.toInt() ?? 0) >=
                  _maxSilentFailures,
            ) ||
            currentOwnerQueue.any(
              (a) =>
                  ((a['failCount'] as num?)?.toInt() ?? 0) >=
                  _maxSilentFailures,
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

    if (pullAdvanced) {
      // A bounded pull may need several runs. An advancing saved cursor is
      // progress, so it must not consume the non-progress retry budget.
      _failureStreak = 0;
    } else if (!sessionLost) {
      _failureStreak++;
    }
    AppLogger.log(_tag, '_runSync(): failed, failureStreak=$_failureStreak');
    await AppAnalytics.syncFailed(reason: _failureReason(failure));
    if (_failureStreak >= _maxSilentFailures) {
      AppLogger.log(
        _tag,
        '_runSync(): failure streak exhausted -> setSyncPaused',
      );
      SyncManager.instance.setSyncPaused(pendingCount);
    } else {
      _leaveSyncingState(pendingCount);
    }
  }

  String _failureReason(Object? error) {
    if (error is ApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'forbidden';
      }
      if ((error.statusCode ?? 0) >= 500) return 'server';
    }
    return error == null ? 'server' : 'unknown';
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
    try {
      await _ordersRepository.reviveDeadLetterQueue();
      await _ownerRepository.reviveDeadLetterQueue();
      await ConnectivityService.instance.checkIsOffline();
    } catch (e) {
      // Callers fire-and-forget this; still attempt the sync below.
      AppLogger.log(_tag, 'retryNow(): revive/probe failed', error: e);
    }
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

  /// Owner with several outlets: fills any outlet (or the combined All
  /// outlets view) that has nothing on the phone yet — a session signed in
  /// before per-outlet sync existed, or an outlet added since sign-in — so the
  /// switcher never says "Not on this phone yet". Fire-and-forget; never runs
  /// two passes at once.
  Future<void> _backfillScopesInBackground() async {
    if (_backfillInFlight) return;
    _backfillInFlight = true;
    try {
      await _backfillScopes();
    } catch (e) {
      AppLogger.log(_tag, 'backfillScopes(): unexpected error', error: e);
    } finally {
      _backfillInFlight = false;
    }
  }

  bool _scopeCached(String scope) {
    final all = scope == LocalCacheService.allScope;
    return _localCache.hasCachedOrdersFor(
          outletId: all ? null : scope,
          allOutlets: all,
        ) &&
        _localCache.getCachedDashboardMetricsForScope(scope) != null &&
        _localCache.getCachedExpensesForScope(scope) != null;
  }

  Future<void> _backfillScopes() async {
    final storeJson = _localCache.getCachedStoreDetails();
    if (storeJson == null || !StoreSummary.fromJson(storeJson).isOwner) return;
    final outletIds = [
      for (final o in _localCache.getAllowedOutlets() ?? const [])
        if (o['id']?.toString().isNotEmpty == true) o['id'].toString(),
    ];
    if (outletIds.length <= 1) return;

    final storeId = _localCache.getActiveStoreId();
    final missing = [
      for (final scope in [LocalCacheService.allScope, ...outletIds])
        if (!_scopeCached(scope)) scope,
    ];
    if (missing.isEmpty) return;
    AppLogger.log(_tag, 'backfillScopes(): filling $missing');

    for (final scope in missing) {
      // Stop as soon as the session is gone, the store changed, or we went
      // offline; the next sync picks up what is left.
      if (_localCache.getActiveStoreId() != storeId) return;
      if (ConnectivityService.instance.isOffline) return;
      try {
        await Future.wait([
          _ordersRepository.syncOrdersForScope(scope),
          _ownerRepository.syncDashboardForScope(scope),
          _ownerRepository.syncExpensesForScope(scope),
        ]);
      } catch (e) {
        AppLogger.log(_tag, 'backfillScopes(): $scope failed', error: e);
        if (e is AuthException && e.statusCode == 401) return;
      }
    }
  }
}
