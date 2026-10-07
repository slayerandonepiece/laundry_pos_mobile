import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/bloc/cart_event.dart';
import 'package:myshop/features/pos/bloc/cart_state.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/pos/presentation/checkout_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/features/shell/data/models/outlet_model.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class _FakePosRepo implements PosRepository {
  List<StorePaymentMethod>? cachedMethods;
  List<StorePaymentMethod> apiMethods = [];
  bool submitCalled = false;
  String? lastPaymentChoice;
  String? lastPassedMethodName;

  @override
  List<Product> getCachedProductsList() => [
    Product(
      id: 'p1',
      name: 'Shirt Wash',
      category: 'wash',
      type: 'item',
      price: 100,
      active: true,
    ),
  ];

  @override
  List<StorePaymentMethod>? getCachedPaymentMethodsList() => cachedMethods;

  @override
  Future<List<Product>> listProducts() async => getCachedProductsList();

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async => apiMethods;

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
    submitCalled = true;
    lastPaymentChoice = initialPayment != null ? 'prepaid' : 'delivery';
    lastPassedMethodName = initialPayment?['method']?.toString();
    return Order(
      id: 'ORDER-999',
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

class _TestOutletScopeCubit extends Cubit<OutletScope>
    implements OutletScopeCubit {
  _TestOutletScopeCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StorePaymentMethod.isCashOnDelivery unit tests', () {
    test('code COD with name Pay at handover -> true', () {
      final method = StorePaymentMethod(
        id: '1',
        code: 'COD',
        name: 'Pay at handover',
      );
      expect(method.isCashOnDelivery, isTrue);
    });

    test('name Cash On Delivery with no code -> true', () {
      final method = StorePaymentMethod(
        id: '2',
        code: '',
        name: 'Cash On Delivery',
      );
      expect(method.isCashOnDelivery, isTrue);
    });

    test('Cash -> false', () {
      final method = StorePaymentMethod(id: '3', code: 'CASH', name: 'Cash');
      expect(method.isCashOnDelivery, isFalse);
    });
  });

  group('CartBloc background refresh of payment methods', () {
    test(
      'cached [Cash, UPI], API returns [Cash] -> state ends with [Cash]',
      () async {
        final repo = _FakePosRepo();
        final cashMethod = StorePaymentMethod(
          id: 'c',
          code: 'CASH',
          name: 'Cash',
        );
        final upiMethod = StorePaymentMethod(id: 'u', code: 'UPI', name: 'UPI');
        repo.cachedMethods = [cashMethod, upiMethod];
        repo.apiMethods = [cashMethod];

        final bloc = CartBloc(posRepository: repo);
        bloc.add(LoadCatalogEvent());

        await expectLater(
          bloc.stream.map((s) => s.paymentMethods.map((m) => m.name).toList()),
          emitsThrough(['Cash']),
        );

        expect(bloc.state.paymentMethods.length, 1);
        expect(bloc.state.paymentMethods.first.name, 'Cash');
        await bloc.close();
      },
    );
  });

  group('CheckoutScreen payment methods tests', () {
    late _FakePosRepo fakeRepo;
    late CartBloc cartBloc;
    late _TestOutletScopeCubit outletCubit;

    final dummyProduct = Product(
      id: 'prod_1',
      name: 'Dry Clean Suit',
      category: 'dry clean',
      type: 'item',
      price: 200,
      active: true,
    );

    final outletA = Outlet(
      id: 'outlet_a',
      outletCode: 'OBLRCHN01',
      displayName: 'Chinnapanahalli Outlet',
      isDefault: true,
      status: 'ACTIVE',
    );

    setUp(() {
      fakeRepo = _FakePosRepo();
      cartBloc = CartBloc(posRepository: fakeRepo);
      outletCubit = _TestOutletScopeCubit(
        OutletScope(
          allowed: [outletA],
          activeOutletId: 'outlet_a',
          allOutlets: false,
          isOwner: true,
        ),
      );
    });

    tearDown(() {
      cartBloc.close();
      outletCubit.close();
    });

    Widget createWidgetUnderTest() {
      return MultiBlocProvider(
        providers: [
          BlocProvider<CartBloc>.value(value: cartBloc),
          BlocProvider<OutletScopeCubit>.value(value: outletCubit),
        ],
        child: const MaterialApp(home: CheckoutScreen()),
      );
    }

    testWidgets(
      '1. Given methods [Cash, Cash On Delivery(code COD), UPI]: exactly 3 options render, no extra Pay on delivery, none selected, Place order disabled',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(
                id: 'pm_cash',
                code: 'CASH',
                name: 'Cash',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_cod',
                code: 'COD',
                name: 'Cash On Delivery',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_upi',
                code: 'UPI',
                name: 'UPI',
                active: true,
              ),
            ],
            outletId: 'outlet_a',
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Cash On Delivery'), findsOneWidget);
        expect(find.text('UPI'), findsOneWidget);

        // No extra hardcoded "Pay on delivery"
        expect(find.text('Pay on delivery'), findsNothing);

        // Subtitles are removed from payment options
        expect(find.text('Collect full amount at handover'), findsNothing);
        expect(find.text('Pay full amount now'), findsNothing);

        // Submit button is disabled
        final submitButton = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(submitButton.onPressed, isNull);
      },
    );

    testWidgets(
      '2. Select Cash On Delivery -> Place order dispatches paymentChoice delivery with no paymentMethodName',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(
                id: 'pm_cash',
                code: 'CASH',
                name: 'Cash',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_cod',
                code: 'COD',
                name: 'Cash On Delivery',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_upi',
                code: 'UPI',
                name: 'UPI',
                active: true,
              ),
            ],
            outletId: 'outlet_a',
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // Tap Cash On Delivery
        await tester.tap(find.text('Cash On Delivery'));
        await tester.pump();

        expect(find.text('Place order · Pay on delivery'), findsOneWidget);

        final submitButtonFinder = find.byType(PrimaryButton);
        final submitButton = tester.widget<PrimaryButton>(submitButtonFinder);
        expect(submitButton.onPressed, isNotNull);

        await tester.tap(submitButtonFinder);
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(fakeRepo.lastPaymentChoice, 'delivery');
        expect(fakeRepo.lastPassedMethodName, isNull);
      },
    );

    testWidgets(
      '3. Select UPI -> dispatches prepaid with paymentMethodName UPI',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(
                id: 'pm_cash',
                code: 'CASH',
                name: 'Cash',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_cod',
                code: 'COD',
                name: 'Cash On Delivery',
                active: true,
              ),
              StorePaymentMethod(
                id: 'pm_upi',
                code: 'UPI',
                name: 'UPI',
                active: true,
              ),
            ],
            outletId: 'outlet_a',
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // Tap UPI
        await tester.tap(find.text('UPI'));
        await tester.pump();

        final submitButtonFinder = find.byType(PrimaryButton);
        final submitButton = tester.widget<PrimaryButton>(submitButtonFinder);
        expect(submitButton.onPressed, isNotNull);

        await tester.tap(submitButtonFinder);
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(fakeRepo.lastPaymentChoice, 'prepaid');
        expect(fakeRepo.lastPassedMethodName, 'UPI');
      },
    );

    testWidgets(
      '4. Empty list -> No payment methods are enabled text shows and Place order is disabled',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [],
            outletId: 'outlet_a',
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        expect(
          find.text(
            'No payment methods are enabled. Ask the owner to enable one in Profile → Payment methods.',
          ),
          findsOneWidget,
        );

        // No options at all
        expect(find.text('Pay on delivery'), findsNothing);

        final submitButton = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(submitButton.onPressed, isNull);
      },
    );
  });
}
