import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

import '../helpers/mock_dio.dart';

class MockApiClient extends ApiClient {
  dynamic getResponse;
  dynamic postResponse;
  Future<dynamic> Function(String url)? onGet;
  int getCallCount = 0;
  int postCallCount = 0;
  dynamic lastPostBody;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getCallCount++;
    if (onGet != null) return onGet!(url);
    return getResponse;
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    postCallCount++;
    lastPostBody = body;
    return postResponse;
  }
}

class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

void main() {
  late Directory tempDir;
  late LocalCacheService localCache;
  late MockApiClient mockApiClient;
  late OrdersRepository repository;
  late FakeConnectivityService fakeConnectivity;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sync_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    await localCache.setActiveStoreId('store_1');
    mockApiClient = MockApiClient();
    repository = OrdersRepository(
      apiClient: mockApiClient,
      localCache: localCache,
    );
    fakeConnectivity = FakeConnectivityService(mockOffline: false);
    ConnectivityService.instance = fakeConnectivity;
    SyncEngine.instance = SyncEngine.internal(
      ordersRepository: repository,
      localCache: localCache,
    );
  });

  tearDown(() async {
    SyncEngine.instance = SyncEngine.internal();
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('syncOrdersDelta Reconciliation Tests', () {
    test(
      'drops update_status action when server order has matching status',
      () async {
        await localCache.setPendingSyncQueue([
          {
            'type': 'update_status',
            'clientActionId': 'act_status_1',
            'orderCode': 'EL-1001',
            'status': 'Ready',
          },
        ]);

        mockApiClient.getResponse = {
          'orders': [
            {'id': 'EL-1001', 'status': 'Ready', 'payments': []},
          ],
          'nextCursor': null,
        };

        final ok = await repository.syncOrdersDelta();
        expect(ok, isTrue);

        final queue = localCache.getPendingSyncQueue();
        expect(queue, isEmpty);
      },
    );

    test('retains update_status action if server status differs', () async {
      await localCache.setPendingSyncQueue([
        {
          'type': 'update_status',
          'clientActionId': 'act_status_2',
          'orderCode': 'EL-1001',
          'status': 'Delivered',
        },
      ]);

      mockApiClient.getResponse = {
        'orders': [
          {'id': 'EL-1001', 'status': 'Ready', 'payments': []},
        ],
        'nextCursor': null,
      };

      final ok = await repository.syncOrdersDelta();
      expect(ok, isTrue);

      final queue = localCache.getPendingSyncQueue();
      expect(queue.length, 1);
      expect(queue.first['clientActionId'], 'act_status_2');
    });

    test('drops record_payment by 1-to-1 match (amount + method + date) and keeps second identical payment', () async {
      final now = DateTime.now();
      await localCache.setPendingSyncQueue([
        {
          'type': 'record_payment',
          'clientActionId': 'act_pay_1',
          'orderCode': 'EL-1001',
          'amount': 500,
          'method': 'Cash',
          'queuedAt': now.toIso8601String(),
        },
        {
          'type': 'record_payment',
          'clientActionId': 'act_pay_2',
          'orderCode': 'EL-1001',
          'amount': 500,
          'method': 'Cash',
          'queuedAt': now.toIso8601String(),
        },
      ]);

      // Server only has ONE payment recorded so far
      mockApiClient.getResponse = {
        'orders': [
          {
            'id': 'EL-1001',
            'status': 'Pending',
            'payments': [
              {
                'id': 'srv_pay_999',
                'amount': 500,
                'method': 'Cash',
                'date':
                    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              },
            ],
          },
        ],
        'nextCursor': null,
      };

      final ok = await repository.syncOrdersDelta();
      expect(ok, isTrue);

      final queue = localCache.getPendingSyncQueue();
      // Only one action should have been dropped; the second must remain queued
      expect(queue.length, 1);
      expect(queue.first['clientActionId'], 'act_pay_2');
    });

    test(
      'drops record_payment when server echoes matching clientActionId',
      () async {
        await localCache.setPendingSyncQueue([
          {
            'type': 'record_payment',
            'clientActionId': 'act_pay_echo',
            'orderCode': 'EL-1001',
            'amount': 300,
            'method': 'UPI',
          },
        ]);

        mockApiClient.getResponse = {
          'orders': [
            {
              'id': 'EL-1001',
              'status': 'Pending',
              'payments': [
                {
                  'id': 'srv_pay_1',
                  'clientActionId': 'act_pay_echo',
                  'amount': 300,
                  'method': 'UPI',
                  'date': '2026-09-11',
                },
              ],
            },
          ],
          'nextCursor': null,
        };

        final ok = await repository.syncOrdersDelta();
        expect(ok, isTrue);

        final queue = localCache.getPendingSyncQueue();
        expect(queue, isEmpty);
      },
    );

    test(
      'drops pending actions when target order was deleted server-side',
      () async {
        await localCache.setPendingSyncQueue([
          {
            'type': 'update_status',
            'clientActionId': 'act_del_1',
            'orderCode': 'EL-1002',
            'status': 'Delivered',
          },
          {
            'type': 'record_payment',
            'clientActionId': 'act_del_2',
            'orderCode': 'EL-1002',
            'amount': 500,
            'method': 'Cash',
          },
        ]);

        mockApiClient.getResponse = {
          'orders': [
            {'id': 'EL-1002', 'deleted': true},
          ],
          'nextCursor': null,
        };

        final ok = await repository.syncOrdersDelta();
        expect(ok, isTrue);

        final queue = localCache.getPendingSyncQueue();
        expect(queue, isEmpty);
      },
    );

    test('dependent actions keep the offline id; the next push sends the server code', () async {
      await localCache.setPendingSyncQueue([
        {
          'type': 'create_order',
          'clientActionId': 'act_create_1',
          'offlineCode': 'off-1001',
          'body': {'phone': '9876543210', 'offlineId': 'off-1001'},
        },
        {
          'type': 'update_status',
          'clientActionId': 'act_status_1',
          'orderCode': 'off-1001',
          'status': 'In Progress',
        },
        {
          'type': 'record_payment',
          'clientActionId': 'act_pay_1',
          'orderCode': 'off-1001',
          'amount': 500,
          'method': 'Cash',
        },
      ]);
      await localCache.setCachedOrders([
        {
          'id': '',
          'offlineId': 'off-1001',
          'phone': '9876543210',
          'isSynced': false,
        },
      ]);

      mockApiClient.postResponse = {
        'results': [
          {
            'clientActionId': 'act_create_1',
            'status': 'success',
            'order': {
              'id': 'EL-50',
              'offlineId': 'off-1001',
              'phone': '9876543210',
              'status': 'Pending',
              'lines': [],
              'payments': [],
            },
          },
          // update_status and record_payment failed or skipped this cycle
          {
            'clientActionId': 'act_status_1',
            'status': 'failed',
            'error': 'Busy',
          },
          {'clientActionId': 'act_pay_1', 'status': 'failed', 'error': 'Busy'},
        ],
      };

      expect(await repository.processPendingSyncQueue(), isTrue);

      final queue = localCache.getPendingSyncQueue();
      expect(queue.any((a) => a['clientActionId'] == 'act_create_1'), isFalse);
      // No rewrite: queued actions keep the offline id they were written with.
      expect(queue.map((a) => a['orderCode']), ['off-1001', 'off-1001']);

      // The placeholder row was filled in, not duplicated.
      final cached = localCache.getCachedOrders()!;
      expect(cached, hasLength(1));
      expect(cached.single['id'], 'EL-50');
      expect(cached.single['offlineId'], 'off-1001');

      // Next push resolves the offline id to the server code.
      mockApiClient.postResponse = {'results': []};
      await repository.processPendingSyncQueue();
      final sent = (mockApiClient.lastPostBody as Map)['actions'] as List;
      expect(sent.map((a) => a['orderRef']), ['EL-50', 'EL-50']);
    });

    test(
      'processPendingSyncQueue increments failCount on failed actions',
      () async {
        await localCache.setPendingSyncQueue([
          {
            'type': 'update_status',
            'clientActionId': 'act_fail_1',
            'orderCode': 'EL-100',
            'status': 'Ready',
          },
        ]);

        mockApiClient.postResponse = {
          'results': [
            {
              'clientActionId': 'act_fail_1',
              'status': 'failed',
              'error': 'Validation failed',
            },
          ],
        };

        await repository.processPendingSyncQueue();
        var queue = localCache.getPendingSyncQueue();
        expect(queue.first['failCount'], 1);
        expect(queue.first['lastError'], 'Validation failed');

        // Second failure increments to 2
        await repository.processPendingSyncQueue();
        queue = localCache.getPendingSyncQueue();
        expect(queue.first['failCount'], 2);
      },
    );

    test('SyncEngine triggers offline state without making network calls when offline', () async {
      fakeConnectivity.mockOffline = true;
      await localCache.setPendingSyncQueue([
        {
          'type': 'update_status',
          'clientActionId': 'act_offline_1',
          'orderCode': 'EL-100',
          'status': 'Ready',
        },
      ]);

      await SyncEngine.instance.trigger();

      // No network calls should be made
      expect(mockApiClient.postCallCount, 0);
      expect(mockApiClient.getCallCount, 0);
      expect(SyncManager.instance.value.isOffline, isTrue);
      expect(SyncManager.instance.value.pendingCount, 1);
    });

    test('SyncEngine escalates to setSyncPaused when failCount >= 3 on successful response', () async {
      fakeConnectivity.mockOffline = false;
      await localCache.setPendingSyncQueue([
        {
          'type': 'update_status',
          'clientActionId': 'act_fail_max',
          'orderCode': 'EL-100',
          'status': 'Ready',
          'failCount': 3,
        },
      ]);

      mockApiClient.postResponse = {
        'results': [
          {
            'clientActionId': 'act_fail_max',
            'status': 'failed',
            'error': 'Repeated failure',
          },
        ],
      };
      mockApiClient.getResponse = {'orders': [], 'nextCursor': null};

      await SyncEngine.instance.trigger();

      expect(SyncManager.instance.value.isSyncPaused, isTrue);
      expect(SyncManager.instance.value.pendingCount, 1);
    });

    test('PosRepository short-circuits API calls when offline and uses cache fallback', () async {
      final posRepo = PosRepository(
        apiClient: mockApiClient,
        localCache: localCache,
      );
      fakeConnectivity.mockOffline = true;

      await localCache.setCachedProducts([
        Product(
          id: 'prod_1',
          name: 'Wash & Fold',
          category: 'Laundry',
          price: 50,
          type: 'ITEM',
        ).toJson(),
      ]);

      final products = await posRepo.listProducts();
      expect(products.length, 1);
      expect(products.first.name, 'Wash & Fold');
      expect(mockApiClient.getCallCount, 0);

      // No cached methods: must not fabricate a Cash/UPI fallback.
      final methods = await posRepo.listPaymentMethods();
      expect(methods, isEmpty);
      expect(mockApiClient.getCallCount, 0);

      await localCache.setCachedPaymentMethods([
        {'id': 'pm_1', 'name': 'Card', 'type': 'Cash', 'active': true},
      ]);
      final cached = await posRepo.listPaymentMethods();
      expect(cached.map((m) => m.name), ['Card']);
    });

    test(
      'createOrderOptimistic puts outletId in queued payload and local order',
      () async {
        final posRepo = PosRepository(
          apiClient: mockApiClient,
          localCache: localCache,
        );
        fakeConnectivity.mockOffline = true;

        final order = await posRepo.createOrderOptimistic(
          idempotencyKey: 'idem_1',
          phone: '9999999999',
          dueDate: '2026-01-01',
          entries: [
            {'productId': 'p1', 'quantity': 1},
          ],
          outletId: 'outlet_A',
        );

        expect(order.outletId, 'outlet_A');
        final queued = localCache
            .getPendingSyncQueue()
            .where((a) => a['type'] == 'create_order')
            .toList();
        expect(queued, hasLength(1));
        expect(queued.first['body']['outletId'], 'outlet_A');
      },
    );

    test('SyncManager pendingOnline state and getters', () {
      final syncManager = SyncManager.instance;
      syncManager.setPendingOnline(2);

      expect(syncManager.value.isPendingOnline, isTrue);
      expect(syncManager.value.isOffline, isFalse);
      expect(syncManager.value.pendingCount, 2);
      expect(syncManager.value.message, '2 changes pending');
    });

    test('ConnectivityService debounces transient disconnections and commits isOffline only after stable duration', () async {
      // The OS "offline" signal alone is no longer trusted — a reachability
      // probe to the backend must ALSO fail before isOffline commits to
      // true (this is the VPN-false-positive fix). Use a fake HTTP client
      // that always fails so the probe resolves "unreachable" fast and
      // deterministically within this test's tight timing windows.
      final unreachableDio = createMockDio((options) async {
        throw const SocketException('unreachable (test)');
      });
      final connectivity = ConnectivityService.internal(
        localCache: localCache,
        debounceDuration: const Duration(milliseconds: 50),
        dio: unreachableDio,
      );
      ConnectivityService.instance = connectivity;

      await localCache.setPendingSyncQueue([
        {'type': 'update_status', 'clientActionId': 'act_1'},
        {'type': 'update_status', 'clientActionId': 'act_2'},
      ]);

      expect(connectivity.isOffline, isFalse);

      // Transient blip: none arrives
      connectivity.handleForTesting([ConnectivityResult.none]);

      // Immediately after event: isOffline must still be false
      expect(connectivity.isOffline, isFalse);
      expect(SyncManager.instance.value.isOffline, isFalse);

      // Within 20ms (< 50ms window), connection returns
      await Future<void>.delayed(const Duration(milliseconds: 20));
      connectivity.handleForTesting([ConnectivityResult.wifi]);

      // Wait beyond initial 50ms window
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Still online, banner never flipped
      expect(connectivity.isOffline, isFalse);
      expect(SyncManager.instance.value.isOffline, isFalse);

      // Now persistent disconnection
      connectivity.handleForTesting([ConnectivityResult.none]);
      expect(connectivity.isOffline, isFalse); // still not flipped immediately

      // Wait for the debounce window to elapse, plus the (fast, always-fails)
      // reachability probe that now runs before isOffline commits to true.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Now committed
      expect(connectivity.isOffline, isTrue);
      expect(SyncManager.instance.value.isOffline, isTrue);
      // Real pending queue count (2) passed
      expect(SyncManager.instance.value.pendingCount, 2);

      connectivity.dispose();
    });

    test('SyncEngine.trigger() awaits retriggered generation when called while sync is in flight', () async {
      fakeConnectivity.mockOffline = false;

      final run1GetCompleter = Completer<void>();
      final run2GetCompleter = Completer<void>();
      var getCount = 0;

      mockApiClient.onGet = (url) async {
        getCount++;
        if (getCount == 1) {
          await run1GetCompleter.future;
          return {
            'orders': [
              {'id': 'EL-RUN1', 'status': 'Pending', 'payments': []},
            ],
            'nextCursor': null,
          };
        } else {
          await run2GetCompleter.future;
          return {
            'orders': [
              {'id': 'EL-RUN2', 'status': 'Delivered', 'payments': []},
            ],
            'nextCursor': null,
          };
        }
      };

      // Run 1 starts
      final run1Future = SyncEngine.instance.trigger();

      // Yield briefly to let run1 enter onGet
      await Future<void>.delayed(Duration.zero);
      expect(SyncEngine.instance.isSyncing, isTrue);

      // While Run 1 is in flight, caller 2 triggers retryNow() (simulating pull-to-refresh)
      var caller2Finished = false;
      final caller2Future = SyncEngine.instance.retryNow().then((_) {
        caller2Finished = true;
      });

      // Yield briefly
      await Future<void>.delayed(Duration.zero);
      expect(caller2Finished, isFalse);

      // Complete Run 1 network call
      run1GetCompleter.complete();
      await run1Future;

      // Run 1 finished, but caller 2 must NOT be finished yet because Run 2 is running
      expect(caller2Finished, isFalse);

      // Complete Run 2 network call
      run2GetCompleter.complete();
      await caller2Future;

      // Caller 2 is now finished
      expect(caller2Finished, isTrue);

      // Cached orders must contain EL-RUN2 pulled in Run 2
      final cached = repository.getCachedOrdersList();
      expect(cached.any((o) => o.id == 'EL-RUN2'), isTrue);
    });

    test('SyncEngine skips sync when not signed in and runs once active store is set', () async {
      await localCache.clearActiveStoreId();
      await localCache.setPendingSyncQueue([
        {
          'type': 'update_status',
          'clientActionId': 'act_unauth_1',
          'orderCode': 'EL-100',
          'status': 'Ready',
        },
      ]);
      mockApiClient.postResponse = {'results': []};
      mockApiClient.getResponse = {'orders': [], 'nextCursor': null};

      await SyncEngine.instance.trigger();

      expect(mockApiClient.getCallCount, 0);
      expect(mockApiClient.postCallCount, 0);

      await localCache.setActiveStoreId('store_1');
      await SyncEngine.instance.trigger();

      expect(mockApiClient.postCallCount, 1);
      expect(mockApiClient.getCallCount, 1);
    });

    test('syncOrdersDelta preserves cached invoice when server order omits invoice', () async {
      await localCache.setCachedOrders([
        {
          'id': 'EL-1001',
          'status': 'Delivered',
          'lines': [],
          'payments': [],
          'invoice': {'exists': true, 'invoiceSeq': 42},
        },
      ]);

      mockApiClient.getResponse = {
        'orders': [
          {'id': 'EL-1001', 'status': 'Delivered', 'lines': [], 'payments': []},
        ],
        'nextCursor': null,
      };

      expect(await repository.syncOrdersDelta(), isTrue);

      final cached = repository.getCachedOrdersList().single;
      expect(cached.invoice, isNotNull);
      expect(cached.invoice!.invoiceSeq, 42);
    });
  });

  group('Two ids per order (offlineId)', () {
    Map<String, dynamic> serverOrder(String id, {String? offlineId}) => {
      'id': id,
      'offlineId': ?offlineId,
      'phone': '9000000000',
      'status': 'Pending',
      'lines': [],
      'payments': [],
    };

    test('lost reply: delta pull fills in the unsynced row, then the retried create keeps one order', () async {
      await localCache.setCachedOrders([
        {
          'id': '',
          'offlineId': 'off-2',
          'phone': '9000000000',
          'isSynced': false,
        },
      ]);
      await localCache.setPendingSyncQueue([
        {
          'type': 'create_order',
          'clientActionId': 'act_create_2',
          'offlineCode': 'off-2',
          'body': {'phone': '9000000000', 'offlineId': 'off-2'},
        },
      ]);

      mockApiClient.getResponse = {
        'orders': [serverOrder('EL-60', offlineId: 'off-2')],
        'nextCursor': null,
      };
      expect(await repository.syncOrdersDelta(), isTrue);
      var orders = repository.getCachedOrdersList();
      expect(orders, hasLength(1));
      expect(orders.single.id, 'EL-60');

      // The server answers the retried create with the same order.
      mockApiClient.postResponse = {
        'results': [
          {
            'clientActionId': 'act_create_2',
            'status': 'success',
            'order': serverOrder('EL-60', offlineId: 'off-2'),
          },
        ],
      };
      await repository.processPendingSyncQueue();
      orders = repository.getCachedOrdersList();
      expect(orders, hasLength(1));
      expect(orders.single.id, 'EL-60');
      expect(localCache.getPendingSyncQueue(), isEmpty);
    });

    test(
      "another device's new order is shown while uploads are pending",
      () async {
        await localCache.setCachedOrders([
          {
            'id': '',
            'offlineId': 'off-3',
            'phone': '9000000000',
            'isSynced': false,
          },
        ]);
        await localCache.setPendingSyncQueue([
          {
            'type': 'create_order',
            'clientActionId': 'act_create_3',
            'offlineCode': 'off-3',
            'body': {'phone': '9000000000', 'offlineId': 'off-3'},
          },
        ]);
        mockApiClient.getResponse = {
          'orders': [serverOrder('EL-70')],
          'nextCursor': null,
        };

        expect(await repository.syncOrdersDelta(), isTrue);

        final orders = repository.getCachedOrdersList();
        expect(orders.map((o) => o.orderCode), ['off-3', 'EL-70']);
      },
    );

    test('create and pay offline: order keyed by its offline id', () async {
      final posRepo = PosRepository(
        apiClient: mockApiClient,
        localCache: localCache,
      );
      fakeConnectivity.mockOffline = true;

      final order = await posRepo.createOrderOptimistic(
        idempotencyKey: 'idem_2',
        phone: '9999999999',
        dueDate: '2026-01-01',
        entries: [
          {'productId': 'p1', 'quantity': 1},
        ],
      );
      expect(order.id, isEmpty);
      expect(order.offlineId, isNotNull);
      expect(order.orderCode, order.offlineId);
      expect(order.displayCode, startsWith('OFF-'));

      final create = localCache.getPendingSyncQueue().single;
      expect(create['offlineCode'], order.offlineId);
      expect(create['body']['offlineId'], order.offlineId);

      final paid = await repository.recordPayment(order.orderCode, 100, 'Cash');
      expect(paid.paidAmount, 100);
      expect(paid.offlineId, order.offlineId);
      final pay = localCache.getPendingSyncQueue().firstWhere(
        (a) => a['type'] == 'record_payment',
      );
      expect(pay['orderCode'], order.offlineId);
    });

    test('web order edited in the app gets a phone-only offline id that survives a pull', () async {
      await localCache.setCachedOrders([serverOrder('EL-80')]);

      final updated = await repository.updateStatus('EL-80', 'Ready');
      final offlineId = updated.offlineId;
      expect(offlineId, isNotNull);
      expect(localCache.getPendingSyncQueue().single['orderCode'], 'EL-80');

      mockApiClient.getResponse = {
        'orders': [serverOrder('EL-80')..['status'] = 'Ready'],
        'nextCursor': null,
      };
      await repository.syncOrdersDelta();

      final cached = repository.getCachedOrdersList().single;
      expect(cached.id, 'EL-80');
      expect(cached.offlineId, offlineId);
      expect(localCache.getPendingSyncQueue(), isEmpty);
    });

    test(
      'legacy LOCAL- action is not pruned once its order has synced',
      () async {
        await localCache.setCachedOrders([
          serverOrder('EL-5', offlineId: 'LOCAL-5'),
        ]);
        await localCache.setPendingSyncQueue([
          {
            'type': 'update_status',
            'clientActionId': 'act_legacy_status',
            'orderCode': 'LOCAL-5',
            'status': 'Ready',
          },
        ]);
        mockApiClient.postResponse = {'results': []};

        await repository.processPendingSyncQueue();

        expect(mockApiClient.postCallCount, 1);
        final sent = (mockApiClient.lastPostBody as Map)['actions'] as List;
        expect(sent.single['orderRef'], 'EL-5');
      },
    );
  });

  group('Setup screen orders sync (syncAllOrders)', () {
    test('pulls from the start and merges, keeping unsynced orders', () async {
      await localCache.setLastSyncCursor('old-cursor');
      await localCache.setCachedOrders([
        {
          'id': '',
          'offlineId': 'off-9',
          'phone': '9000000000',
          'isSynced': false,
        },
      ]);
      final urls = <String>[];
      mockApiClient.onGet = (url) async {
        urls.add(url);
        return {
          'orders': [
            {'id': 'EL-1', 'status': 'Pending', 'lines': [], 'payments': []},
          ],
          'nextCursor': null,
        };
      };

      await repository.syncAllOrders();

      expect(urls.single, isNot(contains('since=')));
      final orders = repository.getCachedOrdersList();
      expect(orders.map((o) => o.orderCode), ['off-9', 'EL-1']);
    });

    test('leaves an empty list behind when there are no orders', () async {
      mockApiClient.getResponse = {'orders': [], 'nextCursor': null};
      expect(localCache.getCachedOrders(), isNull);

      await repository.syncAllOrders();

      expect(localCache.getCachedOrders(), isEmpty);
    });

    test('throws when the server cannot be reached', () async {
      mockApiClient.onGet = (_) async => throw Exception('offline');
      await expectLater(repository.syncAllOrders(), throwsException);
      expect(localCache.getCachedOrders(), isNull);
    });
  });
}
