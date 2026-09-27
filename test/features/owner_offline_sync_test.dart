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
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
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
  final List<String> getUrls = [];
  final List<String> postUrls = [];
  final List<dynamic> postBodies = [];
  final List<String> putUrls = [];
  final List<dynamic> putBodies = [];
  final List<String> patchUrls = [];
  final List<dynamic> patchBodies = [];
  bool shouldThrow = false;
  Exception? errorToThrow;
  void Function(String url)? onPost;
  void Function(String url)? onPut;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
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
    onPost?.call(url);
    if (shouldThrow) throw errorToThrow ?? Exception('Network failure');
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> put(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    putUrls.add(url);
    putBodies.add(body);
    onPut?.call(url);
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
  Future<bool> syncOrdersDelta({
    int maxBatches = 10,
    int limit = 50,
    bool fromStart = false,
  }) async => true;

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
    await localCache.setActiveStoreId('store_1');
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
      'createStaff offline: throws and does not queue or cache password',
      () async {
        mockConnectivity.mockOffline = true;

        await expectLater(
          () => ownerRepo.createStaff(
            name: 'Jane Operator',
            phone: 'jane_op',
            password: 'secret_password_123',
          ),
          throwsA(
            predicate(
              (e) => e.toString().contains(
                'Adding staff needs an internet connection',
              ),
            ),
          ),
        );

        expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
        expect(localCache.getCachedStaff(), isNull);
        expect(localCache.getTotalPendingCount(), 0);
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
      'togglePaymentMethod online PATCHes body {\'enabled\': <bool>}',
      () async {
        await localCache.setCachedPaymentMethods([
          {'id': 'pm_1', 'name': 'Cash', 'type': 'Cash', 'active': true},
        ]);

        mockConnectivity.mockOffline = false;
        await ownerRepo.togglePaymentMethod('pm_1', false);

        expect(
          mockApiClient.patchUrls,
          contains(ApiEndpoints.paymentMethodDetail('pm_1')),
        );
        expect(mockApiClient.patchBodies.last, equals({'enabled': false}));

        final cached = localCache.getCachedPaymentMethods();
        expect(cached!.first['active'], isFalse);
      },
    );

    test(
      'toggleStaffActive and updateStaff offline: updates cache and queues',
      () async {
        await localCache.setCachedStaff([
          {
            'id': 'staff_202',
            'name': 'Bob Clerk',
            'phone': 'bob_c',
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
          phone: 'bob_sr',
        );
        expect(updated.name, 'Bob Senior Clerk');
        cached = localCache.getCachedStaff();
        expect(cached!.first['name'], 'Bob Senior Clerk');

        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 2);
        expect(queue[0]['type'], 'set_staff_active');
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

    test('processPendingOwnerActions replays legacy queued create_staff and reconciles placeholder in cache', () async {
      const localStaffId = 'LOCAL-legacy-staff-1';
      await localCache.setCachedStaff([
        {
          'id': localStaffId,
          'name': 'Sam Tech',
          'phone': 'sam_tech',
          'active': true,
        },
      ]);
      await localCache.enqueueOwnerAction({
        'clientActionId': 'owner_legacy_staff',
        'type': 'create_staff',
        'payload': {
          'localId': localStaffId,
          'name': 'Sam Tech',
          'phone': 'sam_tech',
          'password': 'password123',
        },
        'queuedAt': DateTime.now().toIso8601String(),
      });
      expect(localCache.getPendingOwnerActionsQueue().length, 1);

      mockConnectivity.mockOffline = false;
      mockApiClient.responses[ApiEndpoints.employees] = {
        'id': 'staff_srv_888',
        'name': 'Sam Tech',
        'phone': 'sam_tech',
        'active': true,
      };

      final drainResult = await ownerRepo.processPendingOwnerActions();
      expect(drainResult, isTrue);

      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      expect(localCache.getTotalPendingCount(), 0);

      final cached = localCache.getCachedStaff();
      expect(cached!.length, 1);
      expect(cached.first['id'], 'staff_srv_888');
      expect(cached.any((s) => s['id'] == localStaffId), isFalse);
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

    test('Dependent action resolution across runs: create_expense rewrites remaining mark_expense_paid payload when drain stops mid-way', () async {
      mockConnectivity.mockOffline = true;

      final localExpense = await ownerRepo.createExpense(
        title: 'Water Bill',
        category: 'Utilities',
        amount: 3200,
        due: '2026-09-25',
        monthly: true,
      );
      await ownerRepo.markExpensePaid(localExpense.id);
      expect(localCache.getPendingOwnerActionsQueue().length, 2);

      // First drain: create_expense succeeds, then phone goes offline on mark_expense_paid
      mockConnectivity.mockOffline = false;
      mockApiClient.responses[ApiEndpoints.expenses] = {
        'id': 'exp_srv_777',
        'title': 'Water Bill',
        'category': 'Utilities',
        'amount': 3200,
        'due': '2026-09-25',
        'monthly': true,
      };
      mockApiClient.onPost = (url) {
        if (url == ApiEndpoints.markExpensePaid('exp_srv_777')) {
          mockConnectivity.mockOffline = true;
          throw Exception('Connection lost');
        }
      };

      final firstRun = await ownerRepo.processPendingOwnerActions();
      expect(firstRun, isFalse);

      // Remaining queued mark_expense_paid has rewritten expenseId
      final remaining = localCache.getPendingOwnerActionsQueue();
      expect(remaining.length, 1);
      expect(remaining.first['type'], 'mark_expense_paid');
      expect(remaining.first['payload']['expenseId'], 'exp_srv_777');

      // Second drain: back online, mark_expense_paid succeeds with exp_srv_777
      mockConnectivity.mockOffline = false;
      mockApiClient.onPost = null;
      mockApiClient.postUrls.clear();

      final secondRun = await ownerRepo.processPendingOwnerActions();
      expect(secondRun, isTrue);
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      expect(
        mockApiClient.postUrls,
        contains(ApiEndpoints.markExpensePaid('exp_srv_777')),
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

    test('Queued legacy create_payment_method action is dropped (not dead-lettered, no network call)', () async {
      await localCache.enqueueOwnerAction({
        'clientActionId': 'owner_legacy_create_pm',
        'type': 'create_payment_method',
        'payload': {'localId': 'LOCAL-123', 'name': 'Old Custom Method'},
        'queuedAt': DateTime.now().toIso8601String(),
      });
      expect(localCache.getPendingOwnerActionsQueue().length, 1);

      mockConnectivity.mockOffline = false;
      final result = await ownerRepo.processPendingOwnerActions();

      expect(result, isTrue);
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
      expect(localCache.getDeadLetterOwnerActionsQueue(), isEmpty);
      expect(mockApiClient.postUrls, isEmpty);
      expect(mockApiClient.patchUrls, isEmpty);
    });

    test('Failing action reaches dead letter queue after 3 retries and revives cleanly', () async {
      mockConnectivity.mockOffline = true;
      await ownerRepo.createExpense(
        title: 'Broken Expense',
        category: 'Supplies',
        amount: 500,
        due: '2026-09-30',
      );

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
      expect(deadLetter.first['type'], 'create_expense');

      // Revive dead letter queue
      await ownerRepo.reviveDeadLetterQueue();
      expect(localCache.getDeadLetterOwnerActionsQueue(), isEmpty);
      final revived = localCache.getPendingOwnerActionsQueue();
      expect(revived.length, 1);
      expect(revived.first['failCount'], 0);
    });

    test(
      'updateStoreProfile online + offline replay sends PUT /api/v1/profile with store key',
      () async {
        mockApiClient.responses[ApiEndpoints.profile] = {
          'name': 'Alice Owner',
          'phone': '9876543210',
          'email': 'alice@quickwash.com',
          'store': 'QuickWash Hub',
          'address': '123 Main St',
        };

        // 1. Online
        mockConnectivity.mockOffline = false;
        await ownerRepo.updateStoreProfile(
          storeName: 'QuickWash Hub',
          address: '123 Main St',
          phone: '9876543210',
          name: 'Alice Owner',
          email: 'alice@quickwash.com',
        );

        expect(mockApiClient.putUrls.last, ApiEndpoints.profile);
        expect(
          mockApiClient.putBodies.last,
          equals({
            'name': 'Alice Owner',
            'phone': '9876543210',
            'email': 'alice@quickwash.com',
            'store': 'QuickWash Hub',
            'address': '123 Main St',
          }),
        );

        // 2. Offline + replay
        mockApiClient.putUrls.clear();
        mockApiClient.putBodies.clear();
        mockConnectivity.mockOffline = true;
        await ownerRepo.updateStoreProfile(
          storeName: 'QuickWash Express',
          address: '456 Market Rd',
          phone: '9998887770',
          name: 'Alice B',
          email: 'aliceb@quickwash.com',
        );
        expect(mockApiClient.putUrls, isEmpty);

        mockConnectivity.mockOffline = false;
        mockApiClient.responses[ApiEndpoints.profile] = {
          'name': 'Alice B',
          'phone': '9998887770',
          'email': 'aliceb@quickwash.com',
          'store': 'QuickWash Express',
          'address': '456 Market Rd',
        };
        await ownerRepo.processPendingOwnerActions();

        expect(mockApiClient.putUrls.last, ApiEndpoints.profile);
        expect(
          mockApiClient.putBodies.last,
          equals({
            'name': 'Alice B',
            'phone': '9998887770',
            'email': 'aliceb@quickwash.com',
            'store': 'QuickWash Express',
            'address': '456 Market Rd',
          }),
        );
      },
    );

    test(
      'updateStaff online + offline replay calls PUT /api/v1/employees/{id} with name, phone, and active',
      () async {
        await localCache.setCachedStaff([
          {
            'id': 'emp_42',
            'name': 'Bob Clerk',
            'phone': 'bob_c',
            'active': false,
          },
        ]);
        mockApiClient.responses[ApiEndpoints.employeeDetail('emp_42')] = {
          'id': 'emp_42',
          'name': 'Bob Updated',
          'phone': 'bob_u',
          'active': false,
        };

        // 1. Online
        mockConnectivity.mockOffline = false;
        await ownerRepo.updateStaff(
          employeeId: 'emp_42',
          name: 'Bob Updated',
          phone: 'bob_u',
        );

        expect(
          mockApiClient.putUrls.last,
          ApiEndpoints.employeeDetail('emp_42'),
        );
        expect(
          mockApiClient.putBodies.last,
          equals({'name': 'Bob Updated', 'phone': 'bob_u', 'active': false}),
        );

        // 2. Offline + replay
        mockApiClient.putUrls.clear();
        mockApiClient.putBodies.clear();
        mockConnectivity.mockOffline = true;
        await ownerRepo.updateStaff(
          employeeId: 'emp_42',
          name: 'Bob Replay',
          phone: 'bob_r',
        );
        expect(mockApiClient.putUrls, isEmpty);

        mockConnectivity.mockOffline = false;
        mockApiClient.responses[ApiEndpoints.employeeDetail('emp_42')] = {
          'id': 'emp_42',
          'name': 'Bob Replay',
          'phone': 'bob_r',
          'active': false,
        };
        await ownerRepo.processPendingOwnerActions();

        expect(
          mockApiClient.putUrls.last,
          ApiEndpoints.employeeDetail('emp_42'),
        );
        expect(
          mockApiClient.putBodies.last,
          equals({'name': 'Bob Replay', 'phone': 'bob_r', 'active': false}),
        );
      },
    );

    test(
      'set_staff_active online calls PUT, offline queues set_staff_active and replays PUT, legacy toggle_staff_active replays POST, and rewriteQueuedId rewrites employeeId',
      () async {
        await localCache.setCachedStaff([
          {
            'id': 'emp_50',
            'name': 'Clara Staff',
            'phone': 'clara_s',
            'active': true,
          },
        ]);

        // 1. Online toggleStaffActive -> PUT with explicit active: false
        mockConnectivity.mockOffline = false;
        await ownerRepo.toggleStaffActive('emp_50');
        expect(
          mockApiClient.putUrls.last,
          ApiEndpoints.employeeDetail('emp_50'),
        );
        expect(
          mockApiClient.putBodies.last,
          equals({'name': 'Clara Staff', 'phone': 'clara_s', 'active': false}),
        );
        expect(mockApiClient.postUrls, isEmpty);

        // 2. Offline toggleStaffActive -> queues set_staff_active, replays as PUT
        mockApiClient.putUrls.clear();
        mockApiClient.putBodies.clear();
        mockConnectivity.mockOffline = true;
        await ownerRepo.toggleStaffActive('emp_50');
        final queued = localCache.getPendingOwnerActionsQueue();
        expect(queued.length, 1);
        expect(queued.first['type'], 'set_staff_active');
        expect(queued.first['payload']['active'], isTrue);

        mockConnectivity.mockOffline = false;
        await ownerRepo.processPendingOwnerActions();
        expect(
          mockApiClient.putUrls.last,
          ApiEndpoints.employeeDetail('emp_50'),
        );
        expect(
          mockApiClient.putBodies.last,
          equals({'name': 'Clara Staff', 'phone': 'clara_s', 'active': true}),
        );

        // 3. Legacy toggle_staff_active still replays as POST
        mockApiClient.postUrls.clear();
        await localCache.enqueueOwnerAction({
          'clientActionId': 'legacy_toggle_1',
          'type': 'toggle_staff_active',
          'payload': {'employeeId': 'emp_50'},
          'queuedAt': DateTime.now().toIso8601String(),
        });
        await ownerRepo.processPendingOwnerActions();
        expect(
          mockApiClient.postUrls.last,
          ApiEndpoints.toggleEmployeeActive('emp_50'),
        );

        // 4. rewriteQueuedId('employeeId', ...) rewrites queued set_staff_active when create_staff resolves temp id
        const tempStaffId = 'LOCAL-staff-temp-99';
        await localCache.enqueueOwnerAction({
          'clientActionId': 'act_create_staff',
          'type': 'create_staff',
          'payload': {
            'localId': tempStaffId,
            'name': 'New Hire',
            'phone': 'newhire',
            'password': 'pw1',
          },
          'queuedAt': DateTime.now().toIso8601String(),
        });
        await localCache.enqueueOwnerAction({
          'clientActionId': 'act_set_active',
          'type': 'set_staff_active',
          'payload': {
            'employeeId': tempStaffId,
            'name': 'New Hire',
            'phone': 'newhire',
            'active': false,
          },
          'queuedAt': DateTime.now().toIso8601String(),
        });
        mockApiClient.responses[ApiEndpoints.employees] = {
          'id': 'emp_srv_99',
          'name': 'New Hire',
          'phone': 'newhire',
          'active': true,
        };
        mockApiClient.onPut = (url) {
          if (url == ApiEndpoints.employeeDetail('emp_srv_99')) {
            mockConnectivity.mockOffline = true;
            throw Exception('Lost connection on PUT');
          }
        };

        final midDrain = await ownerRepo.processPendingOwnerActions();
        expect(midDrain, isFalse);

        final rem = localCache.getPendingOwnerActionsQueue();
        expect(rem.length, 1);
        expect(rem.first['type'], 'set_staff_active');
        expect(rem.first['payload']['employeeId'], 'emp_srv_99');
        mockApiClient.onPut = null;
      },
    );

    test(
      'createProduct and updateProduct POST /api/v1/products with discriminated union body',
      () async {
        mockConnectivity.mockOffline = false;
        mockApiClient.responses[ApiEndpoints.products] = {
          'id': 'prod-item-1',
          'name': 'Shirt Press',
          'category': 'Ironing',
          'active': true,
          'type': 'item',
          'price': 5000,
        };

        await ownerRepo.createProduct(
          id: 'prod-item-1',
          name: 'Shirt Press',
          category: 'Ironing',
          unit: 'ITEM',
          price: 5000,
          active: true,
        );

        expect(mockApiClient.postUrls.last, ApiEndpoints.products);
        expect(mockApiClient.putUrls, isEmpty);
        expect(
          mockApiClient.postBodies.last,
          equals({
            'id': 'prod-item-1',
            'name': 'Shirt Press',
            'category': 'Ironing',
            'active': true,
            'type': 'item',
            'price': 5000,
          }),
        );

        mockApiClient.responses[ApiEndpoints.products] = {
          'id': 'prod-weight-1',
          'name': 'Wash & Fold',
          'category': 'Laundry',
          'active': true,
          'type': 'weight',
          'slabs': [
            {'limit': 5.0, 'price': 20000},
          ],
          'extra': 3500,
        };

        await ownerRepo.updateProduct(
          id: 'prod-weight-1',
          name: 'Wash & Fold',
          category: 'Laundry',
          unit: 'WEIGHT',
          price: 0,
          slabs: [
            {'limit': 5.0, 'price': 20000},
          ],
          active: true,
          extra: 3500,
        );

        expect(mockApiClient.postUrls.last, ApiEndpoints.products);
        expect(mockApiClient.putUrls, isEmpty);
        expect(
          mockApiClient.postBodies.last,
          equals({
            'id': 'prod-weight-1',
            'name': 'Wash & Fold',
            'category': 'Laundry',
            'active': true,
            'type': 'weight',
            'slabs': [
              {'limit': 5.0, 'price': 20000},
            ],
            'extra': 3500,
          }),
        );
      },
    );

    test(
      'create_expense offline replay sends the SAME idempotencyKey that was passed when queued, and createStaff forwards idempotencyKey',
      () async {
        // 1. Offline createExpense with explicit idempotencyKey
        mockConnectivity.mockOffline = true;
        await ownerRepo.createExpense(
          title: 'Packaging Bags',
          category: 'Supplies',
          amount: 1200,
          due: '2026-10-01',
          monthly: false,
          idempotencyKey: 'idem-exp-fixed-001',
        );

        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['payload']['idempotencyKey'], 'idem-exp-fixed-001');

        // Replay online
        mockConnectivity.mockOffline = false;
        mockApiClient.responses[ApiEndpoints.expenses] = {
          'id': 'exp_srv_1001',
          'title': 'Packaging Bags',
          'category': 'Supplies',
          'amount': 1200,
          'due': '2026-10-01',
          'monthly': false,
        };
        await ownerRepo.processPendingOwnerActions();

        expect(mockApiClient.postUrls.last, ApiEndpoints.expenses);
        expect(
          (mockApiClient.postBodies.last as Map)['idempotencyKey'],
          'idem-exp-fixed-001',
        );

        // 2. Online createStaff forwards idempotencyKey
        mockApiClient.responses[ApiEndpoints.employees] = {
          'id': 'emp_srv_2002',
          'name': 'Dan Staff',
          'phone': 'dan_s',
          'active': true,
        };
        await ownerRepo.createStaff(
          name: 'Dan Staff',
          phone: 'dan_s',
          password: 'password123',
          idempotencyKey: 'idem-staff-fixed-002',
        );

        expect(mockApiClient.postUrls.last, ApiEndpoints.employees);
        expect(
          (mockApiClient.postBodies.last as Map)['idempotencyKey'],
          'idem-staff-fixed-002',
        );
        expect((mockApiClient.postBodies.last as Map)['active'], isTrue);
      },
    );

    test(
      'F3 warm-cache open: LoadDashboardEvent and LoadExpensesEvent (with empty [] cached expenses) emit cached data and make zero apiClient.get calls',
      () async {
        await localCache.setCachedDashboardMetrics({
          'todaySales': 48000,
          'todayCount': 12,
          'periodSales': 48000,
          'periodOrders': 12,
        });
        await localCache.setCachedExpenses([]);

        mockApiClient.getUrls.clear();
        final ownerBloc = OwnerBloc(ownerRepository: ownerRepo);
        addTearDown(ownerBloc.close);

        ownerBloc.add(LoadDashboardEvent());
        ownerBloc.add(LoadExpensesEvent());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(ownerBloc.state.metrics.todayCount, 12);
        expect(ownerBloc.state.expenses, isEmpty);
        expect(mockApiClient.getUrls, isEmpty);
      },
    );
  });
}
