import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/services_screen.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';

class FakePosRepository extends PosRepository {
  List<Product> products = [];
  int listProductsCallCount = 0;
  bool shouldThrowOnList = false;

  FakePosRepository({required List<Product> initialProducts})
    : products = initialProducts,
      super(apiClient: ApiClient(), localCache: LocalCacheService());

  @override
  List<Product> getCachedProductsList() => [];

  @override
  Future<List<Product>> listProducts() async {
    listProductsCallCount++;
    if (shouldThrowOnList) throw Exception('Failed to load services');
    return products;
  }
}

class FakeOwnerRepository extends OwnerRepository {
  Product? lastCreatedProduct;
  Map<String, dynamic>? lastCreateProductParams;
  Map<String, dynamic>? lastUpdateProductParams;
  final List<String?> createdIds = [];
  bool failFirstCreate = false;

  FakeOwnerRepository() : super(apiClient: ApiClient());

  @override
  Future<Product> createProduct({
    String? id,
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    createdIds.add(id);
    if (failFirstCreate) {
      failFirstCreate = false;
      throw Exception('Network timeout');
    }
    lastCreateProductParams = {
      'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'price': price,
      'slabs': slabs,
      'active': active,
      'extra': extra,
    };
    final newProd = Product(
      id: id ?? 'prod-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: category,
      active: active ?? true,
      type: unit.toLowerCase() == 'weight' ? 'weight' : 'item',
      price: price,
      slabs: slabs
          .map(
            (s) => PricingSlab(
              limit: (s['limit'] as num).toDouble(),
              price: s['price'] as int,
            ),
          )
          .toList(),
      extra: extra ?? 0,
    );
    lastCreatedProduct = newProd;
    return newProd;
  }

  @override
  Future<Product> updateProduct({
    required String id,
    required String name,
    required String category,
    required String unit,
    required int price,
    List<Map<String, dynamic>> slabs = const [],
    bool? active,
    int? extra,
  }) async {
    lastUpdateProductParams = {
      'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'price': price,
      'slabs': slabs,
      'active': active,
      'extra': extra,
    };
    return Product(
      id: id,
      name: name,
      category: category,
      active: active ?? true,
      type: unit.toLowerCase() == 'weight' ? 'weight' : 'item',
      price: price,
      slabs: slabs
          .map(
            (s) => PricingSlab(
              limit: (s['limit'] as num).toDouble(),
              price: s['price'] as int,
            ),
          )
          .toList(),
      extra: extra ?? 0,
    );
  }
}

void main() {
  group('ServicesScreen Parity Tests', () {
    late FakePosRepository fakePosRepo;
    late FakeOwnerRepository fakeOwnerRepo;
    late List<Product> testProducts;

    setUp(() {
      testProducts = [
        Product(
          id: 'prod-item-1',
          name: 'Shirt Wash & Iron',
          category: 'wash',
          active: true,
          type: 'item',
          price: 5000,
        ),
        Product(
          id: 'prod-weight-1',
          name: 'Bed Sheets & Blankets',
          category: 'dry clean',
          active: true,
          type: 'weight',
          price: 20000,
          slabs: [
            PricingSlab(limit: 4, price: 20000),
            PricingSlab(limit: 6, price: 25000),
          ],
          extra: 4000,
        ),
        Product(
          id: 'prod-inactive-1',
          name: 'Curtain Dry Clean',
          category: 'dry clean',
          active: false,
          type: 'item',
          price: 15000,
        ),
      ];

      fakePosRepo = FakePosRepository(initialProducts: testProducts);
      fakeOwnerRepo = FakeOwnerRepository();
    });

    Widget buildTestWidget() {
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PosRepository>.value(value: fakePosRepo),
          RepositoryProvider<OwnerRepository>.value(value: fakeOwnerRepo),
        ],
        child: const MaterialApp(home: ServicesScreen()),
      );
    }

    testWidgets(
      'Renders service cards with Active/Inactive pills and full tier breakdowns',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Verify names render
        expect(find.text('Shirt Wash & Iron'), findsOneWidget);
        expect(find.text('Bed Sheets & Blankets'), findsOneWidget);
        expect(find.text('Curtain Dry Clean'), findsOneWidget);

        // Verify status pills
        expect(find.text('Active'), findsNWidgets(2));
        expect(find.text('Inactive'), findsOneWidget);
        expect(find.text('Per piece'), findsNWidgets(4));
        expect(find.text('Per kg'), findsOneWidget);

        // Verify "Edit pricing" action exists
        expect(find.text('Edit pricing'), findsNWidgets(3));

        // Verify weight tier breakdown on Bed Sheets & Blankets
        expect(find.text('Up to 4 kg'), findsOneWidget);
        expect(find.text('₹200'), findsOneWidget);
        expect(find.text('Up to 6 kg'), findsOneWidget);
        expect(find.text('₹250'), findsOneWidget);
        expect(find.text('Extra kg'), findsOneWidget);
        expect(find.text('₹40 / kg'), findsOneWidget);
      },
    );

