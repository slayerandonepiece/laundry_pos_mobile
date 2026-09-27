import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/auth/presentation/bootstrap_screen.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/expense_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
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
  String? getActiveOutletId() => _memory['active_outlet_id'] as String?;

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() =>
      _memory['allowed_outlets'] as List<Map<String, dynamic>>?;

  @override
  List<Map<String, dynamic>>? getCachedPaymentMethods() =>
      _memory['cached_payment_methods_list'] as List<Map<String, dynamic>>?;
  @override
  Future<void> setCachedPaymentMethods(List<Map<String, dynamic>> m) async =>
      _memory['cached_payment_methods_list'] = m;

  @override
  Map<String, dynamic>? getCachedDashboardMetrics() =>
      _memory['cached_dashboard_metrics_json'] as Map<String, dynamic>?;
  @override
  List<Map<String, dynamic>>? getCachedExpenses() =>
      _memory['cached_expenses_list'] as List<Map<String, dynamic>>?;
  @override
  List<Map<String, dynamic>>? getCachedStaff() =>
      _memory['cached_staff_list'] as List<Map<String, dynamic>>?;

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
  int refreshOutletContextCallCount = 0;
  final FakeLocalCache localCache;

  FakeAuthRepository({required this.localCache})
    : super(
        apiClient: ApiClient(),
        secureStorage: FakeSecureStorage(),
        localCache: localCache,
      );

  @override
  Future<List<Map<String, dynamic>>?> refreshOutletContext() async {
    refreshOutletContextCallCount++;
    return [
      {'id': 'o1', 'displayName': 'Main Road'},
    ];
  }

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
  int listPaymentMethodsCallCount = 0;
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

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    listPaymentMethodsCallCount++;
    await localCache.setCachedPaymentMethods([
      {'id': 'pm1', 'code': 'CASH', 'name': 'Cash', 'enabled': true},
    ]);
    return [];
  }
}

class FakeOrdersRepository extends OrdersRepository {
  bool syncAllOrdersShouldFail = false;
  int syncAllOrdersCallCount = 0;
  final FakeLocalCache localCache;

  FakeOrdersRepository({required this.localCache})
    : super(apiClient: ApiClient(), localCache: localCache);

  @override
  Future<void> syncAllOrders() async {
    syncAllOrdersCallCount++;
    if (syncAllOrdersShouldFail) {
      throw Exception('Network error syncing orders');
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
  }
}

class FakeOwnerRepository extends OwnerRepository {
  bool getDashboardMetricsShouldFail = false;
  int getDashboardMetricsCallCount = 0;
  bool listExpensesShouldFail = false;
  int listExpensesCallCount = 0;
  int listStaffCallCount = 0;

