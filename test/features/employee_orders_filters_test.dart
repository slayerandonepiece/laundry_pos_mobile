import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/orders_list_screen.dart';
import 'package:myshop/features/pos/bloc/cart_bloc.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/app_button.dart';

class _Cache extends LocalCacheService {
  String? activeOutletId = 'o1';
  @override
  Map<String, dynamic>? getCachedUser() => null;
  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'EMPLOYEE'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => [
    {
      'id': 'o1',
      'outletCode': 'O01',
      'displayName': 'Main Outlet',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'o2',
      'outletCode': 'O02',
      'displayName': 'Second Outlet',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];
  @override
  String? getActiveOutletId() => activeOutletId;
  @override
  bool isAllOutletsScope() => false;
  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
  @override
  Future<void> setActiveOutletId(String outletId) async {
    activeOutletId = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    activeOutletId = null;
  }

  @override
  Future<void> setAllOutletsScope(bool value) async {}
  @override
  Future<void> clearAllOutletsScope() async {}
}

class _OrdersRepo implements OrdersRepository {
  List<Order> orders = [];
  @override
  bool hasCachedOrders({String? outletId, bool? allOutlets}) => true;
  @override
  List<Order> getCachedOrdersList() => orders;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _Auth() : super(UnauthenticatedState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _OrdersRepo repo;
  late _Cache cache;

  // One clock reading for the whole test file, so day offsets never straddle
  // midnight.
  final clock = DateTime.now();
  String day(int offset) {
    final d = clock.add(Duration(days: offset));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Order order(
    String id, {
    required String status,
    required int dueOffset,
    required int total,
    required int paid,
  }) => Order(
    id: id,
    name: 'Customer $id',
    phone: '9000000000',
    date: day(-3),
    due: day(dueOffset),
    status: status,
    lines: [
      OrderLine(
        productId: 'p',
        name: 'Item',
        quantity: 1,
        unit: 'PIECE',
        amount: total,
      ),
    ],
    payments: paid > 0
        ? [
            OrderPayment(
              id: 'pay-$id',
              amount: paid,
              date: day(-2),
              method: 'Cash',
            ),
          ]
        : [],
  );

  setUp(() {
    cache = _Cache();
    repo = _OrdersRepo()
      ..orders = [
        order('A', status: 'Pending', dueOffset: 0, total: 10000, paid: 0),
        order(
          'B',
          status: 'In Progress',
          dueOffset: -2,
          total: 10000,
          paid: 4000,
        ),
        order('C', status: 'Ready', dueOffset: 1, total: 10000, paid: 10000),
      ];
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 1800),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider<OrdersRepository>.value(value: repo)],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<OrdersBloc>(
              create: (_) => OrdersBloc(ordersRepository: repo),
            ),
            BlocProvider<CartBloc>(
              create: (_) => CartBloc(posRepository: _PosRepo()),
            ),
            BlocProvider<AuthBloc>(create: (_) => _Auth()),
            BlocProvider<OutletScopeCubit>(
              create: (_) => OutletScopeCubit(localCache: cache)..hydrate(),
            ),
          ],
          child: MaterialApp(theme: theme, home: const OrdersListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String field, String option) async {
    await tester.tap(find.text(field));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('has payment status and due date dropdowns, no Clear at first', (
    tester,
  ) async {
    await pump(tester);

    final payment = find.byKey(const ValueKey('payment-status-filter'));
    final due = find.byKey(const ValueKey('due-filter'));
    expect(payment, findsOneWidget);
    expect(due, findsOneWidget);
    expect(tester.getSize(payment).height, 44);
    expect(tester.getSize(due).height, 44);
    expect(find.text('Clear'), findsNothing);
    for (final id in ['A', 'B', 'C']) {
      expect(find.text('Customer $id'), findsOneWidget);
    }
  });

  testWidgets(
    'Ready counts in progress and the three status cards sum to total',
    (tester) async {
      await pump(tester);
      int cardValue(String label) {
        final card = find
            .ancestor(
              of: find.text(label).first,
              matching: find.byType(Container),
            )
            .first;
        final values = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .map((text) => int.tryParse(text.data ?? ''))
            .whereType<int>();
        return values.single;
      }

      expect(cardValue('Total orders'), 3);
      expect(cardValue('In progress'), 2);
      expect(
        cardValue('Pending') +
            cardValue('In progress') +
            cardValue('Completed'),
        cardValue('Total orders'),
      );
    },
  );

  testWidgets('outlet switch clears an active filter and the search text', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Pending 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Customer A');
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(OrdersListScreen));
    final bloc = context.read<OrdersBloc>();
    expect(bloc.state.hasActiveFilters, isTrue);
    context.read<OutletScopeCubit>().select('o2');
    await tester.pumpAndSettle();

    expect(bloc.state.hasActiveFilters, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('search clear has a labeled 44 by 44 hit area', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pumpAndSettle();
    final clear = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Clear search',
    );
    expect(clear, findsOneWidget);
    expect(tester.getSize(clear), const Size(44, 44));
  });

  testWidgets('search miss names the query; filter-only miss stays generic', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Nobody');
    await tester.pumpAndSettle();
    expect(find.text('No orders match "Nobody"'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await choose(tester, 'Any due date', 'Late');
    await choose(tester, 'Payment status', 'Paid');
    expect(find.text('No orders match'), findsOneWidget);
    expect(find.text('No orders match "Nobody"'), findsNothing);
  });

  testWidgets('payment status filters the list and shows Clear on the row', (
    tester,
  ) async {
    await pump(tester);
    final dropdownsBefore = tester.getRect(
      find.byKey(const ValueKey('payment-status-filter')),
    );

    await choose(tester, 'Payment status', 'Part-paid');

    expect(find.text('Customer B'), findsOneWidget);
    expect(find.text('Customer A'), findsNothing);
    expect(find.text('Customer C'), findsNothing);

    final clear = find.byType(TextActionButton);
    expect(clear, findsOneWidget);
    expect(
      tester.getRect(clear).center.dy,
      dropdownsBefore.center.dy,
      reason: 'Clear sits on the dropdown row',
    );
    // The dropdown did not move or resize when Clear appeared.
    expect(
      tester.getRect(find.byKey(const ValueKey('payment-status-filter'))),
      dropdownsBefore,
    );
  });

  testWidgets('due date scope and payment status combine; chip counts follow', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('All 3'), findsOneWidget);

    await choose(tester, 'Any due date', 'Late');
    // Only B is late.
    expect(find.text('Customer B'), findsOneWidget);
    expect(find.text('Customer A'), findsNothing);
    expect(find.text('All 1'), findsOneWidget);
    expect(find.text('In progress 1'), findsOneWidget);
    expect(find.text('Pending 0'), findsOneWidget);

    await choose(tester, 'Payment status', 'Paid');
    // Late and paid: nobody.
    expect(find.text('No orders match'), findsOneWidget);
  });

