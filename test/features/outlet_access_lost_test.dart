import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/auth/presentation/login_screen.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/presentation/outlet_required_screen.dart';
import 'package:myshop/main.dart';
import 'package:myshop/shared/widgets/blocked_screen.dart';

import '../helpers/mock_dio.dart';

class FakeSecureStorage extends SecureStorageService {
  String? token = 'tok_123';

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<void> deleteToken() async => token = null;
}

class InMemoryLocalCache extends LocalCacheService {
  // A phone that has already been through setup: the app opens straight
  // into the shell instead of the setup screen.
  List<Map<String, dynamic>>? _cachedOrders = [];
  @override
  List<Map<String, dynamic>>? getCachedOrders() => _cachedOrders;
  @override
  Future<void> setCachedOrders(List<Map<String, dynamic>> orders) async =>
      _cachedOrders = orders;

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

  String? _activeStoreId = 's1';
  Map<String, dynamic>? _cachedUser = {
    'id': 'u1',
    'name': 'Priya',
    'username': 'priya',
  };
  Map<String, dynamic>? _cachedStoreDetails = {
    'storeId': 's1',
    'storeName': 'Store 1',
    'role': 'EMPLOYEE',
  };
  List<Map<String, dynamic>>? _cachedAvailableStores = [
    {'storeId': 's1', 'storeName': 'Store 1', 'role': 'EMPLOYEE'},
  ];
  final Map<String, List<Map<String, dynamic>>> _outletsByStore = {};
  final Map<String, String?> _activeOutletByStore = {};
  final Map<String, bool> _allOutletsByStore = {};
  int clearAllOutletsScopeCalls = 0;

  @override
  String? getActiveStoreId() => _activeStoreId;

  @override
  Future<void> setActiveStoreId(String storeId) async {
    _activeStoreId = storeId;
  }

  @override
  Map<String, dynamic>? getCachedUser() => _cachedUser;

  @override
  Future<void> setCachedUser(Map<String, dynamic> userJson) async {
    _cachedUser = userJson;
  }

  @override
  Map<String, dynamic>? getCachedStoreDetails() => _cachedStoreDetails;

  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> storeJson) async {
    _cachedStoreDetails = storeJson;
  }

  @override
  List<Map<String, dynamic>>? getCachedAvailableStores() =>
      _cachedAvailableStores;

  @override
  Future<void> setCachedAvailableStores(
    List<Map<String, dynamic>> stores,
  ) async {
    _cachedAvailableStores = stores;
  }

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() {
    final s = _activeStoreId ?? 'none';
    return _outletsByStore[s];
  }

  Future<void> setAllowedOutlets(List<Map<String, dynamic>> outlets) async {
    final s = _activeStoreId ?? 'none';
    _outletsByStore[s] = outlets;
  }

  @override
  Future<void> setAllowedOutletsForStore(
    String storeId,
    List<Map<String, dynamic>> outlets,
  ) async {
    _outletsByStore[storeId] = outlets;
  }

  @override
  String? getActiveOutletId() {
    final s = _activeStoreId ?? 'none';
    return _activeOutletByStore[s];
  }

  @override
  Future<void> setActiveOutletId(String outletId) async {
    final s = _activeStoreId ?? 'none';
    _activeOutletByStore[s] = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    final s = _activeStoreId ?? 'none';
    _activeOutletByStore.remove(s);
  }

  @override
  bool isAllOutletsScope() {
    final s = _activeStoreId ?? 'none';
    return _allOutletsByStore[s] ?? false;
  }

  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {
    final s = _activeStoreId ?? 'none';
    _allOutletsByStore[s] = allOutlets;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    clearAllOutletsScopeCalls++;
    final s = _activeStoreId ?? 'none';
    _allOutletsByStore.remove(s);
  }

  @override
  Future<void> clear() async {
    _activeOutletByStore.clear();
    _allOutletsByStore.clear();
  }
}

class SpyAuthRepository extends AuthRepository {
  final InMemoryLocalCache cache;
  String role;
  int statusCalls = 0;
  int logoutCalls = 0;
  Future<List<Map<String, dynamic>>?> Function()? onRefreshOutletContext;

  SpyAuthRepository({
    required super.apiClient,
    required super.secureStorage,
    required this.cache,
    this.role = 'EMPLOYEE',
  }) : super(localCache: cache);

  @override
  Future<AuthResult?> checkSession() async {
    return AuthResult(
      user: User(id: 'u1', name: 'Priya', username: 'priya'),
      stores: [
        StoreSummary(storeId: 's1', storeName: 'Store 1', role: role),
      ],
    );
  }

