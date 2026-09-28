import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

import '../helpers/mock_dio.dart';

class _FakeSecureStorage extends SecureStorageService {
  @override
  Future<String?> getToken() async => 'test_token';
}

class _FakeConnectivityService extends ConnectivityService {
  _FakeConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class _RecordedPost {
  final String url;
  final Map<String, dynamic> body;
  final Map<String, String>? passedHeaders;
  final Map<String, dynamic> wireHeaders;

  _RecordedPost({
    required this.url,
    required this.body,
    required this.passedHeaders,
    required this.wireHeaders,
  });
}

class _RecordingApiClient extends ApiClient {
  final List<Map<String, String>?> passedPostHeaders = [];

  _RecordingApiClient({
    required super.dio,
    required super.secureStorage,
    required super.localCache,
  });

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) {
    passedPostHeaders.add(headers);
    return super.post(url, body: body, headers: headers);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalCacheService localCache;
  late _FakeConnectivityService fakeConnectivity;
  late List<_RecordedPost> recordedPosts;
  late Future<ResponseBody> Function(RequestOptions options) dioHandler;
  late _RecordingApiClient apiClient;
  late OrdersRepository ordersRepo;
  late PosRepository posRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_per_outlet_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    await localCache.setActiveStoreId('store_1');

    fakeConnectivity = _FakeConnectivityService(mockOffline: false);
    ConnectivityService.instance = fakeConnectivity;

    recordedPosts = [];
    dioHandler = (options) async {
      final data = options.data is Map
          ? Map<String, dynamic>.from(options.data as Map)
          : <String, dynamic>{};
      final actions = (data['actions'] as List? ?? [])
          .whereType<Map>()
          .map((a) => Map<String, dynamic>.from(a))
          .toList();
      return mockJsonResponse({
        'results': [
          for (var i = 0; i < actions.length; i++)
            {
              'clientActionId': actions[i]['clientActionId'],
              'status': 'success',
              'order': {
                'id': 'EL-${100 + i}',
                'phone': '9876543210',
                'status': 'Pending',
                'lines': [],
                'payments': [],
                'outletId': options.headers['X-Outlet-Id'],
              },
            },
        ],
      });
    };

    final mockDio = createMockDio((options) async {
      if (options.method == 'POST') {
        final bodyMap = options.data is Map
            ? Map<String, dynamic>.from(options.data as Map)
            : <String, dynamic>{};
        recordedPosts.add(
          _RecordedPost(
            url: options.uri.toString(),
            body: bodyMap,
            passedHeaders: apiClient.passedPostHeaders.isNotEmpty
                ? apiClient.passedPostHeaders.last
                : null,
            wireHeaders: Map<String, dynamic>.from(options.headers),
          ),
        );
      }
      return await dioHandler(options);
    });

    apiClient = _RecordingApiClient(
      dio: mockDio,
      secureStorage: _FakeSecureStorage(),
      localCache: localCache,
    );
    ordersRepo = OrdersRepository(apiClient: apiClient, localCache: localCache);
    posRepo = PosRepository(apiClient: apiClient, localCache: localCache);
    SyncEngine.instance = SyncEngine.internal(
      ordersRepository: ordersRepo,
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

  group('Per-outlet offline sync queue (Step 7 / O6)', () {
    test('two create_orders in outlets o1 and o2 -> exactly two bulk-sync POSTs, headers o1 and o2', () async {
      // Offline while enqueueing so SyncEngine.trigger() inside
      // createOrderOptimistic does not flush early.
      fakeConnectivity.mockOffline = true;

      await posRepo.createOrderOptimistic(
        idempotencyKey: 'idem_o1',
        phone: '9000000001',
        dueDate: '2026-09-30',
        entries: const [
          {'productId': 'p1', 'quantity': 1},
        ],
        outletId: 'o1',
      );
      await posRepo.createOrderOptimistic(
        idempotencyKey: 'idem_o2',
        phone: '9000000002',
        dueDate: '2026-09-30',
        entries: const [
          {'productId': 'p1', 'quantity': 2},
        ],
        outletId: 'o2',
      );

      final queued = localCache.getPendingSyncQueue();
      expect(queued, hasLength(2));
      expect(queued[0]['outletId'], 'o1');
      expect(queued[1]['outletId'], 'o2');

      // Come online and flush
      fakeConnectivity.mockOffline = false;
      final ok = await ordersRepo.processPendingSyncQueue();
      expect(ok, isTrue);

      expect(recordedPosts, hasLength(2));
      expect(recordedPosts[0].passedHeaders?['X-Outlet-Id'], 'o1');
      expect(recordedPosts[0].wireHeaders['X-Outlet-Id'], 'o1');
      expect(recordedPosts[1].passedHeaders?['X-Outlet-Id'], 'o2');
      expect(recordedPosts[1].wireHeaders['X-Outlet-Id'], 'o2');
      expect(localCache.getPendingSyncQueue(), isEmpty);
    });

    test('null-outlet owner action -> passes kNoOutletHeader and omits X-Outlet-Id on the wire even when activeOutletId is set later', () async {
      // Owner in All-Outlets scope (no active outlet) updates a null-outlet order.
      await localCache.setAllOutletsScope(true);
      await localCache.clearActiveOutletId();
      await localCache.setCachedOrders([
        {
          'id': 'EL-500',
          'name': 'Owner Order',
          'phone': '9111111111',
          'date': '2026-09-26',
          'due': '2026-09-28',
          'status': 'Pending',
          'lines': [],
          'payments': [],
          'outletId': null,
        },
      ]);

      await ordersRepo.updateStatus('EL-500', 'Ready');

      final queued = localCache.getPendingSyncQueue();
      expect(queued, hasLength(1));
      expect(queued.first.containsKey('outletId'), isTrue);
      expect(queued.first['outletId'], isNull);

      // Even if the user switches active outlet to o1 before flushing,
      // the action's stamped null outlet must not resolve to o1 at flush.
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');

      final ok = await ordersRepo.processPendingSyncQueue();
      expect(ok, isTrue);

      expect(recordedPosts, hasLength(1));
      expect(
        recordedPosts.single.passedHeaders?['X-Outlet-Id'],
        kNoOutletHeader,
      );
      expect(
        recordedPosts.single.wireHeaders.containsKey('X-Outlet-Id'),
        isFalse,
      );
    });

    test('403 on o1 -> o1 actions dead-lettered with lastError "outlet access changed" and removed from pending queue; o2 still sent and completed', () async {
      await localCache.setPendingSyncQueue([
        {
          'type': 'create_order',
          'clientActionId': 'act_o1_1',
          'offlineCode': 'LOCAL-1',
          'storeId': 'store_1',
          'outletId': 'o1',
          'body': {'phone': '9000000001', 'outletId': 'o1'},
        },
        {
          'type': 'update_status',
          'clientActionId': 'act_o1_2',
          'orderCode': 'LOCAL-1',
          'status': 'Ready',
          'storeId': 'store_1',
          'outletId': 'o1',
        },
        {
          'type': 'create_order',
          'clientActionId': 'act_o2_1',
          'offlineCode': 'LOCAL-2',
          'storeId': 'store_1',
          'outletId': 'o2',
          'body': {'phone': '9000000002', 'outletId': 'o2'},
        },
      ]);

      dioHandler = (options) async {
        final outletHeader = options.headers['X-Outlet-Id'];
        if (outletHeader == 'o1') {
          return mockJsonResponse({
            'error': 'Outlet access revoked',
            'reason': 'outlet_forbidden',
          }, statusCode: 403);
        }
        return mockJsonResponse({
          'results': [
            {
              'clientActionId': 'act_o2_1',
              'status': 'success',
              'order': {
                'id': 'EL-202',
                'phone': '9000000002',
                'status': 'Pending',
                'lines': [],
                'payments': [],
                'outletId': 'o2',
              },
            },
          ],
        });
      };

      final ok = await ordersRepo.processPendingSyncQueue();
      expect(ok, isTrue);

      // Both groups were attempted once (o1 got 403, o2 succeeded).
      expect(recordedPosts, hasLength(2));
      expect(recordedPosts[0].wireHeaders['X-Outlet-Id'], 'o1');
      expect(recordedPosts[1].wireHeaders['X-Outlet-Id'], 'o2');

      // Pending queue is now empty (o1 dead-lettered, o2 completed).
      expect(localCache.getPendingSyncQueue(), isEmpty);

      // Dead-letter queue contains both o1 actions with lastError set.
      final deadLetter = localCache.getDeadLetterQueue();
      expect(deadLetter, hasLength(2));
      expect(
        deadLetter.map((a) => a['clientActionId']),
        containsAll(['act_o1_1', 'act_o1_2']),
      );
      for (final a in deadLetter) {
        expect(a['lastError'], 'outlet access changed');
      }
    });

    test(
      'legacy create_order without top-level outletId groups by body.outletId',
      () async {
        await localCache.setActiveOutletId('o_active_fallback');
        await localCache.setPendingSyncQueue([
          {
            'type': 'create_order',
            'clientActionId': 'legacy_create_o2',
            'offlineCode': 'LOCAL-99',
            'storeId': 'store_1',
            // No top-level 'outletId'
            'body': {'phone': '9888888888', 'outletId': 'o2'},
          },
        ]);

        final ok = await ordersRepo.processPendingSyncQueue();
        expect(ok, isTrue);

        expect(recordedPosts, hasLength(1));
        expect(recordedPosts.single.passedHeaders?['X-Outlet-Id'], 'o2');
        expect(recordedPosts.single.wireHeaders['X-Outlet-Id'], 'o2');
      },
    );

    test('confirmed order from o2 is not inserted into o1 cache when not replacing a placeholder, but placeholder replacement stays unconditional', () async {
      // Active scope is o1. Cache for o1 has one existing order EL-100,
      // and NO placeholder for LOCAL-O2.
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');
      await localCache.setCachedOrders([
        {
          'id': 'EL-100',
          'name': 'Existing O1 Order',
          'phone': '9000000100',
          'date': '2026-09-26',
          'due': '2026-09-28',
          'status': 'Pending',
          'lines': [],
          'payments': [],
          'outletId': 'o1',
        },
      ]);

      await localCache.setPendingSyncQueue([
        {
          'type': 'create_order',
          'clientActionId': 'act_o2_new',
          'offlineCode': 'LOCAL-O2',
          'storeId': 'store_1',
          'outletId': 'o2',
          'body': {'phone': '9000000200', 'outletId': 'o2'},
        },
      ]);

      dioHandler = (options) async {
        return mockJsonResponse({
          'results': [
            {
              'clientActionId': 'act_o2_new',
              'status': 'success',
              'order': {
                'id': 'EL-200',
                'name': 'Confirmed O2 Order',
                'phone': '9000000200',
                'status': 'Pending',
                'lines': [],
                'payments': [],
                'outletId': 'o2',
              },
            },
          ],
        });
      };

      final ok = await ordersRepo.processPendingSyncQueue();
      expect(ok, isTrue);

      // o1's cache must NOT have EL-200 inserted.
      final cachedO1 = localCache.getCachedOrders() ?? [];
      expect(cachedO1.map((c) => c['id']), ['EL-100']);

      // Now test that if a placeholder IS present in the current cache,
      // replacing it stays unconditional even if outletId differs.
      await localCache.setCachedOrders([
        {
          'id': 'LOCAL-PLACEHOLDER',
          'name': 'Placeholder Order',
          'phone': '9000000300',
          'date': '2026-09-26',
          'due': '2026-09-28',
          'status': 'Pending',
          'lines': [],
          'payments': [],
          'outletId': 'o2',
        },
      ]);
      await localCache.setPendingSyncQueue([
        {
          'type': 'create_order',
          'clientActionId': 'act_o2_replace',
          'offlineCode': 'LOCAL-PLACEHOLDER',
          'storeId': 'store_1',
          'outletId': 'o2',
          'body': {'phone': '9000000300', 'outletId': 'o2'},
        },
      ]);

      dioHandler = (options) async {
        return mockJsonResponse({
          'results': [
            {
              'clientActionId': 'act_o2_replace',
              'status': 'success',
              'order': {
                'id': 'EL-300',
                'name': 'Placeholder Order',
                'phone': '9000000300',
                'status': 'Pending',
                'lines': [],
                'payments': [],
                'outletId': 'o2',
              },
            },
          ],
        });
      };

      final okReplace = await ordersRepo.processPendingSyncQueue();
      expect(okReplace, isTrue);

      final cachedAfterReplace = localCache.getCachedOrders() ?? [];
      expect(cachedAfterReplace.map((c) => c['id']), ['EL-300']);
    });
  });
}
