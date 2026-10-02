import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';

import '../helpers/mock_dio.dart';

class _MockConnectivityService extends ConnectivityService {
  _MockConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class _TestSecureStorage extends SecureStorageService {
  @override
  Future<String?> getToken() async => 'test_token';
}

class _RecordingApiClient implements ApiClient {
  final List<String> getUrls = [];
  final List<String> postUrls = [];
  final List<Map<String, String>?> postHeaders = [];
  final List<dynamic> postBodies = [];

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
    if (url.contains('/expenses')) {
      return <dynamic>[];
    }
    return <String, dynamic>{
      'todaySales': 1000,
      'todayCount': 1,
      'periodSales': 5000,
      'periodOrders': 5,
    };
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    postUrls.add(url);
    postHeaders.add(headers);
    postBodies.add(body);
    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    return <String, dynamic>{
      'id': 'exp-server-1',
      'title': map['title'] ?? 'Item',
      'category': map['category'] ?? 'Operations',
      'amount': map['amount'] ?? 1000,
      'due': map['due'] ?? '2026-09-26',
      'monthly': map['monthly'] ?? false,
    };
  }

  final List<String> putUrls = [];
  final List<dynamic> putBodies = [];
  final List<String> deleteUrls = [];

  @override
  Future<dynamic> put(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    putUrls.add(url);
    putBodies.add(body);
    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    return <String, dynamic>{
      'id': url.split('/').last,
      'title': map['title'] ?? 'Updated',
      'category': map['category'] ?? 'Operations',
      'amount': map['amount'] ?? 1000,
      'due': map['due'] ?? '2026-09-26',
      'monthly': map['monthly'] ?? false,
      if (map['outletId'] != null) 'outletId': map['outletId'],
    };
  }