  @override
  Future<List<Map<String, dynamic>>?> refreshOutletContext() async {
    statusCalls++;
    if (onRefreshOutletContext != null) {
      return onRefreshOutletContext!();
    }
    return super.refreshOutletContext();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

class StubPosRepository implements PosRepository {
  @override
  List<Product> getCachedProductsList() => [
    Product(
      id: 'p1',
      name: 'Shirt',
      price: 50,
      type: 'Dry Clean',
      category: 'Men',
    ),
  ];

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StubOrdersRepository implements OrdersRepository {
  @override
  List<Order> getCachedOrdersList() => [
    Order(
      id: 'ORD-1',
      name: 'Asha',
      phone: '9876543210',
      date: '2026-09-26',
      due: '2026-09-27',
      status: 'Pending',
      lines: const [],
      payments: const [],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StubOwnerRepository implements OwnerRepository {
  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => DashboardMetrics();

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async => DashboardMetrics();

  @override
  List<Expense> getCachedExpensesSync() => [];

  @override
  Future<List<Expense>> listExpenses() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final o1 = <String, dynamic>{
    'id': 'o1',
    'outletCode': 'OBLRCHN01',
    'displayName': 'Chinnapanahalli',
    'isDefault': true,
    'status': 'ACTIVE',
  };
  final o2 = <String, dynamic>{
    'id': 'o2',
    'outletCode': 'OBLRMTH02',
    'displayName': 'Marathahalli',
    'isDefault': false,
    'status': 'ACTIVE',
  };
  final o3 = <String, dynamic>{
    'id': 'o3',
    'outletCode': 'OBLRWHT03',
    'displayName': 'Whitefield',
    'isDefault': false,
    'status': 'ACTIVE',
  };

  group('Outlet access lost & Invalid outlet handling', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_outlet_lost_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalCacheService.boxName);
    });

    tearDownAll(() async {
      if (Hive.isBoxOpen(LocalCacheService.boxName)) {
        await Hive.box(LocalCacheService.boxName).close();
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'cold start with nothing synced for the active outlet opens the setup screen',
      (tester) async {
        final cache = InMemoryLocalCache().._cachedOrders = null;
        await cache.setAllowedOutletsForStore('s1', [o1, o2]);
        await cache.setActiveOutletId('o1');

        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: createMockDio((options) async => mockJsonResponse({})),
          secureStorage: storage,
          localCache: cache,
        );

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: SpyAuthRepository(
              apiClient: apiClient,
              secureStorage: storage,
              cache: cache,
            ),
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Setting things up'), findsOneWidget);
        expect(find.text('Opening your outlet'), findsOneWidget);
      },
    );

    testWidgets(
      'reason-less 403, previous outlet absent from fresh list -> clearSelection, NO AccessForbiddenEvent, snackbar shows outlet name',
      (tester) async {
        final cache = InMemoryLocalCache();
        await cache.setAllowedOutletsForStore('s1', [o1, o2, o3]);
        await cache.setActiveOutletId('o1');

        final mockDio = createMockDio((options) async {
          return mockJsonResponse({
            'user': {'id': 'u1', 'name': 'Priya', 'username': 'priya'},
            'stores': [
              {'storeId': 's1', 'storeName': 'Store 1', 'role': 'EMPLOYEE'},
            ],
            'organizations': [
              {
                'id': 's1',
                'allowedOutlets': [o2, o3],
              },
            ],
          });
        });

        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final authRepo = SpyAuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          cache: cache,
        );

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: authRepo,
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pumpAndSettle();

        // Trigger reason-less 403 via apiClient callback
        apiClient.onForbidden?.call(null, null);
        await tester.pumpAndSettle();

        expect(authRepo.statusCalls, 1);
        expect(authRepo.logoutCalls, 0);
        expect(cache.clearAllOutletsScopeCalls, greaterThan(0));
        expect(cache.getActiveOutletId(), isNull);
        // Re-scoped to picker (2 outlets remaining) instead of LoginScreen
        expect(find.byType(OutletRequiredScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(
          find.text(
            'You no longer have access to Chinnapanahalli. Choose another outlet.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reason-less 403, previous outlet still in fresh list -> AccessForbiddenEvent dispatched (sign-in path), clearSelection not called',
      (tester) async {
        final cache = InMemoryLocalCache();
        await cache.setAllowedOutletsForStore('s1', [o1, o2]);
        await cache.setActiveOutletId('o1');

        final mockDio = createMockDio((options) async {
          return mockJsonResponse({
            'user': {'id': 'u1', 'name': 'Priya', 'username': 'priya'},
            'stores': [
              {'storeId': 's1', 'storeName': 'Store 1', 'role': 'EMPLOYEE'},
            ],
            'organizations': [
              {
                'id': 's1',
                'allowedOutlets': [o1, o2],
              },
            ],
          });
        });

        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final authRepo = SpyAuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          cache: cache,
        );

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: authRepo,
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pumpAndSettle();

        apiClient.onForbidden?.call(null, null);
        await tester.pumpAndSettle();

        expect(authRepo.statusCalls, 1);
        // AccessForbiddenEvent triggers logout -> LoginScreen
        expect(authRepo.logoutCalls, 1);
        expect(cache.clearAllOutletsScopeCalls, 0);
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'reason-less 403 with previous == null (owner All outlets) -> AccessForbiddenEvent, no /auth/status call',
      (tester) async {
        final cache = InMemoryLocalCache();
        await cache.setCachedStoreDetails({
          'storeId': 's1',
          'storeName': 'Store 1',
          'role': 'OWNER',
        });
        await cache.setAllowedOutletsForStore('s1', [o1, o2]);
        await cache.setAllOutletsScope(true);

        final mockDio = createMockDio(
          (options) async => mockJsonResponse({'ok': true}),
        );
        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final authRepo = SpyAuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          cache: cache,
          role: 'OWNER',
        );

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: authRepo,
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pumpAndSettle();

        apiClient.onForbidden?.call(null, null);
        await tester.pumpAndSettle();

        expect(authRepo.statusCalls, 0);
        expect(authRepo.logoutCalls, 1);
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      '403 WITH reason store_locked -> unchanged AccessBlockedState path, no /auth/status call',
      (tester) async {
        final cache = InMemoryLocalCache();
        await cache.setAllowedOutletsForStore('s1', [o1]);
        await cache.setActiveOutletId('o1');

        final mockDio = createMockDio(
          (options) async => mockJsonResponse({'ok': true}),
        );
        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final authRepo = SpyAuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          cache: cache,
        );

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: authRepo,
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pumpAndSettle();

        apiClient.onForbidden?.call('store_locked', null);
        await tester.pumpAndSettle();

        expect(authRepo.statusCalls, 0);
        expect(authRepo.logoutCalls, 0);
        expect(find.byType(BlockedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'two 403s back-to-back -> exactly ONE /auth/status call (_rescoping guard)',
      (tester) async {
        final cache = InMemoryLocalCache();
        await cache.setAllowedOutletsForStore('s1', [o1, o2]);
        await cache.setActiveOutletId('o1');

        final completer = Completer<List<Map<String, dynamic>>?>();
        final mockDio = createMockDio(
          (options) async => mockJsonResponse({'ok': true}),
        );
        final storage = FakeSecureStorage();
        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: storage,
          localCache: cache,
        );
        final authRepo = SpyAuthRepository(
          apiClient: apiClient,
          secureStorage: storage,
          cache: cache,
        )..onRefreshOutletContext = () => completer.future;

        await tester.pumpWidget(
          MyShopApp(
            apiClient: apiClient,
            authRepository: authRepo,
            posRepository: StubPosRepository(),
            ordersRepository: StubOrdersRepository(),
            ownerRepository: StubOwnerRepository(),
            localCache: cache,
          ),
        );
        await tester.pumpAndSettle();

        // Fire two reason-less 403s back-to-back while refresh is in flight
        apiClient.onForbidden?.call(null, null);
        apiClient.onForbidden?.call(null, null);

        expect(authRepo.statusCalls, 1);

        await cache.setAllowedOutletsForStore('s1', [o2]);
        completer.complete([o2]);
        await tester.pumpAndSettle();

        expect(authRepo.statusCalls, 1);
      },
    );

    test(
      '400 {"error":"Invalid outlet."} fires onInvalidOutlet and still throws ValidationException; other 400 messages do not fire',
      () async {
        var invalidOutletCalls = 0;

        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/invalid-outlet')) {
            return mockJsonResponse({
              'error': 'Invalid outlet.',
            }, statusCode: 400);
          }
          return mockJsonResponse({
            'error': 'Some other validation error',
          }, statusCode: 400);
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: FakeSecureStorage(),
          localCache: InMemoryLocalCache(),
          onInvalidOutlet: () {
            invalidOutletCalls++;
          },
        );

        await expectLater(
          () => apiClient.get('https://example.com/api/v1/invalid-outlet'),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              'Invalid outlet.',
            ),
          ),
        );
        expect(invalidOutletCalls, 1);

        await expectLater(
          () => apiClient.get('https://example.com/api/v1/other-400'),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              'Some other validation error',
            ),
          ),
        );
        expect(invalidOutletCalls, 1);
      },
    );
  });
}
