import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/utils/date_formatter.dart';
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
  String? lastPassedDueDate;
  String? lastPassedNotes;
  bool submitCalled = false;
  String? lastPaymentChoice;
  int? lastPassedAmount;

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
    lastPassedAmount = (initialPayment?['amount'] as num?)?.toInt();
    lastPassedDueDate = dueDate;
    lastPassedNotes = notes;
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

    Widget createWidgetUnderTest({Widget home = const CheckoutScreen()}) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<CartBloc>.value(value: cartBloc),
          BlocProvider<OutletScopeCubit>.value(value: outletCubit),
        ],
        child: MaterialApp(home: home),
      );
    }

    // Checkout sits on top of a page that stands in for the items screen.
    Widget checkoutOnTopOfItems() => createWidgetUnderTest(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CheckoutScreen())),
              child: const Text('Open checkout'),
            ),
          ),
        ),
      ),
    );

    void seedCart() => cartBloc.emit(
      cartBloc.state.copyWith(
        items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
        paymentMethods: [
          StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
          StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
          StorePaymentMethod(
            id: 'pm_cod',
            name: 'Cash On Delivery',
            code: 'COD',
            active: true,
          ),
        ],
      ),
    );

    testWidgets(
      'Renders resolved outlet name when outletId is set in CartState',
      (tester) async {
        cartBloc.add(ResetSaleEvent(outletId: 'outlet_a'));
        cartBloc.add(AddItemToCartEvent(product: dummyProduct, quantity: 1));
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        expect(find.text('Chinnapanahalli Outlet'), findsOneWidget);
        expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      },
    );

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

    testWidgets(
      'Renders only store payment methods without hardcoded Pay on delivery row',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
              StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
              StorePaymentMethod(
                id: 'pm_card',
                name: 'Debit Card',
                active: true,
              ),
            ],
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('UPI'), findsOneWidget);
        expect(find.text('Debit Card'), findsOneWidget);
        expect(find.text('Pay on delivery'), findsNothing);
      },
    );

    testWidgets(
      'Empty payment methods shows warning message and omits prepaid choices',
      (tester) async {
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

        final submitButton = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(submitButton.onPressed, isNull);
      },
    );

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

    Product bigProduct() => Product(
      id: 'prod_big',
      name: 'Duvet',
      category: 'dry clean',
      type: 'item',
      price: 50000,
      active: true,
    );

    void loadBigCart() {
      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_big': CartItem(product: bigProduct(), quantity: 1)},
          paymentMethods: [
            StorePaymentMethod(id: 'pm_cash', name: 'Cash', active: true),
            StorePaymentMethod(
              id: 'pm_cod',
              code: 'COD',
              name: 'Cash On Delivery',
              active: true,
            ),
          ],
          outletId: 'outlet_a',
        ),
      );
    }

    testWidgets(
      'Received now sends a partial amount and rejects an amount above the total',
      (tester) async {
        loadBigCart();
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        final receivedField = find.byKey(const Key('checkout_received_field'));
        expect(receivedField, findsNothing);

        // Pay-on-delivery takes no money now, so the field stays hidden.
        await tester.tap(find.text('Cash On Delivery'));
        await tester.pump();
        expect(receivedField, findsNothing);

        await tester.tap(find.text('Cash'));
        await tester.pump();
        expect(receivedField, findsOneWidget);

        await tester.enterText(receivedField, '600');
        await tester.pump();
        expect(
          find.text('Enter an amount between ₹1 and ₹500'),
          findsOneWidget,
        );
        expect(
          tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
          isNull,
        );

        await tester.enterText(receivedField, '150');
        await tester.pump();
        expect(find.text('Place order · ₹150 received now'), findsOneWidget);

        await tester.tap(find.byType(PrimaryButton));
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(fakeRepo.lastPassedMethodName, 'Cash');
        expect(fakeRepo.lastPassedAmount, 15000);
      },
    );

    testWidgets('Shows the bill: order total, received now and balance due', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      loadBigCart();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Review and pay'), findsOneWidget);
      // Nothing chosen yet: the whole total is still due.
      expect(find.text('Order total'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
      expect(find.text('Received now'), findsNothing);

      // Pay on delivery takes nothing now.
      await tester.tap(find.text('Cash On Delivery'));
      await tester.pump();
      expect(find.text('Received now'), findsNothing);

      // A part payment leaves the rest due.
      await tester.tap(find.text('Cash'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('checkout_received_field')),
        '150',
      );
      await tester.pump();
      expect(find.text('Received now'), findsOneWidget);
      expect(find.text('₹350'), findsOneWidget);
    });

    testWidgets('Full fills in the whole total and clears the balance', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      loadBigCart();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.tap(find.text('Cash'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('checkout_received_full')));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('checkout_received_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '500');
      expect(find.text('Place order · ₹500 received now'), findsOneWidget);
    });

    testWidgets('A blank Received now field still sends the full total', (
      tester,
    ) async {
      loadBigCart();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.tap(find.text('Cash'));
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(fakeRepo.lastPassedAmount, 50000);
    });

    testWidgets(
      'Selecting Cash On Delivery method updates button label and submits delivery choice',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(
                id: 'pm_cod',
                code: 'COD',
                name: 'Cash On Delivery',
                active: true,
              ),
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
        expect(
          fakeRepo.lastPassedMethodName,
          isNull,
        ); // delivery sends no payment method name
        expect(fakeRepo.lastPassedOutletId, equals('outlet_a'));
      },
    );

    testWidgets(
      'Due date defaults to today and is sent in order submission when unchanged',
      (tester) async {
        final today = DateTime.now();
        final expectedFormatted = DateFormatter.formatDate(today);
        final expectedIso = DateFormatter.toIsoDateString(today);

        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
            ],
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // UI displays today's date near order summary
        expect(find.text('Due date: $expectedFormatted'), findsOneWidget);

        // Select UPI and place order
        await tester.tap(find.text('UPI'));
        await tester.pump();

        await tester.tap(find.byType(PrimaryButton));
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(fakeRepo.lastPassedDueDate, equals(expectedIso));
        expect(fakeRepo.lastPassedNotes, equals(''));
      },
    );

    testWidgets(
      'Picking a future date is accepted and reflected in dispatched event',
      (tester) async {
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
            ],
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // Open date picker
        await tester.tap(find.byKey(const Key('checkout_due_date_picker')));
        await tester.pumpAndSettle();

        // Advance to next month to ensure future date
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        // Tap day 15
        await tester.tap(find.text('15'));
        await tester.pumpAndSettle();

        // Confirm dialog
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // Calculate expected date
        final now = DateTime.now();
        final nextMonth = DateTime(now.year, now.month + 1, 15);
        final expectedFormatted = DateFormatter.formatDate(nextMonth);
        final expectedIso = DateFormatter.toIsoDateString(nextMonth);

        expect(find.text('Due date: $expectedFormatted'), findsOneWidget);
        expect(find.text('Due date cannot be in the past'), findsNothing);

        // Submit
        await tester.tap(find.text('UPI'));
        await tester.pump();

        await tester.tap(find.byType(PrimaryButton));
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(fakeRepo.lastPassedDueDate, equals(expectedIso));
      },
    );

    testWidgets('Picking a past date is rejected with an inline error', (
      tester,
    ) async {
      final today = DateTime.now();
      final expectedTodayFormatted = DateFormatter.formatDate(today);

      cartBloc.emit(
        cartBloc.state.copyWith(
          items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
          paymentMethods: [
            StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
          ],
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      // Open date picker
      await tester.tap(find.byKey(const Key('checkout_due_date_picker')));
      await tester.pumpAndSettle();

      // Move to previous month to ensure past date
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      // Tap day 15 of previous month
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      // Confirm dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Inline error should be visible
      expect(find.text('Due date cannot be in the past'), findsOneWidget);

      // The selected date should NOT have been updated to the past date
      expect(find.text('Due date: $expectedTodayFormatted'), findsOneWidget);
    });

    testWidgets(
      'Notes text is optional and passed through to order-creation event when filled',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        cartBloc.emit(
          cartBloc.state.copyWith(
            items: {'prod_1': CartItem(product: dummyProduct, quantity: 1)},
            paymentMethods: [
              StorePaymentMethod(id: 'pm_upi', name: 'UPI', active: true),
            ],
          ),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // Notes field exists and is optional
        expect(find.byKey(const Key('checkout_notes_field')), findsOneWidget);

        // Enter notes
        await tester.enterText(
          find.byKey(const Key('checkout_notes_field')),
          'Handle delicate fabric with gentle detergent',
        );
        await tester.pump();

        // Submit with UPI
        await tester.tap(find.text('UPI'));
        await tester.pump();

        await tester.tap(find.byType(PrimaryButton));
        await tester.pump();

        expect(fakeRepo.submitCalled, isTrue);
        expect(
          fakeRepo.lastPassedNotes,
          equals('Handle delicate fabric with gentle detergent'),
        );
      },
    );

    testWidgets('Back returns to the items without asking to discard', (
      tester,
    ) async {
      seedCart();
      await tester.pumpWidget(checkoutOnTopOfItems());
      await tester.tap(find.text('Open checkout'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('checkout_notes_field')),
        'Starch the collars',
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Discard this order?'), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      // The cart is untouched and keeps what was typed.
      expect(cartBloc.state.items, isNotEmpty);
      expect(cartBloc.state.notes, 'Starch the collars');
    });

    testWidgets('Closing with X asks first, and Cancel keeps the order', (
      tester,
    ) async {
      seedCart();
      await tester.pumpWidget(checkoutOnTopOfItems());
      await tester.tap(find.text('Open checkout'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Discard this order?'), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('Methods sit two to a row and Cash on Delivery stands apart', (
      tester,
    ) async {
      seedCart();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      final cash = tester.getTopLeft(find.text('Cash').first);
      final upi = tester.getTopLeft(find.text('UPI'));
      final cod = tester.getTopLeft(find.text('Cash On Delivery'));
      expect(upi.dy, cash.dy); // same row
      expect(upi.dx, greaterThan(cash.dx));
      expect(cod.dy, greaterThan(cash.dy)); // below, on its own
      expect(find.text('Customer pays at delivery'), findsOneWidget);
    });

    testWidgets('Quick due-date chips set the date', (tester) async {
      seedCart();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.tap(find.text('Tomorrow'));
      await tester.pump();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(
        find.text('Due date: ${DateFormatter.formatDate(tomorrow)}'),
        findsOneWidget,
      );
    });
  });
}