  @override
  Future<dynamic> delete(String url, {Map<String, String>? headers}) async {
    deleteUrls.add(url);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers the expenses list with whatever the "server" currently holds.
class _ServerListApiClient extends _RecordingApiClient {
  _ServerListApiClient(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
    return url.contains('/expenses') ? rows : <String, dynamic>{};
  }
}

class _FailOnceExpenseListApiClient extends _RecordingApiClient {
  var calls = 0;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
    calls++;
    if (calls == 1) throw Exception('temporary failure');
    return <dynamic>[];
  }
}

class _TrackingOwnerBloc extends Bloc<OwnerEvent, OwnerState>
    implements OwnerBloc {
  final List<OwnerEvent> events = [];

  _TrackingOwnerBloc([OwnerState? initial])
    : super(initial ?? OwnerState(expenses: const [])) {
    on<OwnerEvent>((event, emit) {
      events.add(event);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalCacheService localCache;
  late _MockConnectivityService mockConnectivity;

  final outlets = [
    {
      'id': 'o1',
      'outletCode': 'O01',
      'displayName': 'Indiranagar',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'o2',
      'outletCode': 'O02',
      'displayName': 'Koramangala',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  group('Expenses & Dashboard Outlet Scope Unit Tests', () {
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('expenses_outlet_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalCacheService.boxName);
      localCache = LocalCacheService();
    });

    setUp(() async {
      await localCache.clear();
      await localCache.setActiveStoreId('store_1');
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      await localCache.setAllowedOutletsForStore('store_1', outlets);

      mockConnectivity = _MockConnectivityService(mockOffline: false);
      ConnectivityService.instance = mockConnectivity;
    });

    tearDown(() {
      ConnectivityService.instance = ConnectivityService.internal();
    });

    tearDownAll(() async {
      if (Hive.isBoxOpen(LocalCacheService.boxName)) {
        await Hive.box(LocalCacheService.boxName).close();
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Expense model round-trip with outletId, null outletId, and legacy JSON',
      () {
        final expWithOutlet = Expense(
          id: 'exp-1',
          outletId: 'out-1',
          title: 'Detergent',
          category: 'Supplies',
          amount: 5000,
          due: '2026-10-05',
          paid: '2026-10-01',
          monthly: true,
          seriesId: 'series-1',
        );
        final jsonWithOutlet = expWithOutlet.toJson();
        expect(jsonWithOutlet['outletId'], 'out-1');
        final roundTrip = Expense.fromJson(jsonWithOutlet);
        expect(roundTrip.outletId, 'out-1');
        expect(roundTrip.id, 'exp-1');
        expect(roundTrip.title, 'Detergent');
        expect(roundTrip.isPaid, isTrue);

        // Org-wide (null outletId)
        final expOrgWide = Expense(
          id: 'exp-2',
          title: 'Internet',
          category: 'Utilities',
          amount: 20000,
          due: '2026-10-10',
        );
        final jsonOrgWide = expOrgWide.toJson();
        expect(jsonOrgWide['outletId'], isNull);
        final roundTripOrgWide = Expense.fromJson(jsonOrgWide);
        expect(roundTripOrgWide.outletId, isNull);

        // Legacy cached JSON without 'outletId' key
        final legacyJson = {
          'id': 'exp-legacy',
          'title': 'Rent',
          'category': 'Rent',
          'amount': 50000,
          'due': '2026-10-01',
          'paid': '2026-10-01',
          'monthly': false,
        };
        final legacyExp = Expense.fromJson(legacyJson);
        expect(legacyExp.outletId, isNull);
        expect(legacyExp.id, 'exp-legacy');
        expect(legacyExp.title, 'Rent');
      },
    );

    test(
      'expenses cache keys differ per outlet and all-outlets scope',
      () async {
        // Outlet o1
        await localCache.setAllOutletsScope(false);
        await localCache.setActiveOutletId('o1');
        await localCache.setCachedExpenses([
          {'id': 'e-o1', 'title': 'Rent O1', 'amount': 1000},
        ]);

        // Outlet o2
        await localCache.setActiveOutletId('o2');
        expect(localCache.getCachedExpenses(), isNull);
        await localCache.setCachedExpenses([
          {'id': 'e-o2', 'title': 'Rent O2', 'amount': 2000},
        ]);

        // All-outlets scope
        await localCache.clearActiveOutletId();
        await localCache.setAllOutletsScope(true);
        expect(localCache.getCachedExpenses(), isNull);
        await localCache.setCachedExpenses([
          {'id': 'e-all', 'title': 'Org Wide', 'amount': 3000},
        ]);

        // Verify each scope reads back its own isolated list
        expect(localCache.getCachedExpenses()!.single['id'], 'e-all');

        await localCache.setAllOutletsScope(false);
        await localCache.setActiveOutletId('o1');
        expect(localCache.getCachedExpenses()!.single['id'], 'e-o1');

        await localCache.setActiveOutletId('o2');
        expect(localCache.getCachedExpenses()!.single['id'], 'e-o2');
      },
    );

    test('queued create_expense stores outletId in outlet scope and null in all-outlets scope', () async {
      mockConnectivity.mockOffline = true;
      final apiClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );

      // 1. Specific outlet o1
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');

      await repo.createExpense(
        title: 'Detergent O1',
        category: 'Supplies',
        amount: 25000,
        due: '2026-09-26',
      );

      // 2. All-outlets scope
      await localCache.clearActiveOutletId();
      await localCache.setAllOutletsScope(true);

      await repo.createExpense(
        title: 'Company Insurance',
        category: 'Operations',
        amount: 90000,
        due: '2026-09-26',
      );

      final queue = localCache.getPendingOwnerActionsQueue();
      expect(queue.length, 2);

      expect(queue[0]['type'], 'create_expense');
      expect(queue[0].containsKey('outletId'), isTrue);
      expect(queue[0]['outletId'], 'o1');

      expect(queue[1]['type'], 'create_expense');
      expect(queue[1].containsKey('outletId'), isTrue);
      expect(queue[1]['outletId'], isNull);
    });

    test('a bill made offline lands in every cached list it belongs in, and in no other', () async {
      mockConnectivity.mockOffline = true;
      final repo = OwnerRepository(
        apiClient: _RecordingApiClient(),
        localCache: localCache,
      );
      // Viewing o1; All and o2 are cached on the phone, o3 never was.
      await localCache.setAllowedOutletsForStore('store_1', [
        ...outlets,
        {
          'id': 'o3',
          'outletCode': 'O03',
          'displayName': 'Jayanagar',
          'isDefault': false,
          'status': 'ACTIVE',
        },
      ]);
      await localCache.setActiveOutletId('o1');
      await localCache.setAllOutletsScope(false);
      await localCache.setCachedExpensesForScope('all', []);
      await localCache.setCachedExpensesForScope('o1', []);
      await localCache.setCachedExpensesForScope('o2', []);

      List<String> titles(String scope) => [
        for (final e in localCache.getCachedExpensesForScope(scope) ?? [])
          e['title'].toString(),
      ];

      // For o2, made while viewing o1.
      await repo.createExpense(
        title: 'Rent for o2',
        category: 'Operations',
        amount: 50000,
        due: '2026-10-01',
        outletId: 'o2',
      );
      expect(titles('all'), ['Rent for o2']);
      expect(titles('o2'), ['Rent for o2']);
      expect(titles('o1'), isEmpty, reason: 'it is not an o1 bill');
      expect(
        localCache.getCachedExpensesForScope('o3'),
        isNull,
        reason: 'a one-row cache would make o3 look synced',
      );
      expect(
        localCache.getCachedExpensesForScope('all')!.single['outletId'],
        'o2',
      );

      // Organization-wide: only the combined view holds it.
      await repo.createExpense(
        title: 'Insurance',
        category: 'Operations',
        amount: 90000,
        due: '2026-10-01',
        orgWide: true,
      );
      expect(titles('all'), containsAll(['Insurance', 'Rent for o2']));
      expect(titles('o1'), isEmpty);
      expect(titles('o2'), ['Rent for o2']);
    });

    test('a refresh keeps a mark-paid and a bill that are still waiting to sync', () async {
      final apiClient = _ServerListApiClient([
        {
          'id': 'exp-9',
          'title': 'Water',
          'category': 'Utilities',
          'amount': 80000,
          'due': '2026-10-01',
          'monthly': false,
        },
      ]);
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );
      await localCache.setAllOutletsScope(true);
      await localCache.setCachedExpensesForScope('all', []);

      // Offline: mark the server's bill paid on a past date and make a new one.
      mockConnectivity.mockOffline = true;
      await repo.markExpensePaid('exp-9', paidDate: '2026-09-15');
      await repo.createExpense(
        title: 'Offline Bill',
        category: 'Operations',
        amount: 30000,
        due: '2026-10-01',
        orgWide: true,
      );
      expect(localCache.getPendingOwnerActionsQueue(), hasLength(2));

      // Back online and refreshing before the queue has been sent: the server
      // still says unpaid and has never heard of the new bill.
      mockConnectivity.mockOffline = false;
      final refreshed = await repo.listExpenses();

      final water = refreshed.firstWhere((e) => e.id == 'exp-9');
      expect(water.paid, '2026-09-15', reason: 'must not flip back to unpaid');
      expect(refreshed.map((e) => e.title), contains('Offline Bill'));
      // And what is saved on the phone agrees with what was shown.
      final cached = localCache.getCachedExpensesForScope('all')!;
      expect(
        cached.firstWhere((e) => e['id'] == 'exp-9')['paid'],
        '2026-09-15',
      );
      expect(cached.any((e) => e['title'] == 'Offline Bill'), isTrue);

      // Once the queue is gone the server's answer is taken as it is.
      await localCache.clearPendingOwnerActionsQueue();
      final after = await repo.listExpenses();
      expect(after.firstWhere((e) => e.id == 'exp-9').paid, isNull);
      expect(after.map((e) => e.title), isNot(contains('Offline Bill')));
    });

    test(
      'a successful expense retry clears only its stale refresh error',
      () async {
        SyncManager.instance.completeSync(force: true);
        addTearDown(() => SyncManager.instance.completeSync(force: true));
        await localCache.setAllOutletsScope(true);
        await localCache.setCachedExpensesForScope('all', []);
        await localCache.setPendingSyncQueue([
          {'clientActionId': 'pending-order', 'type': 'unknown'},
        ]);
        final repo = OwnerRepository(
          apiClient: _FailOnceExpenseListApiClient(),
          localCache: localCache,
        );

        await repo.listExpenses();
        expect(SyncManager.instance.value.hasError, isTrue);
        expect(
          SyncManager.instance.value.message,
          startsWith('Could not refresh expenses'),
        );

        await repo.listExpenses();
        expect(SyncManager.instance.value.hasError, isFalse);
        expect(SyncManager.instance.value.isPendingOnline, isTrue);

        SyncManager.instance.setError('Could not refresh dashboard');
        await repo.listExpenses();
        expect(SyncManager.instance.value.hasError, isTrue);
        expect(
          SyncManager.instance.value.message,
          'Could not refresh dashboard',
        );
      },
    );

    test('replay sends outlet header for outlet-scoped action, and kNoOutletHeader (omitted on wire) for org-wide action', () async {
      // First verify the headers passed to ApiClient.post
      final recordingClient = _RecordingApiClient();
      final repoWithRecording = OwnerRepository(
        apiClient: recordingClient,
        localCache: localCache,
      );

      await localCache.setPendingOwnerActionsQueue([
        {
          'clientActionId': 'act_o1',
          'type': 'create_expense',
          'outletId': 'o1',
          'payload': {
            'localId': 'LOCAL-1',
            'title': 'Outlet 1 Bill',
            'category': 'Utilities',
            'amount': 12000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
        {
          'clientActionId': 'act_org',
          'type': 'create_expense',
          'outletId': null,
          'payload': {
            'localId': 'LOCAL-2',
            'title': 'Org Bill',
            'category': 'Operations',
            'amount': 50000,
            'due': '2026-09-26',
            'monthly': true,
          },
        },
        {
          'clientActionId': 'act_legacy',
          'type': 'create_expense',
          'payload': {
            'localId': 'LOCAL-3',
            'title': 'Legacy Bill',
            'category': 'Other',
            'amount': 8000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
      ]);

      mockConnectivity.mockOffline = false;
      final ok = await repoWithRecording.processPendingOwnerActions();
      expect(ok, isTrue);
      expect(recordingClient.postHeaders.length, 3);
      expect(recordingClient.postHeaders[0], {'X-Outlet-Id': 'o1'});
      expect(recordingClient.postHeaders[1], {'X-Outlet-Id': kNoOutletHeader});
      expect(recordingClient.postHeaders[2], isNull);

      // Now verify wire headers through Dio + AuthInterceptor even when activeOutletId is 'o2'
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o2');

      final wireHeaders = <Map<String, dynamic>>[];
      final mockDio = createMockDio((options) async {
        wireHeaders.add(Map<String, dynamic>.from(options.headers));
        return mockJsonResponse({
          'id': 'exp-wire-${wireHeaders.length}',
          'title': 'Bill',
          'category': 'Operations',
          'amount': 1000,
          'due': '2026-09-26',
          'monthly': false,
        });
      });

      final dioApiClient = ApiClient(
        dio: mockDio,
        secureStorage: _TestSecureStorage(),
        localCache: localCache,
      );
      final repoWithDio = OwnerRepository(
        apiClient: dioApiClient,
        localCache: localCache,
      );

      await localCache.setPendingOwnerActionsQueue([
        {
          'clientActionId': 'wire_o1',
          'type': 'create_expense',
          'outletId': 'o1',
          'payload': {
            'localId': 'LOCAL-10',
            'title': 'Outlet 1 Bill',
            'category': 'Utilities',
            'amount': 12000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
        {
          'clientActionId': 'wire_org',
          'type': 'create_expense',
          'outletId': null,
          'payload': {
            'localId': 'LOCAL-11',
            'title': 'Org Bill',
            'category': 'Operations',
            'amount': 50000,
            'due': '2026-09-26',
            'monthly': true,
          },
        },
      ]);

      final wireOk = await repoWithDio.processPendingOwnerActions();
      expect(wireOk, isTrue);
      expect(wireHeaders.length, 2);
      // First action had outletId: 'o1' -> wire has X-Outlet-Id: o1 (not active o2)
      expect(wireHeaders[0]['X-Outlet-Id'], 'o1');
      // Second action had outletId: null -> kNoOutletHeader stripped by AuthInterceptor -> omitted on wire!
      expect(wireHeaders[1].containsKey('X-Outlet-Id'), isFalse);
    });

    test('dashboard GET URL contains outletId=o1 in outlet scope and no outletId in all-outlets scope', () async {
      final recordingClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: recordingClient,
        localCache: localCache,
      );

      // 1. Outlet scope (o1)
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');
      await repo.getDashboardMetrics(from: '2026-09-01', to: '2026-09-26');

      expect(recordingClient.getUrls.length, 1);
      final outletUri = Uri.parse(recordingClient.getUrls.first);
      expect(outletUri.queryParameters['outletId'], 'o1');
      expect(outletUri.queryParameters['from'], '2026-09-01');
      expect(outletUri.queryParameters['to'], '2026-09-26');

      // 2. All-outlets scope
      recordingClient.getUrls.clear();
      await localCache.clearActiveOutletId();
      await localCache.setAllOutletsScope(true);
      await repo.getDashboardMetrics(from: '2026-09-01', to: '2026-09-26');

      expect(recordingClient.getUrls.length, 1);
      final allOutletsUri = Uri.parse(recordingClient.getUrls.first);
      expect(allOutletsUri.queryParameters.containsKey('outletId'), isFalse);
    });

    test('updateExpense and deleteExpense throw clear exception when offline and never enqueue', () async {
      mockConnectivity.mockOffline = true;
      final apiClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );

      // Populate cache with an expense
      await localCache.setCachedExpenses([
        {
          'id': 'exp-100',
          'title': 'Paper Cups',
          'category': 'Supplies',
          'amount': 500,
          'due': '2026-10-01',
          'monthly': false,
        },
      ]);

      // updateExpense throws offline
      expect(
        () => repo.updateExpense(
          'exp-100',
          title: 'Paper Cups & Plates',
          category: 'Supplies',
          amount: 800,
          due: '2026-10-01',
        ),
        throwsA(
          predicate((e) => e.toString().contains('This needs a connection')),
        ),
      );

      // deleteExpense throws offline
      expect(
        () => repo.deleteExpense('exp-100'),
        throwsA(
          predicate((e) => e.toString().contains('This needs a connection')),
        ),
      );

      // Queue remains empty
      expect(localCache.getPendingOwnerActionsQueue(), isEmpty);
    });

    test(
      'updateExpense and deleteExpense online update/remove cached item',
      () async {
        mockConnectivity.mockOffline = false;
        final apiClient = _RecordingApiClient();
        final repo = OwnerRepository(
          apiClient: apiClient,
          localCache: localCache,
        );

        await localCache.setCachedExpenses([
          {
            'id': 'exp-101',
            'title': 'Detergent',
            'category': 'Supplies',
            'amount': 1500,
            'due': '2026-10-01',
            'monthly': false,
            'outletId': 'o1',
          },
        ]);

        // Online update
        await repo.updateExpense(
          'exp-101',
          title: 'Premium Detergent',
          category: 'Supplies',
          amount: 2500,
          due: '2026-10-02',
          outletId: 'o2',
        );

        expect(apiClient.putUrls.length, 1);
        expect(apiClient.putUrls.first, contains('/api/v1/expenses/exp-101'));
        expect(apiClient.putBodies.first, {
          'title': 'Premium Detergent',
          'category': 'Supplies',
          'amount': 2500,
          'due': '2026-10-02',
          'outletId': 'o2',
        });

        // Local cache updated
        final updatedList = localCache.getCachedExpenses();
        expect(updatedList!.length, 1);
        expect(updatedList.first['title'], 'Premium Detergent');
        expect(updatedList.first['amount'], 2500);
        expect(updatedList.first['outletId'], 'o2');

        // Online delete
        await repo.deleteExpense('exp-101');
        expect(apiClient.deleteUrls.length, 1);
        expect(
          apiClient.deleteUrls.first,
          contains('/api/v1/expenses/exp-101'),
        );

        // Local cache removed
        final afterDelete = localCache.getCachedExpenses();
        expect(afterDelete, isEmpty);
      },
    );

    test('a bill still syncing (LOCAL- id) cannot be edited or deleted and nothing is sent', () async {
      mockConnectivity.mockOffline = false;
      final apiClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );

      await expectLater(
        repo.updateExpense(
          'LOCAL-1790000000000',
          title: 'Rent',
          category: 'Operations',
          amount: 100,
          due: '2026-10-01',
        ),
        throwsA(
          isA<OwnerRefusedException>().having(
            (e) => e.message,
            'message',
            contains('still syncing'),
          ),
        ),
      );
      await expectLater(
        repo.deleteExpense('LOCAL-1790000000000'),
        throwsA(isA<OwnerRefusedException>()),
      );
      expect(apiClient.putUrls, isEmpty);
      expect(apiClient.deleteUrls, isEmpty);
    });

    test('edit and delete patch every cached scope without creating a cache that was never there', () async {
      mockConnectivity.mockOffline = false;
      final repo = OwnerRepository(
        apiClient: _RecordingApiClient(),
        localCache: localCache,
      );
      final threeOutlets = [
        ...outlets,
        {
          'id': 'o3',
          'outletCode': 'O03',
          'displayName': 'Jayanagar',
          'isDefault': false,
          'status': 'ACTIVE',
        },
      ];
      await localCache.setAllowedOutletsForStore('store_1', threeOutlets);
      await localCache.setActiveOutletId('o1');
      await localCache.setAllOutletsScope(false);

      Map<String, dynamic> bill(String id, String outletId) => {
        'id': id,
        'title': 'Bill $id',
        'category': 'Supplies',
        'amount': 1000,
        'due': '2026-10-01',
        'monthly': false,
        'outletId': outletId,
      };
      await localCache.setCachedExpensesForScope('all', [
        bill('exp-1', 'o1'),
        bill('exp-2', 'o2'),
      ]);
      await localCache.setCachedExpensesForScope('o1', [bill('exp-1', 'o1')]);
      await localCache.setCachedExpensesForScope('o2', [bill('exp-2', 'o2')]);
      // o3 has never been synced to this phone: no cache at all.

      // Move exp-1 from o1 to o2 while viewing o1.
      await repo.updateExpense(
        'exp-1',
        title: 'Bill exp-1',
        category: 'Supplies',
        amount: 1000,
        due: '2026-10-01',
        outletId: 'o2',
      );

      List<String> ids(String scope) => [
        for (final e in localCache.getCachedExpensesForScope(scope)!)
          e['id'].toString(),
      ];
      expect(ids('o1'), isEmpty, reason: 'no longer belongs to o1');
      expect(ids('o2'), containsAll(['exp-1', 'exp-2']));
      expect(
        localCache
            .getCachedExpensesForScope('all')!
            .firstWhere((e) => e['id'] == 'exp-1')['outletId'],
        'o2',
      );
      expect(
        localCache.getCachedExpensesForScope('o3'),
        isNull,
        reason: 'a one-row cache would make o3 look synced',
      );

      // Delete exp-2 while viewing o1: gone from every scope that had it.
      await repo.deleteExpense('exp-2');
      expect(ids('all'), ['exp-1']);
      expect(ids('o2'), ['exp-1']);
      expect(localCache.getCachedExpensesForScope('o3'), isNull);
    });

    test(
      'markExpensePaid online sends paidDate and cache stores YYYY-MM-DD',
      () async {
        mockConnectivity.mockOffline = false;
        final apiClient = _RecordingApiClient();
        final repo = OwnerRepository(
          apiClient: apiClient,
          localCache: localCache,
        );

        await localCache.setCachedExpenses([
          {
            'id': 'exp-201',
            'title': 'Rent',
            'category': 'Rent',
            'amount': 50000,
            'due': '2026-10-01',
            'paid': null,
            'monthly': false,
          },
        ]);

        await repo.markExpensePaid('exp-201', paidDate: '2026-10-04');

        expect(apiClient.postUrls.length, 1);
        expect(
          apiClient.postUrls.first,
          contains('/api/v1/expenses/exp-201/pay'),
        );
        expect(apiClient.postBodies.first, {'paidDate': '2026-10-04'});

        // Local cache stores YYYY-MM-DD
        final cached = localCache.getCachedExpenses()!;
        expect(cached.first['paid'], '2026-10-04');
      },
    );

    test(
      'markExpensePaid offline enqueues paidDate and cache stores YYYY-MM-DD',
      () async {
        mockConnectivity.mockOffline = true;
        final apiClient = _RecordingApiClient();
        final repo = OwnerRepository(
          apiClient: apiClient,
          localCache: localCache,
        );

        await localCache.setCachedExpenses([
          {
            'id': 'exp-202',
            'title': 'Electricity',
            'category': 'Utilities',
            'amount': 12000,
            'due': '2026-10-01',
            'paid': null,
            'monthly': false,
          },
        ]);

        await repo.markExpensePaid('exp-202', paidDate: '2026-10-03');

        // Local cache stores YYYY-MM-DD
        final cached = localCache.getCachedExpenses()!;
        expect(cached.first['paid'], '2026-10-03');

        // Pending action has paidDate in payload
        final queue = localCache.getPendingOwnerActionsQueue();
        expect(queue.length, 1);
        expect(queue.first['type'], 'mark_expense_paid');
        expect(queue.first['payload']['expenseId'], 'exp-202');
        expect(queue.first['payload']['paidDate'], '2026-10-03');
      },
    );

    test('replay of mark_expense_paid sends paidDate, and older queued action without paidDate falls back to today', () async {
      final recordingClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: recordingClient,
        localCache: localCache,
      );

      await localCache.setPendingOwnerActionsQueue([
        {
          'clientActionId': 'act_pay_1',
          'type': 'mark_expense_paid',
          'payload': {'expenseId': 'exp-pay-1', 'paidDate': '2026-09-30'},
        },
        {
          'clientActionId': 'act_pay_legacy',
          'type': 'mark_expense_paid',
          'payload': {'expenseId': 'exp-pay-legacy'},
        },
      ]);

      mockConnectivity.mockOffline = false;
      final ok = await repo.processPendingOwnerActions();
      expect(ok, isTrue);

      expect(recordingClient.postUrls.length, 2);
      expect(
        recordingClient.postUrls[0],
        contains('/api/v1/expenses/exp-pay-1/pay'),
      );
      expect(recordingClient.postBodies[0], {'paidDate': '2026-09-30'});

      expect(
        recordingClient.postUrls[1],
        contains('/api/v1/expenses/exp-pay-legacy/pay'),
      );
      expect(recordingClient.postBodies[1]['paidDate'], isNotNull);
      expect((recordingClient.postBodies[1]['paidDate'] as String).length, 10);
    });

    test('OwnerBloc update and delete success and offline handling', () async {
      final apiClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );
      final bloc = OwnerBloc(ownerRepository: repo);
      addTearDown(bloc.close);

      // 1. Online update success
      mockConnectivity.mockOffline = false;
      bloc.add(
        UpdateExpenseEvent(
          expenseId: 'exp-bloc-1',
          title: 'Updated Title',
          category: 'Repairs',
          amount: 4500,
          due: '2026-10-05',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.actionMessage, 'Expense updated');
      expect(bloc.state.error, isNull);

      // 2. Offline update failure surfaces 'This needs a connection'
      mockConnectivity.mockOffline = true;
      bloc.add(
        UpdateExpenseEvent(
          expenseId: 'exp-bloc-1',
          title: 'Fail Title',
          category: 'Repairs',
          amount: 4500,
          due: '2026-10-05',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.error, 'This needs a connection');

      // 3. Offline delete failure surfaces 'This needs a connection'
      bloc.add(DeleteExpenseEvent('exp-bloc-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.error, 'This needs a connection');

      // 4. Online delete success
      mockConnectivity.mockOffline = false;
      bloc.add(DeleteExpenseEvent('exp-bloc-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.actionMessage, 'Expense deleted');
      expect(bloc.state.error, isNull);
    });
  });

  group('Expenses & Dashboard Outlet Scope Widget Tests', () {
    testWidgets(
      'AddExpenseScreen shows organization-wide hint in all-outlets scope and outlet displayName hint in specific outlet scope',
      (tester) async {
        final widgetCache = _WidgetFakeLocalCache(allowedOutlets: outlets);
        final ownerBloc = _TrackingOwnerBloc();
        final outletCubit = OutletScopeCubit(localCache: widgetCache)
          ..adoptFromLogin(isOwner: true);
        addTearDown(ownerBloc.close);
        addTearDown(outletCubit.close);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<OwnerBloc>.value(value: ownerBloc),
              BlocProvider<OutletScopeCubit>.value(value: outletCubit),
            ],
            child: const MaterialApp(home: ExpensesScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // OutletTitleSwitcher is mounted in ExpensesScreen header
        expect(find.byType(OutletTitleSwitcher), findsOneWidget);
        expect(find.text('All outlets'), findsOneWidget);

        // Open AddExpenseScreen in All-outlets scope
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.byType(AddExpenseScreen), findsOneWidget);
        expect(
          find.text('This expense will be recorded as organization-wide.'),
          findsOneWidget,
        );

        // Pop back to ExpensesScreen
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Switch scope to specific outlet 'o1' (Indiranagar)
        final loadCountBefore = ownerBloc.events
            .whereType<LoadExpensesEvent>()
            .length;
        outletCubit.select('o1');
        await tester.pumpAndSettle();

        // BlocListener on ExpensesScreen dispatches LoadExpensesEvent on scope switch
        final loadCountAfter = ownerBloc.events
            .whereType<LoadExpensesEvent>()
            .length;
        expect(loadCountAfter, greaterThan(loadCountBefore));
        expect(find.text('Indiranagar'), findsOneWidget);

        // Open AddExpenseScreen in specific outlet scope
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.byType(AddExpenseScreen), findsOneWidget);
        expect(
          find.text('This expense will be recorded against Indiranagar.'),
          findsOneWidget,
        );
        expect(
          find.text('This expense will be recorded as organization-wide.'),
          findsNothing,
        );
      },
    );
  });
}

class _WidgetFakeLocalCache extends LocalCacheService {
  @override
  Map<String, dynamic>? getCachedUser() => null;

  final Map<String, String> _rememberedOutlets = {};
  @override
  String? getRememberedOutlet(String userId, String storeId) =>
      _rememberedOutlets['$userId::$storeId'];
  @override
  Future<void> setRememberedOutlet(
    String userId,
    String storeId,
    String outletId,
  ) async => _rememberedOutlets['$userId::$storeId'] = outletId;

  final List<Map<String, dynamic>> allowedOutlets;
  String? activeOutletId;
  bool allOutletsScope = true;

  _WidgetFakeLocalCache({required this.allowedOutlets});

  @override
  Map<String, dynamic>? getCachedStoreDetails() => const {'role': 'OWNER'};

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => allowedOutlets;

  @override
  String? getActiveOutletId() => activeOutletId;

  @override
  Future<void> setActiveOutletId(String outletId) async {
    activeOutletId = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    activeOutletId = null;
  }

  @override
  bool isAllOutletsScope() => allOutletsScope;

  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {
    allOutletsScope = allOutlets;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    allOutletsScope = false;
  }

  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
}
