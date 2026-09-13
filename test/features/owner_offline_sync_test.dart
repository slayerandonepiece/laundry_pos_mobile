import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

class MockConnectivityService extends ConnectivityService {
  MockConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class MockApiClient implements ApiClient {
  final Map<String, dynamic> responses = {};
  final List<String> postUrls = [];
  final List<dynamic> postBodies = [];
  final List<String> patchUrls = [];
  final List<dynamic> patchBodies = [];
  bool shouldThrow = false;
  Exception? errorToThrow;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (shouldThrow) throw errorToThrow ?? Exception('Network failure');
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    throw Exception('Unhandled GET: $url');
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    postUrls.add(url);
    postBodies.add(body);
    if (shouldThrow) throw errorToThrow ?? Exception('Network failure');
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> patch(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    patchUrls.add(url);
    patchBodies.add(body);
    if (shouldThrow) throw errorToThrow ?? Exception('Network failure');
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOrdersRepository extends OrdersRepository {
  @override
  Future<bool> processPendingSyncQueue() async => true;

  @override
  Future<bool> syncOrdersDelta({int maxBatches = 10, int limit = 50}) async =>
      true;

  @override
  Future<void> reviveDeadLetterQueue() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalCacheService localCache;
  late MockConnectivityService mockConnectivity;
  late MockApiClient mockApiClient;
  late OwnerRepository ownerRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('owner_offline_sync_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    mockConnectivity = MockConnectivityService(mockOffline: false);
    ConnectivityService.instance = mockConnectivity;
    mockApiClient = MockApiClient();
    ownerRepo = OwnerRepository(
      apiClient: mockApiClient,
      localCache: localCache,
    );
  });

  tearDown(() async {
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Owner Offline Write & Optimistic Cache Tests', () {
    test(
      'createExpense offline: queues action and optimistically updates cache',
      () async {
        mockConnectivity.mockOffline = true;

        final expense = await ownerRepo.createExpense(
          title: 'Bleach & Detergent',
          category: 'Supplies',
          amount: 1500,
          due: '2026-09-20',
          monthly: false,
        );

        // 1. Returned expense has placeholder ID
        expect(expense.id.startsWith('LOCAL-'), isTrue);
        expect(expense.title, 'Bleach & Detergent');
        expect(expense.amount, 1500);

        // 2. LocalCache is optimistically updated
        final cached = localCache.getCachedExpenses();
        expect(cached, isNotNull);
        expect(cached!.length, 1);
        expect(cached.first['id'], expense.id);
        expect(cached.first['title'], 'Bleach & Detergent');

        // 3. Action is appended to owner actions queue
        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['type'], 'create_expense');
        expect(queue.first['payload']['title'], 'Bleach & Detergent');
        expect(queue.first['payload']['localId'], expense.id);

        // 4. Combined pending count reflects queued action
        expect(localCache.getTotalPendingCount(), 1);
        // Orders queue remains completely empty
        expect(localCache.getPendingSyncQueue(), isEmpty);
      },
    );

    test(
      'createStaff offline: queues action and optimistically updates cache',
      () async {
        mockConnectivity.mockOffline = true;

        final staff = await ownerRepo.createStaff(
          name: 'Jane Operator',
          username: 'jane_op',
          password: 'secret_password_123',
        );

        // 1. Returned staff member has placeholder ID
        expect(staff.id.startsWith('LOCAL-'), isTrue);
        expect(staff.name, 'Jane Operator');
        expect(staff.username, 'jane_op');
        expect(staff.active, isTrue);

        // 2. LocalCache is optimistically updated
        final cached = localCache.getCachedStaff();
        expect(cached, isNotNull);
        expect(cached!.length, 1);
        expect(cached.first['id'], staff.id);
        expect(cached.first['name'], 'Jane Operator');

        // 3. Action is appended to owner actions queue
        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['type'], 'create_staff');
        expect(queue.first['payload']['username'], 'jane_op');
        expect(queue.first['payload']['localId'], staff.id);

        // 4. Combined pending count reflects queued action
        expect(localCache.getTotalPendingCount(), 1);
      },
    );

    test('markExpensePaid offline: updates cache and queues action', () async {
      // Seed cached expense
      await localCache.setCachedExpenses([
        {
          'id': 'exp_101',
          'title': 'Rent',
          'category': 'Operations',
          'amount': 25000,
          'due': '2026-09-01',
          'paid': null,
          'monthly': true,
        },
      ]);

      mockConnectivity.mockOffline = true;
      await ownerRepo.markExpensePaid('exp_101');

      // Optimistically marked paid in cache
      final cached = localCache.getCachedExpenses();
      expect(cached!.first['paid'], isNotNull);

      // Queued
      final queue = localCache.getPendingOwnerActionsQueue();
      expect(queue.length, 1);
      expect(queue.first['type'], 'mark_expense_paid');
      expect(queue.first['payload']['expenseId'], 'exp_101');
    });

    test(
      'createPaymentMethod offline: updates cache and queues action',
      () async {
        mockConnectivity.mockOffline = true;

        final method = await ownerRepo.createPaymentMethod(
          name: 'Store Gift Card',
        );
        expect(method.id.startsWith('LOCAL-'), isTrue);
        expect(method.name, 'Store Gift Card');

        final cached = localCache.getCachedPaymentMethods();
        expect(cached!.length, 1);
        expect(cached.first['name'], 'Store Gift Card');

        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['type'], 'create_payment_method');
        expect(queue.first['payload']['name'], 'Store Gift Card');
      },
    );

    test(
      'toggleStaffActive and updateStaff offline: updates cache and queues',
      () async {
        await localCache.setCachedStaff([
          {
            'id': 'staff_202',
            'name': 'Bob Clerk',
            'username': 'bob_c',
            'active': true,
          },
        ]);

        mockConnectivity.mockOffline = true;

        // 1. Toggle active
        await ownerRepo.toggleStaffActive('staff_202');
        var cached = localCache.getCachedStaff();
        expect(cached!.first['active'], isFalse);

        // 2. Update staff
        final updated = await ownerRepo.updateStaff(
          employeeId: 'staff_202',
          name: 'Bob Senior Clerk',
          username: 'bob_sr',
        );
        expect(updated.name, 'Bob Senior Clerk');
        cached = localCache.getCachedStaff();
        expect(cached!.first['name'], 'Bob Senior Clerk');

        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 2);
        expect(queue[0]['type'], 'toggle_staff_active');
        expect(queue[1]['type'], 'update_staff');
      },
    );

