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
  });
}