  testWidgets('Clear resets every filter and the search box', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Customer');
    await choose(tester, 'Payment status', 'Unpaid');
    expect(find.text('Customer A'), findsOneWidget);
    expect(find.text('Customer B'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    for (final id in ['A', 'B', 'C']) {
      expect(find.text('Customer $id'), findsOneWidget);
    }
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Payment status'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets(
    'the empty result offers Clear filters, which restores the list',
    (tester) async {
      await pump(tester);
      await choose(tester, 'Any due date', 'Late');
      await choose(tester, 'Payment status', 'Paid');
      expect(find.text('Clear filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('Customer A'), findsOneWidget);
      expect(find.text('Customer B'), findsOneWidget);
    },
  );

  testWidgets('no owner financial summary appears for an employee', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Sales summary'), findsNothing);
    expect(find.text('Total order value'), findsNothing);
  });

  for (final scale in [1.3, 2.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        '320x568 at ${scale}x text (${dark ? 'dark' : 'light'}): pinned header '
        'fits, no overflow, Clear on its own line',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(
            tester,
            size: const Size(320, 568),
            theme: dark ? ThemeData.dark() : ThemeData.light(),
          );
          expect(tester.takeException(), isNull);

          // The search box stays pinned when the list is scrolled.
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.getRect(find.byType(TextField)).top, lessThan(568 / 3));

          await tester.scrollUntilVisible(
            find.text('Payment'),
            -100,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Payment'), findsOneWidget);
          expect(find.text('Due'), findsOneWidget);
          await choose(tester, 'Payment', 'Unpaid');
          expect(tester.takeException(), isNull);
          expect(find.text('Clear'), findsOneWidget);
        },
      );
    }
  }
}
