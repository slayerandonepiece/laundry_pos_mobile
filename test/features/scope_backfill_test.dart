import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

class _Online extends ConnectivityService {
  _Online(this.offline) : super.internal();
  bool offline;
  @override
  bool get isOffline => offline;
  @override
  Future<bool> checkIsOffline() async => offline;
}

class _Orders extends OrdersRepository {
  _Orders(LocalCacheService cache)
    : super(apiClient: ApiClient(), localCache: cache);
  final List<String> scopes = [];

  @override
  Future<bool> processPendingSyncQueue() async => true;
  @override
  Future<bool> syncOrdersDelta({
    bool fromStart = false,
    int limit = 50,
    int maxBatches = 20,
  }) async => true;
  @override
  Future<void> retryMissingInvoices() async {}
  @override
  Future<void> syncOrdersForScope(String scope) async => scopes.add(scope);
}

class _Owner extends OwnerRepository {
  _Owner() : super(apiClient: ApiClient());
  final List<String> dashboards = [];
  final List<String> expenses = [];

  @override
  Future<bool> processPendingOwnerActions() async => true;
  @override
  Future<void> syncDashboardForScope(String scope) async =>
      dashboards.add(scope);
  @override
  Future<void> syncExpensesForScope(String scope) async => expenses.add(scope);
}

void main() {
  late Directory tempDir;
  late LocalCacheService cache;
  late _Orders orders;
  late _Owner owner;
  late SyncEngine engine;

  Future<void> signIn({
    required String role,
    required List<String> outlets,
  }) async {
    await cache.setActiveStoreId('store-1');
    await cache.setCachedStoreDetails({
      'storeId': 'store-1',
      'storeName': 'Store',
      'role': role,
    });
    await cache.setAllowedOutletsForStore('store-1', [
      for (final id in outlets) {'id': id, 'displayName': id},
    ]);
  }

  Future<void> cacheScope(String scope) async {
    await cache.setCachedOrdersForScope(scope, []);
    await cache.setCachedDashboardMetricsForScope(scope, {'todaySales': 1});
    await cache.setCachedExpensesForScope(scope, []);
  }

  Future<void> syncAndSettle() async {
    await engine.trigger();
    // The backfill runs in the background after the sync completes.
    await pumpEventQueue();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_backfill_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    cache = LocalCacheService();
    ConnectivityService.instance = _Online(false);
    orders = _Orders(cache);
    owner = _Owner();
    engine = SyncEngine.internal(
      ordersRepository: orders,
      ownerRepository: owner,
      localCache: cache,
    );
  });

  tearDown(() async {
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'an owner signed in before per-outlet sync gets every scope filled',
    () async {
      await signIn(role: 'OWNER', outlets: ['o1', 'o2']);

      await syncAndSettle();

      expect(orders.scopes.toSet(), {'all', 'o1', 'o2'});
      expect(owner.dashboards.toSet(), {'all', 'o1', 'o2'});
      expect(owner.expenses.toSet(), {'all', 'o1', 'o2'});
    },
  );

  test('an outlet added later is the only one fetched', () async {
    await signIn(role: 'OWNER', outlets: ['o1', 'o2', 'o3']);
    await cacheScope('all');
    await cacheScope('o1');
    await cacheScope('o2');

    await syncAndSettle();

    expect(orders.scopes, ['o3']);
    expect(owner.dashboards, ['o3']);
    expect(owner.expenses, ['o3']);
  });

  test('nothing to do when every scope is already on the phone', () async {
    await signIn(role: 'OWNER', outlets: ['o1', 'o2']);
    for (final s in ['all', 'o1', 'o2']) {
      await cacheScope(s);
    }

    await syncAndSettle();

    expect(orders.scopes, isEmpty);
  });

  test('an employee is never backfilled', () async {
    await signIn(role: 'EMPLOYEE', outlets: ['o1', 'o2']);

    await syncAndSettle();
    expect(orders.scopes, isEmpty);

    // Control: same engine, same trigger — only the role differs.
    await signIn(role: 'OWNER', outlets: ['o1', 'o2']);
    await syncAndSettle();
    expect(orders.scopes.toSet(), {'all', 'o1', 'o2'});
  });

  test('an owner with one outlet is never backfilled', () async {
    await signIn(role: 'OWNER', outlets: ['o1']);

    await syncAndSettle();
    expect(orders.scopes, isEmpty);

    // Control: same engine, same trigger — once a second outlet exists the
    // backfill does run, so the empty result above was the guard's doing.
    await signIn(role: 'OWNER', outlets: ['o1', 'o2']);
    await syncAndSettle();
    expect(orders.scopes.toSet(), {'all', 'o1', 'o2'});
  });

  test('nothing is fetched while offline', () async {
    await signIn(role: 'OWNER', outlets: ['o1', 'o2']);
    ConnectivityService.instance = _Online(true);

    await syncAndSettle();
    expect(orders.scopes, isEmpty);

    // Control: same engine, same trigger — back online it does run.
    ConnectivityService.instance = _Online(false);
    await syncAndSettle();
    expect(orders.scopes.toSet(), {'all', 'o1', 'o2'});
  });
}
