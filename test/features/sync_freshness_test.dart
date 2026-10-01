import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

class _CountingSyncEngine extends SyncEngine {
  _CountingSyncEngine({super.localCache}) : super.internal();
  int triggers = 0;

  @override
  Future<void> trigger() async => triggers++;
}

/// Only what the dashboard load touches; everything else is unused here.
class _DashboardRepo implements OwnerRepository {
  _DashboardRepo(this.error);
  final Object error;
  int calls = 0;

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => null;

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async {
    calls++;
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SyncFreshness', () {
    tearDown(SyncFreshness.reset);

    test('is fresh right after a sync and not before or after a reset', () {
      SyncFreshness.reset();
      expect(SyncFreshness.isFresh, isFalse);
      SyncFreshness.mark();
      expect(SyncFreshness.isFresh, isTrue);
      SyncFreshness.reset();
      expect(SyncFreshness.isFresh, isFalse);
    });
  });

  group('Opening the Orders screen', () {
    late Directory tempDir;
    late LocalCacheService cache;
    late OrdersBloc bloc;
    late _CountingSyncEngine engine;
    late SyncEngine original;

    setUp(() async {
      SyncFreshness.reset();
      tempDir = await Directory.systemTemp.createTemp('hive_freshness_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalCacheService.boxName);
      cache = LocalCacheService();
      await cache.setActiveStoreId('store-1');
      await cache.setActiveOutletId('outlet-a');
      await cache.setCachedOrders([
        {'id': 'EL-1', 'status': 'Pending', 'payments': <dynamic>[]},
      ]);
      bloc = OrdersBloc(
        ordersRepository: OrdersRepository(
          apiClient: ApiClient(),
          localCache: cache,
        ),
      );
      original = SyncEngine.instance;
      engine = _CountingSyncEngine();
      SyncEngine.instance = engine;
    });

    tearDown(() async {
      SyncEngine.instance = original;
      SyncFreshness.reset();
      await bloc.close();
      await Hive.box(LocalCacheService.boxName).close();
      await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test(
      'with cached orders and nothing synced lately, it refreshes quietly',
      () async {
        bloc.add(LoadOrdersEvent());
        await bloc.stream.firstWhere((s) => s.allOrders.isNotEmpty);
        await Future<void>.delayed(Duration.zero);

        expect(engine.triggers, 1);
      },
    );

    test('straight after a sync, it shows the cache and asks the server for nothing', () async {
      SyncFreshness.mark();

      bloc.add(LoadOrdersEvent());
      await bloc.stream.firstWhere((s) => s.allOrders.isNotEmpty);
      await Future<void>.delayed(Duration.zero);

      expect(engine.triggers, 0);
    });
  });

  group('Dashboard load after the session is gone', () {
    test('a 401 sets no "try again" message', () async {
      final repo = _DashboardRepo(
        AuthException(code: 'UNAUTHENTICATED', statusCode: 401),
      );
      final bloc = OwnerBloc(ownerRepository: repo);
      addTearDown(bloc.close);

      bloc.add(LoadDashboardEvent(refresh: true));
      await pumpEventQueue();

      // The handler really ran and failed; it just says nothing about it.
      expect(repo.calls, 1);
      expect(bloc.state.error, isNull);
      expect(bloc.state.messageSection, isNull);
    });

    test('any other failure still tells the user', () async {
      final repo = _DashboardRepo(Exception('server on fire'));
      final bloc = OwnerBloc(ownerRepository: repo);
      addTearDown(bloc.close);

      bloc.add(LoadDashboardEvent(refresh: true));
      await pumpEventQueue();

      expect(repo.calls, 1);
      expect(bloc.state.error, 'Could not load dashboard — try again');
    });
  });

  group('App resume', () {
    late Directory tempDir;
    late LocalCacheService cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_resume_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalCacheService.boxName);
      cache = LocalCacheService();
      SyncFreshness.reset();
    });

    tearDown(() async {
      SyncFreshness.reset();
      await Hive.box(LocalCacheService.boxName).close();
      await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('syncs when the data is stale', () async {
      final engine = _CountingSyncEngine(localCache: cache);
      await engine.triggerIfStale();
      expect(engine.triggers, 1);
    });

    test('does nothing right after a sync with nothing queued', () async {
      final engine = _CountingSyncEngine(localCache: cache);
      SyncFreshness.mark();
      await engine.triggerIfStale();
      expect(engine.triggers, 0);
    });

    test('still syncs when fresh but changes are waiting to be sent', () async {
      final engine = _CountingSyncEngine(localCache: cache);
      SyncFreshness.mark();
      await cache.enqueueSyncAction({'id': 'p1', 'type': 'order'});
      await engine.triggerIfStale();
      expect(engine.triggers, 1);
    });
  });
}