  FakeOwnerRepository() : super(apiClient: ApiClient());

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
  }) async {
    getDashboardMetricsCallCount++;
    if (getDashboardMetricsShouldFail) {
      throw Exception('Network error loading dashboard metrics');
    }
    return DashboardMetrics();
  }

  @override
  Future<List<Expense>> listExpenses() async {
    listExpensesCallCount++;
    if (listExpensesShouldFail) {
      throw Exception('Network error loading expenses');
    }
    return [];
  }

  @override
  Future<List<StaffMember>> listStaff() async {
    listStaffCallCount++;
    return [];
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
  group('BootstrapScreen Tests', () {
    late FakeLocalCache fakeCache;
    late FakeAuthRepository fakeAuthRepo;
    late FakePosRepository fakePosRepo;
    late FakeOrdersRepository fakeOrdersRepo;
    late FakeOwnerRepository fakeOwnerRepo;
    late FakeConnectivityService fakeConnectivity;
    late AuthenticatedState employeeState;
    late AuthenticatedState ownerState;

    setUp(() {
      fakeCache = FakeLocalCache();
      fakeAuthRepo = FakeAuthRepository(localCache: fakeCache);
      fakePosRepo = FakePosRepository(localCache: fakeCache);
      fakeOrdersRepo = FakeOrdersRepository(localCache: fakeCache);
      fakeOwnerRepo = FakeOwnerRepository();
      fakeConnectivity = FakeConnectivityService();

      final employeeUser = User(
        id: 'u-emp',
        name: 'Staff John',
        phone: 'john',
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
        phone: 'alice',
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

    Widget screen(AuthenticatedState state, VoidCallback onCompleted) =>
        MaterialApp(
          home: BootstrapScreen(
            authState: state,
            authRepository: fakeAuthRepo,
            posRepository: fakePosRepo,
            ordersRepository: fakeOrdersRepo,
            ownerRepository: fakeOwnerRepo,
            localCache: fakeCache,
            connectivityService: fakeConnectivity,
            onCompleted: onCompleted,
          ),
        );

    testWidgets(
      'Employee: outlet, then organization, services & prices, payment methods, orders',
      (tester) async {
        fakeCache._memory['active_outlet_id'] = 'o1';
        fakeCache._memory['allowed_outlets'] = [
          {'id': 'o1', 'displayName': 'Main Road'},
          {'id': 'o2', 'displayName': 'Lake View'},
        ];
        bool completedCalled = false;

        await tester.pumpWidget(
          screen(employeeState, () => completedCalled = true),
        );

        expect(find.text('Setting things up'), findsOneWidget);
        expect(
          find.text('Just a moment while we sync your data'),
          findsOneWidget,
        );
        expect(find.text('Opening your outlet'), findsOneWidget);
        expect(find.text('Syncing organization details'), findsOneWidget);
        expect(find.text('Syncing services & prices'), findsOneWidget);
        expect(find.text('Syncing payment methods'), findsOneWidget);
        expect(find.text('Syncing orders'), findsOneWidget);
        expect(find.text('Fetching organization & outlets'), findsNothing);
        expect(find.text('Syncing dashboard'), findsNothing);
        expect(find.text('Syncing staff'), findsNothing);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Main Road'), findsOneWidget);
        expect(fakeAuthRepo.refreshOutletContextCallCount, 0);
        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1);
        expect(fakePosRepo.listProductsCallCount, 1);
        expect(fakePosRepo.listPaymentMethodsCallCount, 1);
        expect(fakeOrdersRepo.syncAllOrdersCallCount, 1);
        expect(fakeOwnerRepo.getDashboardMetricsCallCount, 0);
        expect(fakeOwnerRepo.listExpensesCallCount, 0);
        expect(fakeOwnerRepo.listStaffCallCount, 0);

        expect(fakeCache.getCachedStoreProfile(), isNotNull);
        expect(fakeCache.getCachedProducts()?.length, 1);
        expect(fakeCache.getCachedOrders()?.length, 1);
        expect(completedCalled, isTrue);
      },
    );

    testWidgets('Owner: all 8 steps run in order and invoke onCompleted', (
      tester,
    ) async {
      bool completedCalled = false;

      await tester.pumpWidget(screen(ownerState, () => completedCalled = true));

      for (final title in [
        'Fetching organization & outlets',
        'Syncing organization details',
        'Syncing services & prices',
        'Syncing payment methods',
        'Syncing orders',
        'Syncing dashboard',
        'Syncing expenses',
        'Syncing staff',
      ]) {
        expect(find.text(title), findsOneWidget);
      }

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Express Laundry Demo'), findsOneWidget);
      expect(fakeAuthRepo.refreshOutletContextCallCount, 1);
      expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1);
      expect(fakePosRepo.listProductsCallCount, 1);
      expect(fakePosRepo.listPaymentMethodsCallCount, 1);
      expect(fakeOrdersRepo.syncAllOrdersCallCount, 1);
      expect(fakeOwnerRepo.getDashboardMetricsCallCount, 1);
      expect(fakeOwnerRepo.listExpensesCallCount, 1);
      expect(fakeOwnerRepo.listStaffCallCount, 1);
      expect(completedCalled, isTrue);
    });

    testWidgets('Owner step failure: error, Retry resumes from that step', (
      tester,
    ) async {
      fakeOwnerRepo.getDashboardMetricsShouldFail = true;
      bool completedCalled = false;

      await tester.pumpWidget(screen(ownerState, () => completedCalled = true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fakeOwnerRepo.getDashboardMetricsCallCount, 1);
      expect(fakeOwnerRepo.listExpensesCallCount, 0);
      expect(find.text("Couldn't sync dashboard"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(completedCalled, isFalse);

      fakeOwnerRepo.getDashboardMetricsShouldFail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fakeOrdersRepo.syncAllOrdersCallCount, 1); // Not restarted
      expect(fakeOwnerRepo.getDashboardMetricsCallCount, 2);
      expect(fakeOwnerRepo.listExpensesCallCount, 1);
      expect(fakeOwnerRepo.listStaffCallCount, 1);
      expect(completedCalled, isTrue);
    });

    testWidgets('Step failure: retries only that step and the ones after it', (
      tester,
    ) async {
      fakePosRepo.listProductsShouldFail = true;
      bool completedCalled = false;

      await tester.pumpWidget(
        screen(employeeState, () => completedCalled = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1);
      expect(fakePosRepo.listProductsCallCount, 1);
      expect(find.text("Couldn't sync services & prices"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Continue anyway'), findsOneWidget);
      expect(completedCalled, isFalse);

      fakePosRepo.listProductsShouldFail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fakeAuthRepo.fetchStoreDetailsCallCount, 1); // Not restarted
      expect(fakePosRepo.listProductsCallCount, 2);
      expect(fakeOrdersRepo.syncAllOrdersCallCount, 1);
      expect(completedCalled, isTrue);
    });

    testWidgets('Continue anyway proceeds and marks the scope as set up', (
      tester,
    ) async {
      fakeOrdersRepo.syncAllOrdersShouldFail = true;
      bool completedCalled = false;

      await tester.pumpWidget(
        screen(employeeState, () => completedCalled = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text("Couldn't sync orders"), findsOneWidget);
      expect(find.text('Continue anyway'), findsOneWidget);
      expect(completedCalled, isFalse);
      expect(fakeCache.getCachedOrders(), isNull);

      await tester.tap(find.text('Continue anyway'));
      await tester.pump(const Duration(milliseconds: 450));

      expect(fakeCache.getCachedOrders(), isEmpty);
      expect(completedCalled, isTrue);
    });

    testWidgets(
      'Offline with data on the phone: no network calls, cached rows',
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
        fakeCache._memory['cached_payment_methods_list'] =
            <Map<String, dynamic>>[];
        fakeCache._memory['cached_orders_list'] = <Map<String, dynamic>>[];

        bool completedCalled = false;

        await tester.pumpWidget(
          screen(employeeState, () => completedCalled = true),
        );

        expect(
          find.text('Offline · using data already on this phone'),
          findsOneWidget,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(fakeAuthRepo.fetchStoreDetailsCallCount, 0);
        expect(fakePosRepo.listProductsCallCount, 0);
        expect(fakePosRepo.listPaymentMethodsCallCount, 0);
        expect(fakeOrdersRepo.syncAllOrdersCallCount, 0);

        expect(find.text('Using cached data'), findsNWidgets(4));
        expect(completedCalled, isTrue);
      },
    );
  });
}