    test(
      'updateStoreProfile offline: updates cache and queues action',
      () async {
        mockConnectivity.mockOffline = true;

        final profile = await ownerRepo.updateStoreProfile(
          storeName: 'QuickWash Hub',
          address: '123 Main St',
          phone: '9876543210',
          name: 'Alice Owner',
          email: 'alice@quickwash.com',
        );

        expect(profile.store, 'QuickWash Hub');
        final cached = localCache.getCachedStoreProfile();
        expect(cached, isNotNull);
        expect(cached!['store'], 'QuickWash Hub');

        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['type'], 'update_store_profile');
        expect(queue.first['payload']['storeName'], 'QuickWash Hub');
      },
    );
  });

  group('processPendingOwnerActions Replay and Drain Tests', () {
    test('processPendingOwnerActions replays create_expense and reconciles placeholder in cache', () async {
      // 1. Create offline
      mockConnectivity.mockOffline = true;
      final localExpense = await ownerRepo.createExpense(
        title: 'Dry Clean Solvent',
        category: 'Supplies',
        amount: 4000,
        due: '2026-09-30',
        monthly: false,
      );
      expect(localCache.getPendingOwnerActionsQueue().length, 1);

      // 2. Back online
      mockConnectivity.mockOffline = false;
      mockApiClient.responses[ApiEndpoints.expenses] = {
        'id': 'exp_server_555',
        'title': 'Dry Clean Solvent',
        'category': 'Supplies',
        'amount': 4000,
        'due': '2026-09-30',
        'monthly': false,
      };

      // 3. Drain
      final drainResult = await ownerRepo.processPendingOwnerActions();
      expect(drainResult, isTrue);

      // Queue is drained
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      expect(localCache.getTotalPendingCount(), 0);

      // API POST was invoked
      expect(mockApiClient.postUrls.contains(ApiEndpoints.expenses), isTrue);

      // Cached list reconciled placeholder LOCAL-xxx to real server id exp_server_555
      final cached = localCache.getCachedExpenses();
      expect(cached!.length, 1);
      expect(cached.first['id'], 'exp_server_555');
      expect(cached.any((e) => e['id'] == localExpense.id), isFalse);
    });

    test('processPendingOwnerActions replays create_staff and reconciles placeholder in cache', () async {
      mockConnectivity.mockOffline = true;
      final localStaff = await ownerRepo.createStaff(
        name: 'Sam Tech',
        username: 'sam_tech',
        password: 'password123',
      );
      expect(localCache.getPendingOwnerActionsQueue().length, 1);

      mockConnectivity.mockOffline = false;
      mockApiClient.responses[ApiEndpoints.employees] = {
        'id': 'staff_srv_888',
        'name': 'Sam Tech',
        'username': 'sam_tech',
        'active': true,
      };

      final drainResult = await ownerRepo.processPendingOwnerActions();
      expect(drainResult, isTrue);

      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      expect(localCache.getTotalPendingCount(), 0);

      final cached = localCache.getCachedStaff();
      expect(cached!.length, 1);
      expect(cached.first['id'], 'staff_srv_888');
      expect(cached.any((s) => s['id'] == localStaff.id), isFalse);
    });

    test('Dependent action resolution: createExpense offline then markExpensePaid offline resolves ID on drain', () async {
      mockConnectivity.mockOffline = true;

      // Offline create
      final localExpense = await ownerRepo.createExpense(
        title: 'Power Bill',
        category: 'Utilities',
        amount: 8000,
        due: '2026-09-25',
        monthly: true,
      );

      // Offline mark paid targeting the local placeholder
      await ownerRepo.markExpensePaid(localExpense.id);

      expect(localCache.getPendingOwnerActionsQueue().length, 2);

      // Come online
      mockConnectivity.mockOffline = false;
      mockApiClient.responses[ApiEndpoints.expenses] = {
        'id': 'exp_srv_999',
        'title': 'Power Bill',
        'category': 'Utilities',
        'amount': 8000,
        'due': '2026-09-25',
        'monthly': true,
      };
      mockApiClient.responses[ApiEndpoints.markExpensePaid('exp_srv_999')] = {
        'ok': true,
      };

      final ok = await ownerRepo.processPendingOwnerActions();
      expect(ok, isTrue);

      // Queue is completely drained
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);

      // The second call went to markExpensePaid with the resolved server ID exp_srv_999
      expect(
        mockApiClient.postUrls.contains(
          ApiEndpoints.markExpensePaid('exp_srv_999'),
        ),
        isTrue,
      );
    });

    test(
      'SyncEngine drains owner actions on trigger and updates SyncManager',
      () async {
        mockConnectivity.mockOffline = true;

        await ownerRepo.createExpense(
          title: 'Hanger Wire',
          category: 'Supplies',
          amount: 600,
          due: '2026-09-28',
        );

        expect(localCache.getTotalPendingCount(), 1);
        expect(SyncManager.instance.value.isOffline, isTrue);
        expect(SyncManager.instance.value.pendingCount, 1);

        // Come online
        mockConnectivity.mockOffline = false;
        mockApiClient.responses[ApiEndpoints.expenses] = {
          'id': 'exp_srv_321',
          'title': 'Hanger Wire',
          'category': 'Supplies',
          'amount': 600,
          'due': '2026-09-28',
          'monthly': false,
        };

        // Trigger SyncEngine
        final engine = SyncEngine.internal(
          ordersRepository: MockOrdersRepository(),
          ownerRepository: ownerRepo,
          localCache: localCache,
        );

        await engine.trigger();

        expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
        expect(localCache.getTotalPendingCount(), 0);
        expect(SyncManager.instance.value.isSynced, isTrue);
        expect(SyncManager.instance.value.pendingCount, 0);
      },
    );

    test('Failing action reaches dead letter queue after 3 retries and revives cleanly', () async {
      mockConnectivity.mockOffline = true;
      await ownerRepo.createPaymentMethod(name: 'Broken Gateway');

      mockConnectivity.mockOffline = false;
      mockApiClient.shouldThrow = true;
      mockApiClient.errorToThrow = Exception('500 Internal Server Error');

      // Attempt 1
      await ownerRepo.processPendingOwnerActions();
      var queue = localCache.getPendingOwnerActionsQueue();
      expect(queue.length, 1);
      expect(queue.first['failCount'], 1);

      // Attempt 2
      await ownerRepo.processPendingOwnerActions();
      queue = localCache.getPendingOwnerActionsQueue();
      expect(queue.length, 1);
      expect(queue.first['failCount'], 2);

      // Attempt 3: moves to dead letter
      await ownerRepo.processPendingOwnerActions();
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      final deadLetter = localCache.getDeadLetterOwnerActionsQueue();
      expect(deadLetter.length, 1);
      expect(deadLetter.first['type'], 'create_payment_method');

      // Revive dead letter queue
      await ownerRepo.reviveDeadLetterQueue();
      expect(localCache.getDeadLetterOwnerActionsQueue(), isEmpty);
      final revived = localCache.getPendingOwnerActionsQueue();
      expect(revived.length, 1);
      expect(revived.first['failCount'], 0);
    });
  });
}
