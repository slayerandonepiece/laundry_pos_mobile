import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool offline;
  _FakeConnectivityService({this.offline = false}) : super.internal();

  @override
  bool get isOffline => offline;

  @override
  Future<bool> checkIsOffline() async => offline;
}

class _FakePosApiClient implements ApiClient {
  final List<String> getUrls = [];
  dynamic nextResponse;
  bool shouldThrow = false;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
    if (shouldThrow) throw Exception('Network error');
    return nextResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosLocalCache implements LocalCacheService {
  List<Map<String, dynamic>>? cachedPaymentMethods;

  @override
  List<Map<String, dynamic>>? getCachedPaymentMethods() => cachedPaymentMethods;

  @override
  Future<void> setCachedPaymentMethods(
    List<Map<String, dynamic>> methods,
  ) async {
    cachedPaymentMethods = methods;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  List<Product> products = [];
  List<StorePaymentMethod> paymentMethods = [];
  bool throwOnPaymentMethods = false;
  String? lastPassedOutletId;
  String? lastPassedPaymentMethodName;

  @override
  List<Product> getCachedProductsList() => products;

  @override
  Future<List<Product>> listProducts() async => products;

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async {
    if (throwOnPaymentMethods) {
      throw Exception('Failed to load payment methods');
    }
    return paymentMethods;
  }

  @override
  Future<Order> createOrderOptimistic({
    required String idempotencyKey,
    required String phone,
    String customerName = '',
    required String dueDate,
    String notes = '',
    required List<Map<String, dynamic>> entries,
    Map<String, dynamic>? initialPayment,
    String? outletId,
  }) async {
    lastPassedOutletId = outletId;
    lastPassedPaymentMethodName = initialPayment?['method']?.toString();
    return Order(
      id: 'LOCAL-TEST',
      name: customerName,
      phone: phone,
      date: DateTime.now().toIso8601String(),
      due: dueDate,
      status: 'Pending',
      lines: [],
      payments: [],
      outletId: outletId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CartBloc outlet pinning & payment methods wiring', () {
    late CartBloc bloc;
    late _FakePosRepo fakeRepo;

    final testProduct = Product(
      id: 'prod_1',
      name: 'Shirt Wash',
      category: 'wash',
      type: 'item',
      price: 50,
      active: true,
    );

    setUp(() {
      fakeRepo = _FakePosRepo();
      fakeRepo.products = [testProduct];
      fakeRepo.paymentMethods = [
        StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
        StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
      ];
      bloc = CartBloc(posRepository: fakeRepo);
    });

    tearDown(() {
      bloc.close();
    });

    test('ResetSaleEvent pins outletId to CartState', () {
      expect(bloc.state.outletId, isNull);

      bloc.add(ResetSaleEvent(outletId: 'outlet_blr_01'));
      expectLater(
        bloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.outletId == 'outlet_blr_01';
          }),
        ),
      );
    });

    test('ResetSaleEvent with null outletId clears existing outletId (not preserved)', () async {
      bloc.add(ResetSaleEvent(outletId: 'outlet_blr_01'));
      await bloc.stream.firstWhere((s) => s.outletId == 'outlet_blr_01');

      // Now reset with null
      bloc.add(ResetSaleEvent());
      await expectLater(
        bloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.outletId == null;
          }),
        ),
      );
    });

    test('SubmitOrderEvent forwards state.outletId to createOrderOptimistic', () async {
      bloc.add(ResetSaleEvent(outletId: 'outlet_mth_02'));
      await bloc.stream.firstWhere((s) => s.outletId == 'outlet_mth_02');

      bloc.add(AddItemToCartEvent(product: testProduct, quantity: 2));
      await bloc.stream.firstWhere((s) => s.items.isNotEmpty);

      bloc.add(
        SubmitOrderEvent(
          paymentChoice: 'prepaid',
          paymentMethodName: 'UPI',
        ),
      );

      await bloc.stream.firstWhere((s) => s.placedOrder != null);
      expect(fakeRepo.lastPassedOutletId, equals('outlet_mth_02'));
      expect(fakeRepo.lastPassedPaymentMethodName, equals('UPI'));
      expect(bloc.state.placedOrder?.outletId, equals('outlet_mth_02'));
    });

    test('LoadCatalogEvent populates paymentMethods on CartState', () async {
      bloc.add(LoadCatalogEvent());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<dynamic>((state) {
            return state.paymentMethods.length == 2 &&
                state.paymentMethods.first.name == 'Cash' &&
                state.paymentMethods.last.name == 'UPI';
          }),
        ),
      );
    });

    test('LoadCatalogEvent payment methods error defaults to empty list and does not fail catalog', () async {
      fakeRepo.throwOnPaymentMethods = true;
      bloc.add(LoadCatalogEvent());
      await expectLater(
        bloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.paymentMethods.isEmpty &&
                state.allProducts.length == 1 &&
                state.error == null;
          }),
        ),
      );
    });

    test('RefreshCatalogEvent populates paymentMethods on CartState', () async {
      fakeRepo.products = [testProduct];
      bloc.add(RefreshCatalogEvent());
      await expectLater(
        bloc.stream.skip(1), // skip isLoading: true
        emits(
          predicate<dynamic>((state) {
            return state.paymentMethods.length == 2 &&
                !state.isLoading &&
                state.allProducts.isNotEmpty;
          }),
        ),
      );
    });
  });

  group('PosRepository.listPaymentMethods tests', () {
    late _FakeConnectivityService fakeConnectivity;
    late _FakePosApiClient fakeApiClient;
    late _FakePosLocalCache fakeLocalCache;
    late PosRepository posRepo;

    setUp(() {
      fakeConnectivity = _FakeConnectivityService(offline: false);
      ConnectivityService.instance = fakeConnectivity;
      fakeApiClient = _FakePosApiClient();
      fakeLocalCache = _FakePosLocalCache();
      posRepo = PosRepository(
        apiClient: fakeApiClient,
        localCache: fakeLocalCache,
      );
    });

    tearDown(() {
      ConnectivityService.instance = ConnectivityService.internal();
    });

    test('GETs paymentMethodsAll (?all=true), caches full list, and returns only active methods', () async {
      fakeApiClient.nextResponse = [
        {'id': 'pm_1', 'code': 'cash', 'name': 'Cash', 'enabled': true},
        {'id': 'pm_2', 'code': 'upi', 'name': 'Upi', 'enabled': false},
      ];

      final result = await posRepo.listPaymentMethods();

      expect(fakeApiClient.getUrls, equals([ApiEndpoints.paymentMethodsAll]));
      expect(fakeApiClient.getUrls.single.endsWith('?all=true'), isTrue);

      // Full list (including disabled) is cached so owner & pos share the same cache shape
      expect(fakeLocalCache.cachedPaymentMethods, isNotNull);
      expect(fakeLocalCache.cachedPaymentMethods!.length, 2);

      // Only active methods are returned
      expect(result.length, 1);
      expect(result.single.name, 'Cash');
      expect(result.single.active, isTrue);
    });

    test('returns only active methods from offline cache when cache holds a disabled one', () async {
      fakeConnectivity.offline = true;
      fakeLocalCache.cachedPaymentMethods = [
        {'id': 'pm_1', 'name': 'Cash', 'type': 'Cash', 'active': true},
        {'id': 'pm_2', 'name': 'Card', 'type': 'Other', 'active': false},
      ];

      final result = await posRepo.listPaymentMethods();

      expect(fakeApiClient.getUrls, isEmpty);
      expect(result.length, 1);
      expect(result.single.id, 'pm_1');
      expect(result.single.name, 'Cash');
    });
  });
}
