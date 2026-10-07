import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/owner/presentation/payment_methods_screen.dart';

class TrackingOwnerBloc extends Bloc<OwnerEvent, OwnerState>
    implements OwnerBloc {
  final List<OwnerEvent> dispatchedEvents = [];

  TrackingOwnerBloc([OwnerState? initialState])
    : super(
        initialState ??
            OwnerState(
              paymentMethods: [
                StorePaymentMethod(
                  id: 'pm-cash',
                  name: 'Cash',
                  type: 'Cash',
                  active: true,
                ),
                StorePaymentMethod(
                  id: 'pm-upi',
                  name: 'UPI QR',
                  type: 'UPI',
                  code: 'MERCHANT-UPI',
                  active: false,
                ),
              ],
            ),
      ) {
    on<OwnerEvent>((event, emit) {
      dispatchedEvents.add(event);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  FakeAuthBloc() : super(UnauthenticatedState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOrdersBloc extends Bloc<OrdersEvent, OrdersState>
    implements OrdersBloc {
  FakeOrdersBloc() : super(OrdersState()) {
    on<OrdersEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestApp({required TrackingOwnerBloc ownerBloc}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<OwnerBloc>.value(value: ownerBloc),
        BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
        BlocProvider<OrdersBloc>(create: (_) => FakeOrdersBloc()),
      ],
      child: const MaterialApp(home: PaymentMethodsScreen()),
    );
  }

  group('PaymentMethodsScreen empty state', () {
    testWidgets('says so when there are no methods and nothing is loading', (
      tester,
    ) async {
      final bloc = TrackingOwnerBloc(OwnerState());
      await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
      await tester.pumpAndSettle();

      expect(find.text('No payment methods enabled'), findsOneWidget);
    });

    testWidgets('shows a spinner, not the empty state, while loading', (
      tester,
    ) async {
      final bloc = TrackingOwnerBloc(
        OwnerState(loading: {OwnerSection.paymentMethods}),
      );
      await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
      await tester.pump();

      expect(find.text('No payment methods enabled'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });

  group('PaymentMethodsScreen stages', () {
    testWidgets('read-only: no switches, shows the contact-support help', (
      tester,
    ) async {
      final bloc = TrackingOwnerBloc(
        OwnerState(
          paymentMethods: [
            StorePaymentMethod(id: 'a', name: 'Cash', code: 'CASH'),
            StorePaymentMethod(
              id: 'b',
              name: 'Old',
              code: 'OLD',
              active: false,
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Old'), findsNothing); // disabled methods are hidden
      expect(
        find.text('Contact support to change which methods are offered.'),
        findsOneWidget,
      );
    });

    testWidgets('stage decides which of the two columns a method is in', (
      tester,
    ) async {
      final bloc = TrackingOwnerBloc(
        OwnerState(
          paymentMethods: [
            StorePaymentMethod(
              id: 'a',
              name: 'Card',
              code: 'CARD',
              stage: 'PRE_ORDER',
            ),
            StorePaymentMethod(
              id: 'b',
              name: 'Cash',
              code: 'CASH',
              stage: 'BOTH',
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
      await tester.pumpAndSettle();

      expect(find.text('When placing an order'), findsNWidgets(2));
      expect(find.text('After the order'), findsNWidgets(2));
      // Card: ticked up front only. Cash: ticked in both places.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(1));
    });
  });

  group('StorePaymentMethod stage rules', () {
    StorePaymentMethod m(String code, String stage) =>
        StorePaymentMethod(id: code, code: code, name: code, stage: stage);

    test('PRE_ORDER is first only, POST_ORDER second only, BOTH both', () {
      expect(m('UPI', 'PRE_ORDER').offeredWhenPlacingOrder, isTrue);
      expect(m('UPI', 'PRE_ORDER').offeredAfterOrder, isFalse);
      expect(m('UPI', 'POST_ORDER').offeredWhenPlacingOrder, isFalse);
      expect(m('UPI', 'POST_ORDER').offeredAfterOrder, isTrue);
      expect(m('UPI', 'BOTH').offeredWhenPlacingOrder, isTrue);
      expect(m('UPI', 'BOTH').offeredAfterOrder, isTrue);
    });

    test('COD is never offered after the order, even when stage is BOTH', () {
      expect(m('COD', 'BOTH').offeredAfterOrder, isFalse);
      expect(m('COD', 'BOTH').offeredWhenPlacingOrder, isTrue);
    });

    test('a missing or unknown stage (old cache) behaves as BOTH', () {
      final fromOld = StorePaymentMethod.fromJson({'id': 'x', 'name': 'Cash'});
      expect(fromOld.stage, 'BOTH');
      expect(
        StorePaymentMethod.fromJson({
          'id': 'x',
          'name': 'Cash',
          'stage': 'nope',
        }).stage,
        'BOTH',
      );
      expect(StorePaymentMethod.fromJson(fromOld.toJson()).stage, 'BOTH');
    });
  });
}
