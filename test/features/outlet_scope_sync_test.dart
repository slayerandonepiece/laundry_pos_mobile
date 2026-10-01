import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

class _Call {
  final String url;
  final Map<String, String>? headers;
  _Call(this.url, this.headers);
}

class _RecordingApiClient implements ApiClient {
  final List<_Call> calls = [];
  final Map<String, dynamic> responses = {};

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(_Call(url, headers));
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    throw Exception('Unhandled URL: $url');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Two pages: the first names a next cursor, the second ends the run.
class _PagedApiClient implements ApiClient {
  int _page = 0;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    _page++;
    return {
      'orders': [
        {'id': 'EL-$_page', 'status': 'Pending', 'payments': []},
      ],
      'nextCursor': _page == 1 ? 'page-1' : null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late LocalCacheService cache;

  final outlets = [
    {
      'id': 'o1',
      'outletCode': 'A1',
      'displayName': 'Main Road',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'o2',
      'outletCode': 'A2',
      'displayName': 'Lake View',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  Map<String, dynamic> order(String id) => {
    'id': id,
    'status': 'Pending',
    'payments': <Map<String, dynamic>>[],
  };

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_scope_sync_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    cache = LocalCacheService();
    await cache.setActiveStoreId('store_a');
  });

  tearDown(() async {
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('LocalCacheService named scopes', () {
    test(
      'a named scope reads and writes without touching the active one',
      () async {
        await cache.setActiveOutletId('o1');
        await cache.setCachedOrders([order('EL-1')]);

        await cache.setCachedOrdersForScope('o2', [
          order('EL-2'),
          order('EL-3'),
        ]);
        await cache.setLastSyncCursorForScope('o2', 'cur-2');

        expect(cache.getCachedOrders()!.map((o) => o['id']), ['EL-1']);
        expect(cache.getLastSyncCursor(), isNull);
        expect(cache.getCachedOrdersForScope('o2')!.length, 2);
        expect(cache.getLastSyncCursorForScope('o2'), 'cur-2');
        expect(
          cache.hasCachedOrdersFor(outletId: 'o2', allOutlets: false),
          isTrue,
        );
        expect(
          cache.hasCachedOrdersFor(outletId: null, allOutlets: true),
          isFalse,
        );
      },
    );

    test(
      'clearing one scope leaves other scopes and the pending queues alone',
      () async {
        for (final scope in ['o1', 'o2', LocalCacheService.allScope]) {
          await cache.setCachedOrdersForScope(scope, [order('EL-$scope')]);
          await cache.setLastSyncCursorForScope(scope, 'cur-$scope');
          await cache.setCachedDashboardMetricsForScope(scope, {
            'todaySales': 1,
          });
          await cache.setCachedExpensesForScope(scope, [<String, dynamic>{}]);
        }
        await cache.setPendingSyncQueue([
          {'clientActionId': 'a1', 'type': 'update_status', 'outletId': 'o2'},
        ]);
        await cache.setDeadLetterQueue([
          {'clientActionId': 'd1'},
        ]);

        await cache.clearScopeData('o2');

        expect(cache.getCachedOrdersForScope('o2'), isNull);
        expect(cache.getLastSyncCursorForScope('o2'), isNull);
        expect(cache.getCachedDashboardMetricsForScope('o2'), isNull);
        expect(cache.getCachedExpensesForScope('o2'), isNull);
        for (final scope in ['o1', LocalCacheService.allScope]) {
          expect(
            cache.getCachedOrdersForScope(scope),
            isNotNull,
            reason: scope,
          );
          expect(
            cache.getLastSyncCursorForScope(scope),
            isNotNull,
            reason: scope,
          );
          expect(cache.getCachedDashboardMetricsForScope(scope), isNotNull);
          expect(cache.getCachedExpensesForScope(scope), isNotNull);
        }
        expect(cache.getPendingSyncQueue().length, 1);
        expect(cache.getDeadLetterQueue().length, 1);
      },
    );
  });

  group('Sign-in sync by explicit scope', () {
    test(
      'orders: an outlet is fetched with its own header into its own cache',
      () async {
        await cache.setActiveOutletId('o1');
        final api = _RecordingApiClient()
          ..responses['orders/sync'] = {
            'orders': [order('EL-9')],
            'nextCursor': null,
          };
        final repo = OrdersRepository(apiClient: api, localCache: cache);

        await repo.syncOrdersForScope('o2');

        expect(api.calls.single.headers, {'X-Outlet-Id': 'o2'});
        expect(cache.getCachedOrdersForScope('o2')!.single['id'], 'EL-9');
        // The active outlet's cache is untouched.
        expect(cache.getCachedOrders(), isNull);
      },
    );

    test('orders: the combined scope omits the outlet header', () async {
      final api = _RecordingApiClient()
        ..responses['orders/sync'] = {'orders': [], 'nextCursor': null};
      final repo = OrdersRepository(apiClient: api, localCache: cache);

      await repo.syncOrdersForScope(LocalCacheService.allScope);

      expect(api.calls.single.headers, {'X-Outlet-Id': kNoOutletHeader});
      expect(
        cache.hasCachedOrdersFor(outletId: null, allOutlets: true),
        isTrue,
      );
    });

    test(
      'orders: pages are followed and the cursor is kept per scope',
      () async {
        final repo = OrdersRepository(
          apiClient: _PagedApiClient(),
          localCache: cache,
        );

        await repo.syncOrdersForScope('o2');

        expect(cache.getCachedOrdersForScope('o2')!.length, 2);
        expect(cache.getLastSyncCursorForScope('o2'), 'page-1');
        expect(cache.getLastSyncCursorForScope('o1'), isNull);
      },
    );

    test(
      'dashboard and expenses: fetched for the outlet, cached under it',
      () async {
        final api = _RecordingApiClient()
          ..responses['dashboard'] = {'todaySales': 500}
          ..responses['expenses'] = [];
        final owner = OwnerRepository(apiClient: api, localCache: cache);

        await owner.syncDashboardForScope('o2');
        await owner.syncExpensesForScope('o2');

        expect(api.calls[0].url, contains('outletId=o2'));
        expect(api.calls[0].url, contains('granularity=day'));
        expect(api.calls[0].headers, {'X-Outlet-Id': 'o2'});
        expect(api.calls[1].headers, {'X-Outlet-Id': 'o2'});
        expect(cache.getCachedDashboardMetricsForScope('o2'), isNotNull);
        expect(cache.getCachedExpensesForScope('o2'), isNotNull);
        expect(cache.getCachedDashboardMetrics(), isNull); // active scope
      },
    );

    test('dashboard: the combined scope sends no outlet at all', () async {
      final api = _RecordingApiClient()
        ..responses['dashboard'] = {'todaySales': 500};
      final owner = OwnerRepository(apiClient: api, localCache: cache);

      await owner.syncDashboardForScope(LocalCacheService.allScope);

      expect(api.calls.single.url, isNot(contains('outletId')));
      expect(api.calls.single.headers, {'X-Outlet-Id': kNoOutletHeader});
      expect(
        cache.getCachedDashboardMetricsForScope(LocalCacheService.allScope),
        isNotNull,
      );
    });
  });

  group('Employee switching outlets', () {
    late OutletScopeCubit cubit;

    setUp(() async {
      cubit = OutletScopeCubit(localCache: cache);
      await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      await cache.setAllowedOutletsForStore('store_a', outlets);
      await cache.setActiveOutletId('o1');
      await cache.setCachedOrders([order('EL-1')]);
      await cache.setLastSyncCursor('cur-1');
    });

    tearDown(() => cubit.close());

    test(
      'clears the outgoing outlet, selects the new one, keeps the queue',
      () async {
        await cache.setPendingSyncQueue([
          {'clientActionId': 'a1', 'type': 'update_status', 'outletId': 'o1'},
        ]);
        cubit.hydrate();

        await cubit.selectClearingPrevious('o2');

        expect(cubit.state.activeOutletId, 'o2');
        expect(cache.getCachedOrdersForScope('o1'), isNull);
        expect(cache.getLastSyncCursorForScope('o1'), isNull);
        expect(cache.getCachedOrders(), isNull); // new active outlet: empty
        expect(cache.getPendingSyncQueue().length, 1);
        expect(cubit.hasPendingChanges, isTrue);
      },
    );

    test('picking the same outlet again clears nothing', () async {
      cubit.hydrate();

      await cubit.selectClearingPrevious('o1');

      expect(cache.getCachedOrdersForScope('o1'), isNotNull);
      expect(cubit.state.activeOutletId, 'o1');
    });

    test('a first pick with no previous outlet clears nothing', () async {
      await cache.setCachedOrdersForScope('o1', [order('EL-1')]);
      await cache.clearActiveOutletId();
      cubit.hydrate();

      await cubit.selectClearingPrevious('o2');

      expect(cache.getCachedOrdersForScope('o1'), isNotNull);
      expect(cubit.state.activeOutletId, 'o2');
    });

    test('an owner selecting an outlet does not clear anything', () async {
      await cache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.hydrate();

      cubit.select('o2');

      expect(cache.getCachedOrdersForScope('o1'), isNotNull);
    });
  });
}
