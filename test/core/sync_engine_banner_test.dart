import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

import '../helpers/sync_test_env.dart';

class _Orders extends OrdersRepository {
  _Orders(ScriptedApi api, LocalCacheService cache)
    : super(apiClient: api, localCache: cache);
  bool? pushResult;
  Object? pullError;
  bool pullResult = true;
  bool useRealPull = false;
  int pulls = 0;

  @override
  Future<bool> processPendingSyncQueue() async =>
      pushResult ?? await super.processPendingSyncQueue();

  @override
  Future<bool> syncOrdersDelta({
    int maxBatches = 10,
    int limit = 50,
    bool fromStart = false,
  }) async {
    pulls++;
    if (pullError != null) throw pullError!;
    if (useRealPull) {
      return super.syncOrdersDelta(
        maxBatches: 1,
        limit: limit,
        fromStart: fromStart,
      );
    }
    return pullResult;
  }

  @override
  Future<void> retryMissingInvoices() async {}
}

class _Owner extends OwnerRepository {
  _Owner(ScriptedApi api, LocalCacheService cache)
    : super(apiClient: api, localCache: cache);
  Object? drainError;
  bool drainResult = true;

  @override
  Future<bool> processPendingOwnerActions() async {
    if (drainError != null) throw drainError!;
    return drainResult;
  }
}

/// A cache whose reads can be made to fail.
class _FlakyCache extends LocalCacheService {
  bool failActiveStore = false;
  @override
  String? getActiveStoreId() {
    if (failActiveStore) throw StateError('corrupt cache');
    return super.getActiveStoreId();
  }
}

