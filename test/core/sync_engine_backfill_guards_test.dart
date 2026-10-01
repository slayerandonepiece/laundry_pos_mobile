import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

import '../helpers/sync_test_env.dart';

/// Records every scope the backfill fetches; each fetch can be scripted.
class _Orders extends OrdersRepository {
  _Orders(ScriptedApi api, LocalCacheService cache)
    : super(apiClient: api, localCache: cache);
  final List<String> scopes = [];
  Future<void> Function(String scope)? onScope;
  int invoiceScans = 0;
  Completer<void>? invoiceGate;

  @override
  Future<bool> processPendingSyncQueue() async => true;
  @override
  Future<bool> syncOrdersDelta({
    int maxBatches = 10,
    int limit = 50,
    bool fromStart = false,
  }) async => true;
  @override
  Future<void> retryMissingInvoices() async {
    invoiceScans++;
    await invoiceGate?.future;
  }

  @override
  Future<void> syncOrdersForScope(String scope) async {
    scopes.add(scope);
    await onScope?.call(scope);
  }
}

class _Owner extends OwnerRepository {
  _Owner(ScriptedApi api, LocalCacheService cache)
    : super(apiClient: api, localCache: cache);
  @override
  Future<bool> processPendingOwnerActions() async => true;
  @override
  Future<void> syncDashboardForScope(String scope) async {}
  @override
  Future<void> syncExpensesForScope(String scope) async {}
}

void main() {
  late SyncTestEnv env;
  late _Orders orders;
  late SyncEngine engine;

  setUp(() async {
    env = await SyncTestEnv.create();
    final api = ScriptedApi(env.cache);
    orders = _Orders(api, env.cache);
    engine = SyncEngine.internal(
      ordersRepository: orders,
      ownerRepository: _Owner(api, env.cache),
      localCache: env.cache,
    );
    await env.cache.setCachedStoreDetails({
      'storeId': 'store-1',
      'storeName': 'Store',
      'role': 'OWNER',
    });
    await env.cache.setAllowedOutletsForStore('store-1', [
      {'id': 'o1', 'displayName': 'o1'},
      {'id': 'o2', 'displayName': 'o2'},
    ]);
  });
  tearDown(() => env.dispose());

  Future<void> runAndSettle() async {
    await engine.trigger();
    // The backfill is fire-and-forget; let its microtasks drain.
    await pumpEventQueue();
  }

  test('control: with nothing cached, every scope is fetched', () async {
    await runAndSettle();
    expect(orders.scopes, ['all', 'o1', 'o2']);
  });

  test('stops at once on 401 (no further scope is fetched)', () async {
    orders.onScope = (scope) async =>
        throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401);
    await runAndSettle();
    expect(orders.scopes, ['all']);
  });

  test('continues with the next scope after a non-401 failure', () async {
    orders.onScope = (scope) async {
      if (scope == 'all') throw ApiException('boom', statusCode: 500);
    };
    await runAndSettle();
    expect(orders.scopes, ['all', 'o1', 'o2']);
  });

  test('stops when the active store changes mid-run', () async {
    orders.onScope = (scope) async {
      if (scope == 'all') await env.cache.setActiveStoreId('store-2');
    };
    await runAndSettle();
    expect(orders.scopes, ['all']);
  });

  test('stops when connectivity drops mid-run', () async {
    final connectivity = FakeConnectivity();
    orders.onScope = (scope) async {
      // The engine reads ConnectivityService.instance, so flip that.
      if (scope == 'all') connectivity.offline = true;
    };
    // Install after setUp so the run starts online and goes offline inside.
    ConnectivityService.instance = connectivity;
    await runAndSettle();
    expect(orders.scopes, ['all']);
  });

  test('two concurrent triggers run only one backfill', () async {
    final gate = Completer<void>();
    orders.onScope = (scope) => gate.future;

    final first = engine.trigger();
    final second = engine.trigger(); // coalesces into a follow-up run
    await Future.wait([first, second]);
    await pumpEventQueue();
    // Still inside the first backfill's first scope; the follow-up run's
    // completion must not have started a second pass.
    expect(orders.scopes, ['all']);

    gate.complete();
    await pumpEventQueue();
    expect(orders.scopes, ['all', 'o1', 'o2']);
  });

  test('two concurrent triggers run only one missing-invoice scan', () async {
    orders.invoiceGate = Completer<void>();

    await Future.wait([engine.trigger(), engine.trigger()]);
    await pumpEventQueue();
    expect(orders.invoiceScans, 1);

    orders.invoiceGate!.complete();
    await pumpEventQueue();
    expect(orders.invoiceScans, 1);
  });
}
