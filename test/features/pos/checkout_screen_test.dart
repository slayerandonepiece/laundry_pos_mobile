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
  String? lastPassedOutletId;
  String? lastPassedMethodName;
  bool submitCalled = false;
  String? lastPaymentChoice;

  @override
  List<Product> getCachedProductsList() => [];

  @override
  Future<List<Product>> listProducts() async => [];

  @override
  Future<List<StorePaymentMethod>> listPaymentMethods() async => [];

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
    lastPassedOutletId = outletId;
    lastPassedMethodName = initialPayment?['method']?.toString();
    return Order(
      id: 'ORDER-123',
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
  group('CheckoutScreen payment methods & outlet display tests', () {
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
        child: const MaterialApp(
          home: CheckoutScreen(),
        ),
      );
    }

    testWidgets('Renders resolved outlet name when outletId is set in CartState', (
      tester,
    ) async {
      cartBloc.add(ResetSaleEvent(outletId: 'outlet_a'));
      cartBloc.add(AddItemToCartEvent(product: dummyProduct, quantity: 1));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Chinnapanahalli Outlet'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('Omits outlet row when outletId is null in CartState', (
      tester,
    ) async {
      cartBloc.add(ResetSaleEvent());
      cartBloc.add(AddItemToCartEvent(product: dummyProduct, quantity: 1));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Chinnapanahalli Outlet'), findsNothing);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
    });

    testWidgets('Renders only store payment methods without hardcoded Pay on delivery row', (
      tester,
    ) async {
      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
          paymentMethods: [
            StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
            StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
            StorePaymentMethod(id: 'pm_card', name: 'Debit Card', active: true),
          ],
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Debit Card'), findsOneWidget);
      expect(find.text('Pay on delivery'), findsNothing);
    });

    testWidgets('Empty payment methods shows warning message and omits prepaid choices', (
      tester,
    ) async {
      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
          paymentMethods: [],
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
      expect(find.text('Cash'), findsNothing);
      expect(find.text('UPI'), findsNothing);
      expect(find.text('Pay on delivery'), findsNothing);

      final submitButton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('Submit button disabled until payment method is selected', (
      tester,
    ) async {
      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
          paymentMethods: [
            StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
            StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
          ],
          outletId: 'outlet_a',
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      // Initially disabled
      final submitButtonFinder = find.byType(PrimaryButton);
      expect(submitButtonFinder, findsOneWidget);
      PrimaryButton button = tester.widget(submitButtonFinder);
      expect(button.onPressed, isNull);

      // Tap UPI to select
      await tester.tap(find.text('UPI'));
      await tester.pump();

      button = tester.widget(submitButtonFinder);
      expect(button.onPressed, isNotNull);

      // Submit UPI payment
      await tester.tap(submitButtonFinder);
      await tester.pump();

      expect(fakeRepo.submitCalled, isTrue);
      expect(fakeRepo.lastPassedMethodName, equals('UPI'));
      expect(fakeRepo.lastPassedOutletId, equals('outlet_a'));
    });

    testWidgets('Selecting Cash On Delivery method updates button label and submits delivery choice', (
      tester,
    ) async {
      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
          paymentMethods: [
            StorePaymentMethod(id: 'pm_cod', code: 'COD', name: 'Cash On Delivery', active: true),
          ],
          outletId: 'outlet_a',
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      final submitButtonFinder = find.byType(PrimaryButton);

      // Tap Cash On Delivery
      await tester.tap(find.text('Cash On Delivery'));
      await tester.pump();

      expect(find.text('Place order · Pay on delivery'), findsOneWidget);

      final button = tester.widget<PrimaryButton>(submitButtonFinder);
      expect(button.onPressed, isNotNull);

      await tester.tap(submitButtonFinder);
      await tester.pump();

      expect(fakeRepo.submitCalled, isTrue);
      expect(fakeRepo.lastPassedMethodName, isNull); // delivery sends no payment method name
      expect(fakeRepo.lastPassedOutletId, equals('outlet_a'));
    });
  });
}
