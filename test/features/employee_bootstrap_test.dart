import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/auth/presentation/employee_bootstrap_screen.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

class FakeSecureStorage extends SecureStorageService {
  String? token = 'fake-token-xyz';
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> saveToken(String t) async => token = t;
  @override
  Future<void> deleteToken() async => token = null;
}

class FakeLocalCache extends LocalCacheService {
  final Map<String, dynamic> _memory = {};

  @override
  String? getActiveStoreId() => _memory['active_store_id'] as String?;
  @override
  Future<void> setActiveStoreId(String s) async =>
      _memory['active_store_id'] = s;

  @override
  Map<String, dynamic>? getCachedStoreProfile() =>
      _memory['cached_store_profile_json'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreProfile(Map<String, dynamic> p) async =>
      _memory['cached_store_profile_json'] = p;

  @override
  Map<String, dynamic>? getCachedStoreDetails() =>
      _memory['cached_store_details_json'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> s) async =>
      _memory['cached_store_details_json'] = s;

  @override
  List<Map<String, dynamic>>? getCachedAvailableStores() =>
      _memory['cached_available_stores_list'] as List<Map<String, dynamic>>?;
  @override
  Future<void> setCachedAvailableStores(List<Map<String, dynamic>> l) async =>
      _memory['cached_available_stores_list'] = l;

  @override
  Map<String, dynamic>? getCachedUser() =>
      _memory['cached_user_json'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedUser(Map<String, dynamic> u) async =>
      _memory['cached_user_json'] = u;

  @override
  List<Map<String, dynamic>>? getCachedProducts() =>
      _memory['cached_products_list'] as List<Map<String, dynamic>>?;
  @override
  Future<void> setCachedProducts(List<Map<String, dynamic>> p) async =>
      _memory['cached_products_list'] = p;

  @override
  List<Map<String, dynamic>>? getCachedOrders() =>
      _memory['cached_orders_list'] as List<Map<String, dynamic>>?;
  @override
  Future<void> setCachedOrders(List<Map<String, dynamic>> o) async =>
      _memory['cached_orders_list'] = o;

  @override
  List<Map<String, dynamic>> getPendingSyncQueue() => [];
}

class FakeAuthRepository extends AuthRepository {
  bool fetchStoreDetailsShouldFail = false;
  int fetchStoreDetailsCallCount = 0;
  final FakeLocalCache localCache;

  FakeAuthRepository({required this.localCache})
    : super(
        apiClient: ApiClient(),
        secureStorage: FakeSecureStorage(),
        localCache: localCache,
      );

  @override
  Future<Map<String, dynamic>> fetchStoreDetails() async {
    fetchStoreDetailsCallCount++;
    if (fetchStoreDetailsShouldFail) {
      throw Exception('Network error loading store profile');
    }
    final data = {
      'name': 'Test Owner',
      'phone': '9876543210',
      'email': 'store@example.com',
      'store': 'Express Laundry Demo',
      'address': '123 Test Street',
    };
    await localCache.setCachedStoreProfile(data);
    return data;
  }
}

class FakePosRepository extends PosRepository {
  bool listProductsShouldFail = false;
  int listProductsCallCount = 0;
  final FakeLocalCache localCache;

  FakePosRepository({required this.localCache})
    : super(apiClient: ApiClient(), localCache: localCache);

  @override
  Future<List<Product>> listProducts() async {
    listProductsCallCount++;
    if (listProductsShouldFail) {
      throw Exception('Network error loading products');
    }
    final products = [
      Product(
        id: 'prod-1',
        name: 'Wash & Fold',
        price: 50,
        type: 'item',
        category: 'Laundry',
      ),
    ];
    await localCache.setCachedProducts(
      products.map((p) => p.toJson()).toList(),
    );
    return products;
  }
}

class FakeOrdersRepository extends OrdersRepository {
  bool fetchRecentOrdersShouldFail = false;
  int fetchRecentOrdersCallCount = 0;
  int lastLimitPassed = 0;
  String lastSortPassed = '';
  final FakeLocalCache localCache;

  FakeOrdersRepository({required this.localCache})
    : super(apiClient: ApiClient(), localCache: localCache);

  @override
  Future<List<Order>> fetchRecentOrders({
    int limit = 30,
    String sort = 'recent',
  }) async {
    fetchRecentOrdersCallCount++;
    lastLimitPassed = limit;
    lastSortPassed = sort;
    if (fetchRecentOrdersShouldFail) {
      throw Exception('Network error loading recent orders');
    }
    final orders = [
      Order(
        id: 'EL-101',
        name: 'Customer One',
        phone: '9876543210',
        date: '2026-09-11',
        due: '2026-09-12',
        status: 'Pending',
        lines: [],
        payments: [],
      ),
    ];
    await localCache.setCachedOrders(orders.map((o) => o.toJson()).toList());
    return orders;
  }
}

class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService() : super.internal();
  bool mockOffline = false;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

void main() {
  group('EmployeeBootstrapScreen Tests', () {
    late FakeLocalCache fakeCache;
    late FakeAuthRepository fakeAuthRepo;
    late FakePosRepository fakePosRepo;
    late FakeOrdersRepository fakeOrdersRepo;
    late FakeConnectivityService fakeConnectivity;
    late AuthenticatedState employeeState;
    late AuthenticatedState ownerState;

    setUp(() {
      fakeCache = FakeLocalCache();
      fakeAuthRepo = FakeAuthRepository(localCache: fakeCache);
      fakePosRepo = FakePosRepository(localCache: fakeCache);
      fakeOrdersRepo = FakeOrdersRepository(localCache: fakeCache);
      fakeConnectivity = FakeConnectivityService();

      final employeeUser = User(
        id: 'u-emp',
        name: 'Staff John',
        username: 'john',
      );
      final employeeStore = StoreSummary(
        storeId: 'store-1',
        storeName: 'Express Laundry Demo',
        role: 'EMPLOYEE',
      );
      employeeState = AuthenticatedState(
        user: employeeUser,
        currentStore: employeeStore,
        availableStores: [employeeStore],
        isFreshLogin: true,
      );

      final ownerUser = User(
        id: 'u-owner',
        name: 'Owner Alice',
        username: 'alice',
      );
      final ownerStore = StoreSummary(
        storeId: 'store-1',
        storeName: 'Express Laundry Demo',
        role: 'OWNER',
      );
      ownerState = AuthenticatedState(
        user: ownerUser,
        currentStore: ownerStore,
        availableStores: [ownerStore],
        isFreshLogin: true,
      );
    });

    test(
      'State gating: employee vs owner and fresh login vs restored session',
      () {
        expect(employeeState.isEmployee, isTrue);
        expect(employeeState.isOwner, isFalse);
        expect(employeeState.isFreshLogin, isTrue);

        expect(ownerState.isOwner, isTrue);
        expect(ownerState.isEmployee, isFalse);

        final restoredEmployeeState = employeeState.copyWith(
          isFreshLogin: false,
        );
        expect(restoredEmployeeState.isEmployee, isTrue);
        expect(restoredEmployeeState.isFreshLogin, isFalse);
      },
    );

    testWidgets(
      'Full happy path: 4 steps resolve sequentially and invoke onCompleted',
      (tester) async {
        bool completedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: EmployeeBootstrapScreen(
              authState: employeeState,
              authRepository: fakeAuthRepo,
              posRepository: fakePosRepo,
              ordersRepository: fakeOrdersRepo,
              localCache: fakeCache,
              connectivityService: fakeConnectivity,
              onCompleted: () {
                completedCalled = true;
              },
            ),
          ),
        );

        // Verify header and 4 checklist items render
        expect(find.text('Setting things up'), findsOneWidget);
        expect(
          find.text('Just a moment while we get your store ready'),
          findsOneWidget,
        );
        expect(find.text('Finding your store'), findsOneWidget);
        expect(find.text('Loading store details'), findsOneWidget);
        expect(find.text('Loading products'), findsOneWidget);
        expect(find.text('Loading recent orders'), findsOneWidget);

        // Step 1: finishes after short frame delay
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Express Laundry Demo'), findsOneWidget);

        // Let steps 2, 3, 4 resolve
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));

        // Check repositories were called
        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1);
        expect(fakePosRepo.listProductsCallCount, 1);
        expect(fakeOrdersRepo.fetchRecentOrdersCallCount, 1);
        expect(fakeOrdersRepo.lastLimitPassed, 30);
        expect(fakeOrdersRepo.lastSortPassed, 'recent');

        // Check local cache was updated
        expect(fakeCache.getCachedStoreProfile(), isNotNull);
        expect(fakeCache.getCachedProducts()?.length, 1);
        expect(fakeCache.getCachedOrders()?.length, 1);

        // Verify onCompleted callback was invoked
        expect(completedCalled, isTrue);
      },
    );

    testWidgets(
      'Step failure: displays error state, Retry button, and retries only that step',
      (tester) async {
        fakePosRepo.listProductsShouldFail = true;
        bool completedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: EmployeeBootstrapScreen(
              authState: employeeState,
              authRepository: fakeAuthRepo,
              posRepository: fakePosRepo,
              ordersRepository: fakeOrdersRepo,
              localCache: fakeCache,
              connectivityService: fakeConnectivity,
              onCompleted: () {
                completedCalled = true;
              },
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Step 1 and Step 2 succeeded
        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1);
        expect(fakePosRepo.listProductsCallCount, 1);

        // Step 3 failed
        expect(find.text('Failed to load products'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Continue anyway'), findsOneWidget);
        expect(completedCalled, isFalse);

        // Fix product loading and tap Retry
        fakePosRepo.listProductsShouldFail = false;
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));

        // Verify only step 3 and subsequent step 4 were run
        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1); // Not restarted
        expect(fakePosRepo.listProductsCallCount, 2);
        expect(fakeOrdersRepo.fetchRecentOrdersCallCount, 1);
        expect(completedCalled, isTrue);
      },
    );

    testWidgets('Continue anyway button allows proceeding when error occurs', (
      tester,
    ) async {
      fakeOrdersRepo.fetchRecentOrdersShouldFail = true;
      bool completedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeBootstrapScreen(
            authState: employeeState,
            authRepository: fakeAuthRepo,
            posRepository: fakePosRepo,
            ordersRepository: fakeOrdersRepo,
            localCache: fakeCache,
            connectivityService: fakeConnectivity,
            onCompleted: () {
              completedCalled = true;
            },
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to load orders'), findsOneWidget);
      expect(find.text('Continue anyway'), findsOneWidget);
      expect(completedCalled, isFalse);

      await tester.tap(find.text('Continue anyway'));
      await tester.pump(const Duration(milliseconds: 450));

      expect(completedCalled, isTrue);
    });

    testWidgets(
      'Offline immediate detection: switches to lighter cached state when cache exists',
      (tester) async {
        fakeConnectivity.mockOffline = true;
        fakeCache._memory['cached_store_profile_json'] = {
          'store': 'Express Laundry Demo',
        };
        fakeCache._memory['cached_products_list'] = [
          {
            'id': 'p1',
            'name': 'Dry Clean',
            'price': 100,
            'type': 'item',
            'category': 'Laundry',
          },
        ];
        fakeCache._memory['cached_orders_list'] = [
          {
            'id': 'EL-99',
            'name': 'Jane',
            'phone': '9876543210',
            'date': '2026-09-10',
            'due': '2026-09-11',
            'status': 'Delivered',
            'lines': [],
            'payments': [],
          },
        ];

        bool completedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: EmployeeBootstrapScreen(
              authState: employeeState,
              authRepository: fakeAuthRepo,
              posRepository: fakePosRepo,
              ordersRepository: fakeOrdersRepo,
              localCache: fakeCache,
              connectivityService: fakeConnectivity,
              onCompleted: () {
                completedCalled = true;
              },
            ),
          ),
        );

        // Verify offline banner copy
        expect(
          find.text('Offline · getting store ready from cached data'),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));

        // No network calls made
        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 0);
        expect(fakePosRepo.listProductsCallCount, 0);
        expect(fakeOrdersRepo.fetchRecentOrdersCallCount, 0);

        // All resolved from cache
        expect(find.text('Using cached data'), findsNWidgets(3));
        expect(completedCalled, isTrue);
      },
    );
  });
}
