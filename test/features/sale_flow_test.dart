import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

class MockPosRepository implements PosRepository {
  List<Product> cachedProducts = [];
  List<Product> networkProducts = [];
  bool shouldThrowOnNetwork = false;
  int listProductsCallCount = 0;
  int getCachedCallCount = 0;

  @override
  List<Product> getCachedProductsList() {
    getCachedCallCount++;
    return cachedProducts;
  }

  @override
  Future<List<Product>> listProducts() async {
    listProductsCallCount++;
    if (shouldThrowOnNetwork) {
      throw Exception('Network failed');
    }
    return networkProducts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Sale Flow & CartBloc Tests', () {
    late CartBloc cartBloc;
    late MockPosRepository mockRepo;

    final pieceProduct = Product(
      id: 'prod-1',
      name: 'Men Shirt',
      category: 'iron',
      type: 'item',
      price: 50,
      active: true,
    );

    final weightProduct = Product(
      id: 'prod-2',
      name: 'Wash & Fold',
      category: 'wash',
      type: 'weight',
      slabs: [
        PricingSlab(limit: 2.0, price: 150),
        PricingSlab(limit: 5.0, price: 300),
      ],
      extra: 50,
      active: true,
    );

    setUp(() {
      mockRepo = MockPosRepository();
      cartBloc = CartBloc(posRepository: mockRepo);
    });

    tearDown(() {
      cartBloc.close();
    });

    test('Initial cart state is empty and has a unique idempotencyKey', () {
      expect(cartBloc.state.items, isEmpty);
      expect(cartBloc.state.totalAmount, equals(0));
      expect(cartBloc.state.idempotencyKey, isNotEmpty);
    });

    test('Adding piece-based item computes exact amount', () async {
      cartBloc.add(AddItemToCartEvent(product: pieceProduct, quantity: 3));
      await expectLater(
        cartBloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.items.length == 1 &&
                state.items['prod-1']!.quantity == 3.0 &&
                state.items['prod-1']!.computedAmount == 150 &&
                state.totalAmount == 150;
          }),
        ),
      );
    });

    test(
      'Adding weight-based item with decimal kg computes price correctly',
      () async {
        cartBloc.add(AddItemToCartEvent(product: weightProduct, quantity: 2.5));
        await expectLater(
          cartBloc.stream,
          emits(
            predicate<dynamic>((state) {
              return state.items.length == 1 &&
                  state.items['prod-2']!.quantity == 2.5 &&
                  state.items['prod-2']!.computedAmount ==
                      300 && // 2.5 <= 5.0 slab -> 300
                  state.totalAmount == 300;
            }),
          ),
        );
      },
    );

    test(
      'Combining piece and weight items sums totalAmount correctly',
      () async {
        cartBloc.add(
          AddItemToCartEvent(product: pieceProduct, quantity: 2),
        ); // 2 * 50 = 100
        cartBloc.add(
          AddItemToCartEvent(product: weightProduct, quantity: 2.5),
        ); // 300

        await expectLater(
          cartBloc.stream.skip(1),
          emits(
            predicate<dynamic>((state) {
              return state.items.length == 2 && state.totalAmount == 400;
            }),
          ),
        );
      },
    );

    test('Updating item quantity to 0 removes item', () async {
      cartBloc.add(AddItemToCartEvent(product: pieceProduct, quantity: 2));
      cartBloc.add(UpdateItemQuantityEvent(productId: 'prod-1', quantity: 0));

      await expectLater(
        cartBloc.stream.skip(1),
        emits(
          predicate<dynamic>((state) {
            return state.items.isEmpty && state.totalAmount == 0;
          }),
        ),
      );
    });

    test('ClearCartEvent resets items to empty', () async {
      cartBloc.add(AddItemToCartEvent(product: pieceProduct, quantity: 4));
      cartBloc.add(ClearCartEvent());

      await expectLater(
        cartBloc.stream.skip(1),
        emits(
          predicate<dynamic>((state) {
            return state.items.isEmpty && state.totalAmount == 0;
          }),
        ),
      );
    });

    test('SetCustomerDetailsEvent correctly updates customer phone, name and notes', () async {
      final dueDate = DateTime(2026, 9, 15);
      cartBloc.add(
        SetCustomerDetailsEvent(
          phone: '9876543210',
          customerName: 'Reddy Gona',
          dueDate: dueDate,
          notes: 'Handle with care',
        ),
      );

      await expectLater(
        cartBloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.customerPhone == '9876543210' &&
                state.customerName == 'Reddy Gona' &&
                state.dueDate == dueDate &&
                state.notes == 'Handle with care';
          }),
        ),
      );
    });

    test('LoadCatalogEvent reads cache only and does not touch network when cache is populated', () async {
      mockRepo.cachedProducts = [pieceProduct];
      cartBloc.add(LoadCatalogEvent());

      await expectLater(
        cartBloc.stream,
        emits(
          predicate<dynamic>((state) {
            return state.allProducts.length == 1 &&
                state.allProducts.first.id == 'prod-1' &&
                !state.isLoading;
          }),
        ),
      );
      expect(mockRepo.getCachedCallCount, equals(1));
      expect(mockRepo.listProductsCallCount, equals(0));
    });

    test('LoadCatalogEvent falls back to network only when cache is completely empty', () async {
      mockRepo.cachedProducts = [];
      mockRepo.networkProducts = [weightProduct];
      cartBloc.add(LoadCatalogEvent());

      await expectLater(
        cartBloc.stream.skip(1), // skip isLoading: true
        emits(
          predicate<dynamic>((state) {
            return state.allProducts.length == 1 &&
                state.allProducts.first.id == 'prod-2' &&
                !state.isLoading;
          }),
        ),
      );
      expect(mockRepo.getCachedCallCount, equals(1));
      expect(mockRepo.listProductsCallCount, equals(1));
    });

    test(
      'RefreshCatalogEvent fetches from network and updates allProducts',
      () async {
        mockRepo.networkProducts = [pieceProduct, weightProduct];
        cartBloc.add(RefreshCatalogEvent());

        await expectLater(
          cartBloc.stream.skip(1), // skip isLoading: true
          emits(
            predicate<dynamic>((state) {
              return state.allProducts.length == 2 && !state.isLoading;
            }),
          ),
        );
        expect(mockRepo.listProductsCallCount, equals(1));
      },
    );

    test(
      'RefreshCatalogEvent catch block emits isLoading: false on error',
      () async {
        mockRepo.shouldThrowOnNetwork = true;
        cartBloc.add(RefreshCatalogEvent());

        await expectLater(
          cartBloc.stream.skip(1), // skip isLoading: true
          emits(
            predicate<dynamic>((state) {
              // The bloc shows a friendly message, not the raw exception.
              return !state.isLoading &&
                  state.error == 'Could not refresh products — try again';
            }),
          ),
        );
      },
    );

    test('Adding 3-decimal weighted item (2.755 kg) computes price and display correctly', () async {
      cartBloc.add(AddItemToCartEvent(product: weightProduct, quantity: 2.755));
      await expectLater(
        cartBloc.stream,
        emits(
          predicate<dynamic>((state) {
            final item = state.items['prod-2']!;
            return item.quantity == 2.755 &&
                item.displayQuantity == '2.755 kg' &&
                item.computedAmount == 300 && // 2.755 <= 5.0 slab -> 300
                state.totalAmount == 300;
          }),
        ),
      );
    });
  });

  group('Offline Slab Pricing Tests (PosRepository.createOrderOptimistic)', () {
    test('Offline created weighted order lines use Product.computePrice across slab boundaries', () async {
      final fakeCache = _FakeLocalCacheService();
      fakeCache.cachedProducts = [
        {
          'id': 'wf-1',
          'name': 'Wash & Fold',
          'category': 'wash',
          'type': 'weight',
          'slabs': [
            {'limit': 2.0, 'price': 150},
            {'limit': 5.0, 'price': 300},
          ],
          'extra': 50,
        },
      ];

      final repo = PosRepository(localCache: fakeCache);

      // Boundary 1: 5.0 kg exactly matches the 5.0 kg slab (₹300)
      final orderAtLimit = await repo.createOrderOptimistic(
        idempotencyKey: 'idemp-1',
        phone: '9876543210',
        dueDate: '2026-09-15',
        entries: [
          {'productId': 'wf-1', 'quantity': 5.0},
        ],
      );
      expect(orderAtLimit.lines.first.amount, equals(300));
      expect(orderAtLimit.lines.first.displayQuantity, equals('5 kg'));

      // Boundary 2: 2.755 kg with 3 decimals falls in the 2.0-5.0 kg slab (₹300)
      final orderDecimal = await repo.createOrderOptimistic(
        idempotencyKey: 'idemp-2',
        phone: '9876543210',
        dueDate: '2026-09-15',
        entries: [
          {'productId': 'wf-1', 'quantity': 2.755},
        ],
      );
      expect(orderDecimal.lines.first.amount, equals(300));
      expect(orderDecimal.lines.first.displayQuantity, equals('2.755 kg'));

      // Boundary 3: 7.0 kg crosses above slab limit (300 + 2*50 = ₹400)
      final orderAboveSlab = await repo.createOrderOptimistic(
        idempotencyKey: 'idemp-3',
        phone: '9876543210',
        dueDate: '2026-09-15',
        entries: [
          {'productId': 'wf-1', 'quantity': 7.0},
        ],
      );
      expect(orderAboveSlab.lines.first.amount, equals(400));
      expect(orderAboveSlab.lines.first.displayQuantity, equals('7 kg'));
    });
  });
}

class _FakeLocalCacheService implements LocalCacheService {
  List<Map<String, dynamic>>? cachedProducts;
  List<Map<String, dynamic>>? cachedOrders = [];
  final List<Map<String, dynamic>> syncQueue = [];

  @override
  List<Map<String, dynamic>>? getCachedProducts() => cachedProducts;

  @override
  List<Map<String, dynamic>>? getCachedOrders() => cachedOrders;

  @override
  Future<void> setCachedOrders(List<Map<String, dynamic>> orders) async {
    cachedOrders = orders;
  }

  @override
  Future<void> enqueueSyncAction(Map<String, dynamic> action) async {
    syncQueue.add(action);
  }

  @override
  List<Map<String, dynamic>> getPendingSyncQueue() => syncQueue;

  @override
  String? getActiveStoreId() => 'store_1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
