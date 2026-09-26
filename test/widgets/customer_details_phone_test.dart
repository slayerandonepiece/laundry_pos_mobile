import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/pos/presentation/customer_details_screen.dart';

class FakeOrdersRepository implements OrdersRepository {
  final List<String> lookups = [];

  @override
  Future<String?> lookupCustomerName(String phone) async {
    lookups.add(phone);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPosRepository implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const error = 'Enter a valid 10-digit mobile number';
  late FakeOrdersRepository ordersRepo;

  Widget buildTestWidget() {
    ordersRepo = FakeOrdersRepository();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OrdersRepository>.value(value: ordersRepo),
        RepositoryProvider<PosRepository>.value(value: MockPosRepository()),
      ],
      child: BlocProvider<CartBloc>(
        create: (_) => CartBloc(posRepository: MockPosRepository()),
        child: const MaterialApp(home: CustomerDetailsScreen()),
      ),
    );
  }

  Finder phoneText() => find.byType(TextField).first;

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(phoneText()).controller!.text;

  testWidgets('pasted +91 number is accepted and normalised on blur', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(phoneText());
    await tester.enterText(phoneText(), '+91 98765 43210');
    await tester.pump();
    // Raw text kept while typing.
    expect(fieldText(tester), '+91 98765 43210');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(fieldText(tester), '9876543210');
    expect(find.text(error), findsNothing);
  });

  testWidgets('too-short number shows the inline error on blur', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(phoneText());
    await tester.enterText(phoneText(), '12345');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(fieldText(tester), '12345');
    expect(find.text(error), findsOneWidget);
  });

  testWidgets('search looks up the normalised number and keeps the lookup', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(phoneText());
    await tester.enterText(phoneText(), '+91 98765 43210');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(ordersRepo.lookups, ['9876543210']);
    expect(fieldText(tester), '9876543210');

    // Blurring afterwards must not reset the completed lookup.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('New customer'), findsOneWidget);
  });

  testWidgets('13-digit paste is not truncated and is rejected', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(phoneText());
    await tester.enterText(phoneText(), '9198765432101');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(fieldText(tester), '9198765432101');
    expect(find.text(error), findsOneWidget);
    expect(ordersRepo.lookups, isEmpty);
  });
}
