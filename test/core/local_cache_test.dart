import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/storage/local_cache.dart';

void main() {
  late Directory tempDir;
  late LocalCacheService localCache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
  });

  tearDown(() async {
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalCacheService Offline Storage Tests', () {
    test('Stores and retrieves active store id', () async {
      expect(localCache.getActiveStoreId(), isNull);
      await localCache.setActiveStoreId('store_123');
      expect(localCache.getActiveStoreId(), 'store_123');
      await localCache.clearActiveStoreId();
      expect(localCache.getActiveStoreId(), isNull);
    });

    test(
      'Stores and retrieves cached store details and available stores',
      () async {
        final store = {
          'storeId': 's1',
          'storeName': 'Indiranagar QuickWash',
          'role': 'EMPLOYEE',
        };
        final stores = [
          store,
          {
            'storeId': 's2',
            'storeName': 'Koramangala Branch',
            'role': 'EMPLOYEE',
          },
        ];

        await localCache.setCachedStoreDetails(store);
        await localCache.setCachedAvailableStores(stores);

        expect(
          localCache.getCachedStoreDetails()?['storeName'],
          'Indiranagar QuickWash',
        );
        expect(localCache.getCachedAvailableStores()?.length, 2);
      },
    );

    test('Stores and retrieves cached products and orders', () async {
      final products = [
        {'id': 'p1', 'name': 'Wash & Fold', 'price': 12000, 'unit': 'WEIGHT'},
        {'id': 'p2', 'name': 'Dry Clean Suit', 'price': 35000, 'unit': 'PIECE'},
      ];
      final orders = [
        {
          'id': 'EL-101',
          'name': 'Ankit Sharma',
          'phone': '9876543210',
          'status': 'Pending',
          'lines': [],
          'payments': [],
        },
      ];

      await localCache.setCachedProducts(products);
      await localCache.setCachedOrders(orders);

      expect(localCache.getCachedProducts()?.length, 2);
      expect(localCache.getCachedProducts()?.first['name'], 'Wash & Fold');

      expect(localCache.getCachedOrders()?.length, 1);
      expect(localCache.getCachedOrders()?.first['id'], 'EL-101');
    });

    test('Enqueues and retrieves offline sync queue actions', () async {
      expect(localCache.getPendingSyncQueue(), isEmpty);

      await localCache.enqueueSyncAction({
        'type': 'update_status',
        'orderCode': 'EL-101',
        'status': 'Ready',
      });
      await localCache.enqueueSyncAction({
        'type': 'record_payment',
        'orderCode': 'EL-101',
        'amount': 12000,
        'method': 'Cash',
      });

      final queue = localCache.getPendingSyncQueue();
      expect(queue.length, 2);
      expect(queue[0]['type'], 'update_status');
      expect(queue[1]['type'], 'record_payment');

      await localCache.clearPendingSyncQueue();
      expect(localCache.getPendingSyncQueue(), isEmpty);
    });

    test('Stores and retrieves cached owner data (metrics, expenses, staff, payment methods)', () async {
      final metrics = {
        'todaySales': 45000,
        'todayCount': 3,
        'periodSales': 150000,
        'periodOrders': 12,
        'todo': 4,
        'completed': 8,
        'outstanding': 20000,
        'overdue': 1,
        'dueToday': 2,
        'serviceMix': [
          {'label': 'Wash & Iron', 'amount': 25000},
        ],
        'cash': [
          {'label': 'Mon', 'income': 20000, 'expenses': 5000},
        ],
      };
      final expenses = [
        {
          'id': 'exp-1',
          'title': 'Detergent 50kg',
          'category': 'Supplies',
          'amount': 3500,
          'due': '2026-09-12',
          'paid': '2026-09-12',
          'monthly': false,
        },
      ];
      final staff = [
        {
          'id': 'st-1',
          'name': 'Ramesh Kumar',
          'phone': 'ramesh',
          'active': true,
        },
      ];
      final paymentMethods = [
        {'id': 'pm-cash', 'name': 'Cash', 'type': 'Cash', 'active': true},
        {'id': 'pm-upi', 'name': 'Store UPI', 'type': 'UPI', 'active': true},
      ];

      expect(localCache.getCachedDashboardMetrics(), isNull);
      expect(localCache.getCachedExpenses(), isNull);
      expect(localCache.getCachedStaff(), isNull);
      expect(localCache.getCachedPaymentMethods(), isNull);

      await localCache.setCachedDashboardMetrics(metrics);
      await localCache.setCachedExpenses(expenses);
      await localCache.setCachedStaff(staff);
      await localCache.setCachedPaymentMethods(paymentMethods);

      final cachedMetrics = localCache.getCachedDashboardMetrics();
      expect(cachedMetrics, isNotNull);
      expect(cachedMetrics?['todaySales'], 45000);
      expect(
        (cachedMetrics?['serviceMix'] as List).first['label'],
        'Wash & Iron',
      );

      final cachedExpenses = localCache.getCachedExpenses();
      expect(cachedExpenses?.length, 1);
      expect(cachedExpenses?.first['title'], 'Detergent 50kg');

      final cachedStaff = localCache.getCachedStaff();
      expect(cachedStaff?.length, 1);
      expect(cachedStaff?.first['name'], 'Ramesh Kumar');

      final cachedMethods = localCache.getCachedPaymentMethods();
      expect(cachedMethods?.length, 2);
      expect(cachedMethods?.last['name'], 'Store UPI');
    });

    test('Outlet scope keys are store-scoped and independent', () async {
      expect(localCache.getAllowedOutlets(), isNull);
      expect(localCache.getActiveOutletId(), isNull);
      expect(localCache.isAllOutletsScope(), isFalse);

      await localCache.setActiveStoreId('store_a');
      await localCache.setAllowedOutletsForStore('store_a', [
        {
          'id': 'outlet_1',
          'outletCode': 'OBLRCHN01',
          'displayName': 'Chinnapanahalli',
          'isDefault': true,
          'status': 'ACTIVE',
        },
      ]);
      expect(localCache.getAllowedOutlets()?.length, 1);
      expect(localCache.getAllowedOutlets()?.first['displayName'], 'Chinnapanahalli');

      await localCache.setActiveOutletId('outlet_1');
      expect(localCache.getActiveOutletId(), 'outlet_1');
      expect(localCache.isAllOutletsScope(), isFalse);

      await localCache.setAllOutletsScope(true);
      expect(localCache.isAllOutletsScope(), isTrue);

      // Switching the active store must not see store_a's outlets/selection.
      await localCache.setActiveStoreId('store_b');
      expect(localCache.getAllowedOutlets(), isNull);
      expect(localCache.getActiveOutletId(), isNull);
      expect(localCache.isAllOutletsScope(), isFalse);

      // Switching back to store_a finds its outlet selection untouched.
      await localCache.setActiveStoreId('store_a');
      expect(localCache.getActiveOutletId(), 'outlet_1');
      await localCache.clearActiveOutletId();
      expect(localCache.getActiveOutletId(), isNull);
    });

    test(
      'Cached orders/dashboard metrics/sync cursor are scoped per outlet',
      () async {
        await localCache.setActiveStoreId('store_a');
        await localCache.setActiveOutletId('outlet_1');
        await localCache.setCachedOrders([
          {'id': 'EL-1', 'name': 'Outlet 1 order'},
        ]);
        await localCache.setCachedDashboardMetrics({'todaySales': 1000});
        await localCache.setLastSyncCursor('cursor-outlet-1');

        await localCache.setActiveOutletId('outlet_2');
        expect(localCache.getCachedOrders(), isNull);
        expect(localCache.getCachedDashboardMetrics(), isNull);
        expect(localCache.getLastSyncCursor(), isNull);

        await localCache.setActiveOutletId('outlet_1');
        expect(localCache.getCachedOrders()?.first['id'], 'EL-1');
        expect(localCache.getCachedDashboardMetrics()?['todaySales'], 1000);
        expect(localCache.getLastSyncCursor(), 'cursor-outlet-1');
      },
    );
  });

  group('Two ids per order', () {
    test(
      'migrateLegacyOfflineIds moves LOCAL-/OFF- ids to offlineId, once',
      () async {
        final box = Hive.box(LocalCacheService.boxName);
        const ordersKey = '${LocalCacheService.keyCachedOrders}::s1::o1';
        await box.put(ordersKey, [
          {'id': 'LOCAL-1', 'status': 'Pending'},
          {'id': 'OFF-2', 'status': 'Pending'},
          {'id': 'EL-3', 'status': 'Ready'},
        ]);
        final legacyCreate = {
          'type': 'create_order',
          'clientActionId': 'c1',
          'offlineCode': 'LOCAL-1',
          'body': {'phone': '9000000000'},
        };
        final status = {
          'type': 'update_status',
          'clientActionId': 's1',
          'orderCode': 'LOCAL-1',
          'status': 'Ready',
        };
        await box.put(LocalCacheService.keyPendingSyncQueue, [
          legacyCreate,
          status,
        ]);
        await box.put(LocalCacheService.keyDeadLetterQueue, [legacyCreate]);

        await LocalCacheService.migrateLegacyOfflineIds(box);
        await LocalCacheService.migrateLegacyOfflineIds(box);

        final orders = (box.get(ordersKey) as List)
            .map((e) => LocalCacheService.deepCopy(e) as Map<String, dynamic>)
            .toList();
        expect(orders[0], {
          'id': '',
          'offlineId': 'LOCAL-1',
          'status': 'Pending',
        });
        expect(orders[1], {
          'id': '',
          'offlineId': 'OFF-2',
          'status': 'Pending',
        });
        expect(orders[2], {'id': 'EL-3', 'status': 'Ready'});

        final pending = localCache.getPendingSyncQueue();
        expect(pending[0]['body'], {
          'phone': '9000000000',
          'offlineId': 'LOCAL-1',
        });
        // Status/payment actions keep their ref — it now equals the offlineId.
        expect(pending[1]['orderCode'], 'LOCAL-1');
        expect(
          localCache.getDeadLetterQueue().single['body']['offlineId'],
          'LOCAL-1',
        );
      },
    );

    test('dedupeOrdersById collapses rows sharing an id or an offlineId', () {
      final result = LocalCacheService.dedupeOrdersById([
        {'id': '', 'offlineId': 'u1', 'v': 'old'},
        {'id': 'EL-1', 'offlineId': 'u1', 'v': 'new'},
        {'id': 'EL-2', 'v': 'a'},
        {'id': 'EL-2', 'v': 'b'},
        {'id': '', 'offlineId': 'u3'},
      ]);
      expect(result, [
        {'id': 'EL-1', 'offlineId': 'u1', 'v': 'new'},
        {'id': 'EL-2', 'v': 'b'},
        {'id': '', 'offlineId': 'u3'},
      ]);
    });

    test('findSyncedIdByOfflineId looks across outlet scopes', () async {
      final box = Hive.box(LocalCacheService.boxName);
      await box.put('${LocalCacheService.keyCachedOrders}::s1::o2', [
        {'id': 'EL-9', 'offlineId': 'u9'},
        {'id': '', 'offlineId': 'u10'},
      ]);
      expect(localCache.findSyncedIdByOfflineId('u9'), 'EL-9');
      expect(localCache.findSyncedIdByOfflineId('u10'), isNull);
      expect(localCache.findSyncedIdByOfflineId('nope'), isNull);
    });
  });
}
