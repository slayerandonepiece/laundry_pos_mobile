import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';
import 'package:myshop/features/pos/presentation/dialogs/discard_order_dialog.dart';

class MockOrdersRepository implements OrdersRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPosRepository implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestWidget() {
    final cartBloc = CartBloc(posRepository: MockPosRepository());
    final ordersRepo = MockOrdersRepository();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OrdersRepository>.value(value: ordersRepo),
        RepositoryProvider<PosRepository>.value(value: MockPosRepository()),
      ],
      child: BlocProvider<CartBloc>.value(
        value: cartBloc,
        child: const MaterialApp(home: CustomerDetailsScreen()),
      ),
    );
  }

  testWidgets(
    'CustomerDetailsScreen closes without prompt when fields are empty',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Close button (Icons.close)
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // Discard dialog should NOT be shown
      expect(find.byType(DiscardOrderDialog), findsNothing);
    },
  );

  testWidgets(
    'CustomerDetailsScreen shows DiscardOrderDialog when phone is entered',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter phone
      final phoneField = find.byType(TextField).first;
      await tester.enterText(phoneField, '9876543210');
      await tester.pumpAndSettle();

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Discard dialog should be shown
      expect(find.byType(DiscardOrderDialog), findsOneWidget);
      expect(find.text('Discard this order?'), findsOneWidget);

      // Tap Keep going
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();

      expect(find.byType(DiscardOrderDialog), findsNothing);
    },
  );
}