void main() {
  late SyncTestEnv env;
  late ScriptedApi api;
  late _Orders orders;
  late _Owner owner;
  late SyncEngine engine;
  final banner = SyncManager.instance;

  setUp(() async {
    env = await SyncTestEnv.create();
    api = ScriptedApi(env.cache);
    orders = _Orders(api, env.cache);
    owner = _Owner(api, env.cache);
    engine = SyncEngine.internal(
      ordersRepository: orders,
      ownerRepository: owner,
      localCache: env.cache,
    );
    SyncEngine.instance = engine;
    // Pull is never the subject unless a test says so.
  });
  tearDown(() async {
    SyncEngine.instance = SyncEngine.internal();
    await env.dispose();
  });

  Future<void> queue([int n = 1]) => env.cache.setPendingSyncQueue([
    for (var i = 0; i < n; i++)
      {
        'type': 'update_status',
        'clientActionId': 'a$i',
        'orderCode': 'EL-1',
        'status': 'Ready',
        'storeId': 'store-1',
      },
  ]);

  group('dead-lettered changes are never "All data synced" (C1)', () {
    test(
      'a push that dead-letters leaves the banner on a tappable error',
      () async {
        await env.cache.setPendingSyncQueue([
          {
            'type': 'update_status',
            'clientActionId': 'bad',
            'orderCode': 'EL-1',
            'status': 'Ready',
            'storeId': 'store-1',
            'outletId': 'A',
            'failCount': 4,
          },
        ]);
        api.onPost = (u, b, h) async => throw ValidationException('poison');
        // Real push, real dead-letter path.
        orders.pushResult = null;

        await engine.trigger();

        expect(env.cache.getDeadLetterQueue(), hasLength(1));
        expect(banner.value.isSynced, isFalse);
        expect(banner.value.isSyncPaused, isTrue);
        expect(
          banner.value.message,
          "1 change couldn't be saved — tap to retry",
        );
        expect(SyncFreshness.isFresh, isFalse);
        expect(engine.lastRunSucceeded, isFalse);
      },
    );

    test('an old dead-letter queue keeps the banner even when the run itself succeeds', () async {
      await env.cache.setDeadLetterQueue([
        {'clientActionId': 'd1'},
      ]);
      await env.cache.setDeadLetterOwnerActionsQueue([
        {'clientActionId': 'o1'},
      ]);

      await engine.trigger();

      expect(banner.value.isSyncPaused, isTrue);
      expect(banner.value.message, contains('2 changes'));
      expect(SyncFreshness.isFresh, isFalse);
    });

    test(
      'triggerIfStale does not skip while something is dead-lettered',
      () async {
        SyncFreshness.mark();
        await env.cache.setDeadLetterQueue([
          {'clientActionId': 'd1'},
        ]);
        orders.pushResult = true;

        await engine.triggerIfStale();

        expect(orders.pulls, 1);
      },
    );

    test(
      'triggerIfStale still skips when fresh and nothing is waiting',
      () async {
        SyncFreshness.mark();
        await engine.triggerIfStale();
        expect(orders.pulls, 0);
      },
    );

    test(
      'manual retry revives them and a successful run clears the banner',
      () async {
        await env.cache.setDeadLetterQueue([
          {
            'type': 'update_status',
            'clientActionId': 'd1',
            'orderCode': 'EL-1',
            'status': 'Ready',
            'storeId': 'store-1',
            'outletId': 'A',
            'failCount': 5,
          },
        ]);
        await engine.trigger();
        expect(banner.value.isSyncPaused, isTrue);

        api.onPost = (u, b, h) async => {
          'results': [
            {'clientActionId': 'd1', 'status': 'success'},
          ],
        };
        await engine.retryNow();

        expect(env.cache.getDeadLetterQueue(), isEmpty);
        expect(banner.value.isSynced, isTrue);
      },
    );
  });

  group('a failed run never leaves the floating "syncing" state (H9)', () {
    test(
      'two truncated pulls advance the cursor and the third completes',
      () async {
        orders.useRealPull = true;
        api.onGet = (url, headers) async {
          if (url.contains('since=c2')) {
            return {'orders': <dynamic>[], 'nextCursor': null};
          }
          return {
            'orders': <dynamic>[],
            'nextCursor': url.contains('since=c1') ? 'c2' : 'c1',
          };
        };

        await engine.trigger();
        expect(banner.value.isSyncPaused, isFalse);
        expect(env.cache.getLastSyncCursor(), 'c1');
        await engine.trigger();
        expect(banner.value.isSyncPaused, isFalse);
        expect(env.cache.getLastSyncCursor(), 'c2');
        await engine.trigger();
        expect(banner.value.isSynced, isTrue);
        expect(api.gets.map((url) => Uri.parse(url).query), [
          'limit=50',
          'since=c1&limit=50',
          'since=c2&limit=50',
        ]);
      },
    );

    test(
      'pull fails with changes still queued -> "N changes pending"',
      () async {
        await queue(2);
        orders.pushResult = true;
        orders.pullResult = false;

        await engine.trigger();

        expect(banner.value.isSyncing, isFalse);
        expect(banner.value.isPendingOnline, isTrue);
        expect(banner.value.pendingCount, 2);
      },
    );

    test('owner drain throws -> pending, not stuck syncing', () async {
      await queue();
      orders.pushResult = true;
      owner.drainError = StateError('boom');

      await engine.trigger();

      expect(banner.value.isSyncing, isFalse);
      expect(banner.value.isPendingOnline, isTrue);
    });

    test(
      'a failure while only the read banner was showing -> retryable error',
      () async {
        banner.startSync('Fetching latest from cloud...');
        orders.pushResult = true;
        orders.pullResult = false;

        await engine.trigger();

        expect(banner.value.isSyncing, isFalse);
        expect(banner.value.hasError, isTrue);
      },
    );

    test('a cache read failing does not escape trigger()', () async {
      final flaky = _FlakyCache();
      final flakyEngine = SyncEngine.internal(
        ordersRepository: orders,
        ownerRepository: owner,
        localCache: flaky,
      );
      flaky.failActiveStore = true;

      await flakyEngine.trigger(); // must complete normally
      expect(flakyEngine.lastRunSucceeded, isFalse);
    });

    test('three failures still pause the banner', () async {
      orders.pushResult = true;
      orders.pullResult = false;
      for (var i = 0; i < 3; i++) {
        await engine.trigger();
      }
      expect(banner.value.isSyncPaused, isTrue);
    });
  });

  group('a dead session is not a connectivity failure', () {
    test(
      '401 during the pull is logged, not counted toward "paused"',
      () async {
        orders.pushResult = true;
        orders.pullError = AuthException(
          code: 'UNAUTHENTICATED',
          statusCode: 401,
        );
        for (var i = 0; i < 4; i++) {
          await engine.trigger();
        }
        expect(banner.value.isSyncPaused, isFalse);
      },
    );
  });

  test('a successful run completes and marks fresh', () async {
    orders.pushResult = true;
    await engine.trigger();
    expect(banner.value.isSynced, isTrue);
    expect(SyncFreshness.isFresh, isTrue);
    expect(engine.lastRunSucceeded, isTrue);
  });

  test('not signed in: skipped, lastRunSucceeded is null', () async {
    await env.cache.clearActiveStoreId();
    await engine.trigger();
    expect(engine.lastRunSucceeded, isNull);
  });
}
