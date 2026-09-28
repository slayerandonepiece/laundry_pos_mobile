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
import 'package:myshop/shared/widgets/centred_dialog.dart';

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
  Widget buildTestApp({
    required TrackingOwnerBloc ownerBloc,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<OwnerBloc>.value(value: ownerBloc),
        BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
        BlocProvider<OrdersBloc>(create: (_) => FakeOrdersBloc()),
      ],
      child: const MaterialApp(
        home: PaymentMethodsScreen(),
      ),
    );
  }

  group('PaymentMethodsScreen Confirmation Dialog Tests', () {
    testWidgets(
      'Disabling an active payment method shows confirmation dialog with correct texts and does not dispatch toggle event yet',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
        await tester.pumpAndSettle();

        bloc.dispatchedEvents.clear();

        final cashSwitch = find.byWidgetPredicate(
          (w) => w is Switch && w.value == true,
        );
        expect(cashSwitch, findsOneWidget);

        // Tap to toggle off
        await tester.tap(cashSwitch);
        await tester.pumpAndSettle();

        // Confirmation dialog is shown
        expect(find.byType(CentredDialog), findsOneWidget);
        expect(find.text('Disable Cash?'), findsOneWidget);
        expect(
          find.text(
            'Customers will no longer be able to pay with Cash at checkout across all outlets.',
          ),
          findsOneWidget,
        );
        expect(find.text('Disable method'), findsOneWidget);
        expect(find.text('Keep enabled'), findsOneWidget);

        // No TogglePaymentMethodEvent should be dispatched yet
        expect(
          bloc.dispatchedEvents.whereType<TogglePaymentMethodEvent>(),
          isEmpty,
        );
      },
    );

    testWidgets(
      'Cancelling via "Keep enabled" closes dialog and leaves method enabled without dispatching toggle event',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
        await tester.pumpAndSettle();

        bloc.dispatchedEvents.clear();

        final cashSwitch = find.byWidgetPredicate(
          (w) => w is Switch && w.value == true,
        );
        expect(cashSwitch, findsOneWidget);

        // Tap switch to trigger confirmation
        await tester.tap(cashSwitch);
        await tester.pumpAndSettle();

        expect(find.byType(CentredDialog), findsOneWidget);

        // Tap cancel button
        await tester.tap(find.text('Keep enabled'));
        await tester.pumpAndSettle();

        // Dialog should be dismissed
        expect(find.byType(CentredDialog), findsNothing);

        // No toggle event should have been dispatched
        expect(
          bloc.dispatchedEvents.whereType<TogglePaymentMethodEvent>(),
          isEmpty,
        );

        // Switch should visually remain on/true
        final switchWidget = tester.widget<Switch>(find.byType(Switch).first);
        expect(switchWidget.value, isTrue);
      },
    );

    testWidgets(
      'Confirming via "Disable method" dispatches TogglePaymentMethodEvent with active: false and closes dialog',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
        await tester.pumpAndSettle();

        bloc.dispatchedEvents.clear();

        final cashSwitch = find.byWidgetPredicate(
          (w) => w is Switch && w.value == true,
        );
        expect(cashSwitch, findsOneWidget);

        // Tap switch to trigger confirmation
        await tester.tap(cashSwitch);
        await tester.pumpAndSettle();

        expect(find.byType(CentredDialog), findsOneWidget);

        // Tap confirm button
        await tester.tap(find.text('Disable method'));
        await tester.pumpAndSettle();

        // Dialog is closed
        expect(find.byType(CentredDialog), findsNothing);

        // TogglePaymentMethodEvent should have been dispatched with id and active: false
        final toggleEvents =
            bloc.dispatchedEvents.whereType<TogglePaymentMethodEvent>().toList();
        expect(toggleEvents.length, equals(1));
        expect(toggleEvents.first.id, equals('pm-cash'));
        expect(toggleEvents.first.active, isFalse);
      },
    );

    testWidgets(
      'Enabling a disabled method stays instant without showing confirmation dialog',
      (tester) async {
        final bloc = TrackingOwnerBloc();
        await tester.pumpWidget(buildTestApp(ownerBloc: bloc));
        await tester.pumpAndSettle();

        bloc.dispatchedEvents.clear();

        final upiSwitch = find.byWidgetPredicate(
          (w) => w is Switch && w.value == false,
        );
        expect(upiSwitch, findsOneWidget);

        // Tap disabled switch to enable it
        await tester.tap(upiSwitch);
        await tester.pumpAndSettle();

        // No dialog should appear
        expect(find.byType(CentredDialog), findsNothing);

        // TogglePaymentMethodEvent dispatched immediately with active: true
        final toggleEvents =
            bloc.dispatchedEvents.whereType<TogglePaymentMethodEvent>().toList();
        expect(toggleEvents.length, equals(1));
        expect(toggleEvents.first.id, equals('pm-upi'));
        expect(toggleEvents.first.active, isTrue);
      },
    );
  });
}
