import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

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
  bool shouldThrow = false;
  Exception? errorToThrow;
  int getCallCount = 0;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getCallCount++;
    if (shouldThrow) {
      throw errorToThrow ?? Exception('Network failure');
    }
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) {
        return entry.value;
      }
    }
    throw Exception('Unhandled URL: $url');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late LocalCacheService localCache;
  late FakeConnectivityService fakeConnectivity;
  late FakeApiClient fakeApiClient;
  late OwnerRepository ownerRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_owner_repo_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    fakeConnectivity = FakeConnectivityService(mockOffline: false);
    ConnectivityService.instance = fakeConnectivity;
    fakeApiClient = FakeApiClient();
    ownerRepo = OwnerRepository(
      apiClient: fakeApiClient,
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

  group('OwnerRepository getDashboardMetrics Cache-First Tests', () {
    final mockMetricsJson = {
      'todaySales': 35000,
      'todayCount': 4,
      'periodSales': 120000,
      'periodOrders': 15,
      'todo': 2,
      'completed': 10,
      'outstanding': 5000,
      'overdue': 0,
      'dueToday': 1,
      'serviceMix': [
        {'label': 'Wash & Fold', 'amount': 20000},
      ],
      'cash': [
        {'label': 'Mon', 'income': 15000, 'expenses': 3000},
      ],
    };

    test('A custom date range is fetched but not cached', () async {
      fakeConnectivity.mockOffline = false;
      final customUrl = Uri.parse(ApiEndpoints.dashboard)
          .replace(queryParameters: {'from': '2026-09-01', 'to': '2026-09-10'})
          .toString();
      fakeApiClient.responses[customUrl] = mockMetricsJson;

      final metrics = await ownerRepo.getDashboardMetrics(
        from: '2026-09-01',
        to: '2026-09-10',
      );

      expect(fakeApiClient.getCallCount, 1);
      expect(metrics.todaySales, 35000);
      expect(localCache.getCachedDashboardMetrics(), isNull);
    });

    test('Online success writes cache and returns data', () async {
      fakeConnectivity.mockOffline = false;
      fakeApiClient.responses[ApiEndpoints.dashboard] = mockMetricsJson;

      expect(localCache.getCachedDashboardMetrics(), isNull);

      final metrics = await ownerRepo.getDashboardMetrics();

      expect(fakeApiClient.getCallCount, 1);
      expect(metrics.todaySales, 35000);
      expect(metrics.serviceMix.first.label, 'Wash & Fold');

      final cached = localCache.getCachedDashboardMetrics();
      expect(cached, isNotNull);
      expect(cached?['todaySales'], 35000);
    });

    test(
      'Offline with cache returns cached data without calling network',
      () async {
        await localCache.setCachedDashboardMetrics(mockMetricsJson);
        fakeConnectivity.mockOffline = true;

        final metrics = await ownerRepo.getDashboardMetrics();

        expect(fakeApiClient.getCallCount, 0);
        expect(metrics.todaySales, 35000);
        expect(metrics.todayCount, 4);
      },
    );

    test('Offline without cache throws clear error', () async {
      fakeConnectivity.mockOffline = true;

      expect(
        () => ownerRepo.getDashboardMetrics(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'No network connection and no cached dashboard metrics available',
            ),
          ),
        ),
      );
      expect(fakeApiClient.getCallCount, 0);
    });

    test('Online network failure falls back to cached data', () async {
      await localCache.setCachedDashboardMetrics(mockMetricsJson);
      fakeConnectivity.mockOffline = false;
      fakeApiClient.shouldThrow = true;

      final metrics = await ownerRepo.getDashboardMetrics();

      expect(fakeApiClient.getCallCount, 1);
      expect(metrics.todaySales, 35000);
    });
  });

  group('OwnerRepository listExpenses Cache-First Tests', () {
    final mockExpensesJson = [
      {
        'id': 'exp-1',
        'title': 'Detergent Bulk',
        'category': 'Supplies',
        'amount': 4500,
        'due': '2026-09-12',
        'paid': '2026-09-12',
        'monthly': false,
      },
      {
        'id': 'exp-2',
        'title': 'Shop Rent',
        'category': 'Rent',
        'amount': 25000,
        'due': '2026-09-15',
        'monthly': true,
      },
    ];

    test('Online success writes cache and returns data', () async {
      fakeConnectivity.mockOffline = false;
      fakeApiClient.responses[ApiEndpoints.expenses] = mockExpensesJson;

      expect(localCache.getCachedExpenses(), isNull);

      final expenses = await ownerRepo.listExpenses();

      expect(fakeApiClient.getCallCount, 1);
      expect(expenses.length, 2);
      expect(expenses.first.title, 'Detergent Bulk');

      final cached = localCache.getCachedExpenses();
      expect(cached, isNotNull);
      expect(cached?.length, 2);
      expect(cached?.first['title'], 'Detergent Bulk');
    });

    test(
      'Offline with cache returns cached data without calling network',
      () async {
        await localCache.setCachedExpenses(mockExpensesJson);
        fakeConnectivity.mockOffline = true;

        final expenses = await ownerRepo.listExpenses();

        expect(fakeApiClient.getCallCount, 0);
        expect(expenses.length, 2);
        expect(expenses[1].category, 'Rent');
      },
    );

    test('Offline without cache throws clear error', () async {
      fakeConnectivity.mockOffline = true;

      expect(
        () => ownerRepo.listExpenses(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'No network connection and no cached expenses available',
            ),
          ),
        ),
      );
      expect(fakeApiClient.getCallCount, 0);
    });

    test('Online network failure falls back to cached data', () async {
      await localCache.setCachedExpenses(mockExpensesJson);
      fakeConnectivity.mockOffline = false;
      fakeApiClient.shouldThrow = true;

      final expenses = await ownerRepo.listExpenses();

      expect(fakeApiClient.getCallCount, 1);
      expect(expenses.length, 2);
      expect(expenses.first.id, 'exp-1');
    });
  });

  group('OwnerRepository listStaff, listPaymentMethods, getStoreProfile Cache-First Tests', () {
    test('Staff: offline with cache returns cached staff', () async {
      final staffList = [
        {'id': 'st-1', 'name': 'John Staff', 'phone': 'john', 'active': true},
      ];
      await localCache.setCachedStaff(staffList);
      fakeConnectivity.mockOffline = true;

      final staff = await ownerRepo.listStaff();
      expect(fakeApiClient.getCallCount, 0);
      expect(staff.length, 1);
      expect(staff.first.name, 'John Staff');
    });

    test('Staff: offline without cache throws clear error', () async {
      fakeConnectivity.mockOffline = true;

      expect(
        () => ownerRepo.listStaff(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'No network connection and no cached staff available',
            ),
          ),
        ),
      );
    });

    test(
      'Payment Methods: offline with cache returns cached methods',
      () async {
        final methodsList = [
          {'id': 'pm-cash', 'name': 'Cash', 'type': 'Cash', 'active': true},
        ];
        await localCache.setCachedPaymentMethods(methodsList);
        fakeConnectivity.mockOffline = true;

        final methods = await ownerRepo.listPaymentMethods();
        expect(fakeApiClient.getCallCount, 0);
        expect(methods.length, 1);
        expect(methods.first.name, 'Cash');
      },
    );

    test('Payment Methods: offline without cache throws clear error', () async {
      fakeConnectivity.mockOffline = true;

      expect(
        () => ownerRepo.listPaymentMethods(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'No network connection and no cached payment methods available',
            ),
          ),
        ),
      );
    });

    test(
      'Store Profile: offline with cache returns cached store profile',
      () async {
        final profileMap = {
          'store': 'Clean Express',
          'address': '123 Main Road',
          'phone': '9988776655',
          'email': 'clean@express.com',
          'name': 'Owner Raj',
        };
        await localCache.setCachedStoreProfile(profileMap);
        fakeConnectivity.mockOffline = true;

        final profile = await ownerRepo.getStoreProfile();
        expect(fakeApiClient.getCallCount, 0);
        expect(profile.storeName, 'Clean Express');
        expect(profile.phone, '9988776655');
      },
    );

    test('Store Profile: offline without cache throws clear error', () async {
      fakeConnectivity.mockOffline = true;

      expect(
        () => ownerRepo.getStoreProfile(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'No network connection and no cached store profile available',
            ),
          ),
        ),
      );
    });
  });
}
