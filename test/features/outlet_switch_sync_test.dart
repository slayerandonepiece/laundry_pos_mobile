import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class FakeApiClient implements ApiClient {
  final Map<String, dynamic> responses = {};
  int getCallCount = 0;
  int postCallCount = 0;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getCallCount++;
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) {
        return entry.value;
      }
    }
    return {'orders': [], 'nextCursor': null};
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    postCallCount++;
    return {'results': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late LocalCacheService localCache;
  late FakeConnectivityService fakeConnectivity;
  late FakeApiClient fakeApiClient;
  late OrdersRepository ordersRepo;
  late OwnerRepository ownerRepo;
  late SyncEngine syncEngine;
  late OutletScopeCubit outletScopeCubit;
  late OrdersBloc ordersBloc;

  setUp(() async {
    SyncFreshness.reset();
    tempDir = await Directory.systemTemp.createTemp(
      'hive_outlet_switch_sync_test_',
    );
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    fakeConnectivity = FakeConnectivityService(mockOffline: false);
    ConnectivityService.instance = fakeConnectivity;
    fakeApiClient = FakeApiClient();

    ordersRepo = OrdersRepository(
      apiClient: fakeApiClient,
      localCache: localCache,
    );
    ownerRepo = OwnerRepository(
      apiClient: fakeApiClient,
      localCache: localCache,
    );
    syncEngine = SyncEngine.internal(
      ordersRepository: ordersRepo,
      ownerRepository: ownerRepo,
      localCache: localCache,
    );
    SyncEngine.instance = syncEngine;

    // Set up active store and allowed outlets
    await localCache.setActiveStoreId('store-1');
    await localCache.setAllowedOutletsForStore('store-1', [
      {
        'id': 'outlet-a',
        'outletCode': 'OA',
        'displayName': 'Outlet A',
        'isDefault': true,
        'status': 'ACTIVE',
      },
      {
        'id': 'outlet-b',
        'outletCode': 'OB',
        'displayName': 'Outlet B',
        'isDefault': false,
        'status': 'ACTIVE',
      },
    ]);
    await localCache.setCachedStoreDetails({'role': 'OWNER'});
    await localCache.setActiveOutletId('outlet-a');
    await localCache.setAllOutletsScope(false);

    outletScopeCubit = OutletScopeCubit(localCache: localCache)..hydrate();
    ordersBloc = OrdersBloc(ordersRepository: ordersRepo);
  });

  tearDown(() async {
    await ordersBloc.close();
    await outletScopeCubit.close();
    ConnectivityService.instance = ConnectivityService.internal();
    SyncManager.instance.completeSync();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('F1 — Outlet switch sync banner tests', () {
    test('with cache for outlet B, switching A to B never emits SyncStatus.syncing', () async {
      // Seed cache for outlet B
      await localCache.setActiveOutletId('outlet-b');
      await localCache.setCachedOrders([
        {
          'id': 'EL-201',
          'outletId': 'outlet-b',
          'name': 'Customer B',
          'phone': '9876543210',
          'status': 'Pending',
          'createdAt': '2026-09-20T10:00:00Z',
          'lines': [],
          'payments': [],
        },
      ]);
      expect(ordersRepo.hasCachedOrders(), isTrue);

      // Switch back to outlet A
      await localCache.setActiveOutletId('outlet-a');
      outletScopeCubit.hydrate();

      // Listen to all SyncManager status emissions
      final statuses = <SyncStatus>[];
      final messages = <String>[];
      void listener() {
        statuses.add(SyncManager.instance.value.status);
        if (SyncManager.instance.value.message != null) {
          messages.add(SyncManager.instance.value.message!);
        }
      }

      SyncManager.instance.addListener(listener);

      try {
        // Switch from A to B
        outletScopeCubit.select('outlet-b');
        ordersBloc.add(LoadOrdersEvent());

        // Wait for bloc to process load
        await ordersBloc.stream.firstWhere((s) => s.allOrders.isNotEmpty);

        expect(statuses, isNot(contains(SyncStatus.syncing)));
        expect(ordersBloc.state.allOrders.first.id, 'EL-201');
      } finally {
        SyncManager.instance.removeListener(listener);
      }
    });

    test(
      'without cache for outlet B, switching A to B emits SyncStatus.syncing',
      () async {
        // Outlet B has no cache
        await localCache.setActiveOutletId('outlet-b');
        expect(ordersRepo.hasCachedOrders(), isFalse);

        // Switch back to outlet A
        await localCache.setActiveOutletId('outlet-a');
        outletScopeCubit.hydrate();

        final statuses = <SyncStatus>[];
        final messages = <String>[];
        void listener() {
          statuses.add(SyncManager.instance.value.status);
          if (SyncManager.instance.value.message != null) {
            messages.add(SyncManager.instance.value.message!);
          }
        }

        SyncManager.instance.addListener(listener);

        try {
          // Switch from A to B
          outletScopeCubit.select('outlet-b');
          ordersBloc.add(LoadOrdersEvent());

          await ordersBloc.stream.firstWhere((s) => !s.isLoading);

          expect(statuses, contains(SyncStatus.syncing));
          expect(messages, contains('Fetching latest from cloud...'));
        } finally {
          SyncManager.instance.removeListener(listener);
        }
      },
    );

    test(
      'pending queue > 0 still shows "Saving changes to cloud..."',
      () async {
        // Outlet B has cache, but has pending sync items
        await localCache.setActiveOutletId('outlet-b');
        await localCache.setCachedOrders([
          {
            'id': 'EL-202',
            'outletId': 'outlet-b',
            'name': 'Customer B2',
            'phone': '9876543210',
            'status': 'Pending',
            'createdAt': '2026-09-20T10:00:00Z',
            'lines': [],
            'payments': [],
          },
        ]);
        await localCache.setPendingSyncQueue([
          {
            'type': 'create_order',
            'clientActionId': 'action-1',
            'outletId': 'outlet-b',
            'storeId': 'store-1',
            'body': {'name': 'Queued Order'},
          },
        ]);

        expect(localCache.getTotalPendingCount(), 1);
        expect(ordersRepo.hasCachedOrders(), isTrue);

        final statuses = <SyncStatus>[];
        final messages = <String>[];
        void listener() {
          statuses.add(SyncManager.instance.value.status);
          if (SyncManager.instance.value.message != null) {
            messages.add(SyncManager.instance.value.message!);
          }
        }

        SyncManager.instance.addListener(listener);

        try {
          outletScopeCubit.select('outlet-b');
          ordersBloc.add(LoadOrdersEvent());

          await ordersBloc.stream.firstWhere((s) => s.allOrders.isNotEmpty);
          await Future<void>.delayed(const Duration(milliseconds: 50));

          expect(statuses, contains(SyncStatus.syncing));
          expect(messages, contains('Saving changes to cloud...'));
        } finally {
          SyncManager.instance.removeListener(listener);
        }
      },
    );
  });
}