    testWidgets(
      'Search filters service list case-insensitively by name and category',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Search by name "blanket"
        await tester.enterText(find.byType(TextField).first, 'blanket');
        await tester.pumpAndSettle();

        expect(find.text('Bed Sheets & Blankets'), findsOneWidget);
        expect(find.text('Shirt Wash & Iron'), findsNothing);
        expect(find.text('Curtain Dry Clean'), findsNothing);

        // Clear search
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.text('Shirt Wash & Iron'), findsOneWidget);
        expect(find.text('Bed Sheets & Blankets'), findsOneWidget);
        expect(find.text('Curtain Dry Clean'), findsOneWidget);

        // Search by category "dry clean"
        await tester.enterText(find.byType(TextField).first, 'dry clean');
        await tester.pumpAndSettle();

        expect(find.text('Bed Sheets & Blankets'), findsOneWidget);
        expect(find.text('Curtain Dry Clean'), findsOneWidget);
        expect(find.text('Shirt Wash & Iron'), findsNothing);
      },
    );

    testWidgets(
      'Edit pricing sheet opens pre-filled and saves updated active status and tiers',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Tap "Edit pricing" on Bed Sheets & Blankets
        await tester.tap(find.text('Edit pricing').at(1));
        await tester.pumpAndSettle();

        // Screen header
        expect(find.text('Edit pricing'), findsOneWidget);
        expect(find.text('Bed Sheets & Blankets'), findsOneWidget);
        expect(find.text('PRICING TIERS'), findsOneWidget);

        // Tiers pre-filled: 4 -> 200, 6 -> 250
        expect(find.text('4'), findsOneWidget);
        expect(find.text('200'), findsOneWidget);
        expect(find.text('6'), findsOneWidget);
        expect(find.text('250'), findsOneWidget);

        // Toggle Active switch to Inactive
        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // Tap "Save changes"
        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        // Verify updateProduct was called with active: false and slabs preserved
        expect(fakeOwnerRepo.lastUpdateProductParams, isNotNull);
        expect(fakeOwnerRepo.lastUpdateProductParams!['id'], 'prod-weight-1');
        expect(fakeOwnerRepo.lastUpdateProductParams!['active'], isFalse);
        expect(fakeOwnerRepo.lastUpdateProductParams!['slabs'], isNotEmpty);
        final slabs = fakeOwnerRepo.lastUpdateProductParams!['slabs'] as List;
        expect(slabs.length, 2);
        expect(slabs[0]['limit'], 4.0);
        expect(slabs[0]['price'], 20000);
        expect(slabs[1]['limit'], 6.0);
        expect(slabs[1]['price'], 25000);
        // Pre-filled extra rate (₹40/kg = 4000 paise) must round-trip on save,
        // not be silently dropped.
        expect(fakeOwnerRepo.lastUpdateProductParams!['extra'], 4000);
      },
    );

    testWidgets(
      'Add service sheet allows creating a weight-based service with multiple tiers',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Tap "+" add button in AppBar
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('Add service'), findsOneWidget);

        // Enter service name
        final nameField = find.widgetWithText(AppTextField, 'SERVICE NAME');
        await tester.enterText(nameField, 'Quilts & Blankets');
        await tester.pumpAndSettle();

        // Change unit type from 'Per piece' to 'Per kg'
        await tester.tap(find.text('Per piece').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Per kg').last);
        await tester.pumpAndSettle();

        // Pricing tiers should now be visible
        expect(find.text('PRICING TIERS'), findsOneWidget);
        expect(find.text('Add tier'), findsOneWidget);

        // Fill in tier 1 (limit 5, price 300)
        final textFields = find.byType(TextField);
        // textFields on full screen: 0: name, 1: tier1 limit, 2: tier1 price, 3: extra rate
        await tester.enterText(textFields.at(1), '5');
        await tester.enterText(textFields.at(2), '300');
        await tester.pumpAndSettle();

        // Tap "Add tier" to add tier 2
        await tester.ensureVisible(find.text('Add tier'));
        await tester.tap(find.text('Add tier'));
        await tester.pumpAndSettle();

        final updatedTextFields = find.byType(TextField);
        // tier 2 limit, tier 2 price
        await tester.enterText(updatedTextFields.at(3), '10');
        await tester.enterText(updatedTextFields.at(4), '550');
        await tester.pumpAndSettle();

        // Tap "Create service"
        await tester.ensureVisible(find.text('Create service'));
        await tester.tap(find.text('Create service'));
        await tester.pumpAndSettle();

        // Verify createProduct was called with built slabs
        expect(fakeOwnerRepo.lastCreateProductParams, isNotNull);
        expect(
          fakeOwnerRepo.lastCreateProductParams!['name'],
          'Quilts & Blankets',
        );
        expect(fakeOwnerRepo.lastCreateProductParams!['unit'], 'WEIGHT');
        expect(fakeOwnerRepo.lastCreateProductParams!['active'], isTrue);
        final slabs = fakeOwnerRepo.lastCreateProductParams!['slabs'] as List;
        expect(slabs.length, 2);
        expect(slabs[0]['limit'], 5.0);
        expect(slabs[0]['price'], 30000);
        expect(slabs[1]['limit'], 10.0);
        expect(slabs[1]['price'], 55000);
      },
    );

    testWidgets(
      'Edit pricing sheet opens successfully for products with non-standard categories (e.g. Laundry)',
      (tester) async {
        final laundryProduct = Product(
          id: 'prod-laundry-1',
          name: 'Express Wash & Fold',
          category: 'Laundry',
          active: true,
          type: 'item',
          price: 9900,
        );
        fakePosRepo = FakePosRepository(initialProducts: [laundryProduct]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Express Wash & Fold'), findsOneWidget);

        // Tap "Edit pricing" - should NOT throw Flutter DropdownButton assertion error
        await tester.tap(find.text('Edit pricing'));
        await tester.pumpAndSettle();

        expect(find.text('Edit pricing'), findsWidgets);
        expect(find.text('LAUNDRY'), findsWidgets);
      },
    );

    testWidgets(
      'Card handles long category names on compact width without RenderFlex overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final longCatProduct = Product(
          id: 'prod-long-1',
          name: 'Designer Silk Gown',
          category: 'Premium Dry Clean & Pressing',
          active: false,
          type: 'item',
          price: 45000,
        );
        fakePosRepo = FakePosRepository(initialProducts: [longCatProduct]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Designer Silk Gown'), findsOneWidget);
        expect(find.text('Inactive'), findsOneWidget);
        expect(find.text('PREMIUM DRY CLEAN & PRESSING'), findsOneWidget);
      },
    );

    testWidgets(
      'Sheet handles keyboard insets responsively without off-screen clipping or overflow',
      (tester) async {
        // Set standard mobile screen size
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetViewInsets());

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Open Add service sheet
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('Add service'), findsOneWidget);

        // Simulate soft keyboard opening (viewInsets.bottom = 336)
        tester.view.viewInsets = const FakeViewPadding(bottom: 336);
        await tester.pumpAndSettle();

        // "Add service" title, name field, and buttons must still exist and be renderable
        expect(find.text('Add service'), findsOneWidget);
        expect(find.text('SERVICE NAME'), findsOneWidget);
        expect(find.text('Create service'), findsOneWidget);
      },
    );

    testWidgets(
      'Sheet scrolls properly and auto-scrolls when adding multiple tiers',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Tap Edit pricing on weight product
        await tester.tap(find.text('Edit pricing').at(1));
        await tester.pumpAndSettle();

        expect(find.text('PRICING TIERS'), findsOneWidget);

        // Add two more tiers
        await tester.tap(find.text('Add tier'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add tier'));
        await tester.pumpAndSettle();

        // Scroll down
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();

        // Scroll up
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, 250),
        );
        await tester.pumpAndSettle();

        // App bar back button remains visible
        expect(find.text('Edit pricing'), findsWidgets);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      },
    );

    testWidgets('Toggling grid/list view switches between ListView and GridView', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // By default list view is active (ListView is present, GridView is not)
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);

      // Tap grid icon
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      // Now GridView is present, ListView is not
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);

      // Tap list icon
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      // Back to ListView
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets(
      'Shows error SnackBar when listProducts throws',
      (tester) async {
        fakePosRepo.shouldThrowOnList = true;

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('Could not load services — try again'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Tapping Create service a second time after a failed create sends the SAME client id',
      (tester) async {
        fakeOwnerRepo.failFirstCreate = true;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        final nameField = find.widgetWithText(AppTextField, 'SERVICE NAME');
        await tester.enterText(nameField, 'Curtain Wash');
        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(1), '250');
        await tester.pumpAndSettle();

        // First attempt fails
        await tester.ensureVisible(find.text('Create service'));
        await tester.tap(find.text('Create service'));
        await tester.pumpAndSettle();

        // Second attempt succeeds
        await tester.tap(find.text('Create service'));
        await tester.pumpAndSettle();

        expect(fakeOwnerRepo.createdIds.length, 2);
        expect(fakeOwnerRepo.createdIds[0], isNotNull);
        expect(fakeOwnerRepo.createdIds[0], isNotEmpty);
        expect(fakeOwnerRepo.createdIds[1], equals(fakeOwnerRepo.createdIds[0]));
      },
    );
  });
}
