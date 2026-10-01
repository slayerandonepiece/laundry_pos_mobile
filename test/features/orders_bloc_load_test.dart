import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';

class _Repo implements OrdersRepository {
  List<Order> cached = [];
  @override
  bool hasCachedOrders({String? outletId, bool? allOutlets}) =>
      cached.isNotEmpty;
  @override
  List<Order> getCachedOrdersList() => cached;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Engine extends SyncEngine {
  _Engine() : super.internal();
  Object? error;
  void Function()? during;
  bool? outcome;
  @override
  bool? get lastRunSucceeded => outcome;
  @override
  Future<void> trigger() async {
    during?.call();
    if (error != null) throw error!;
  }

  @override
  Future<void> retryNow() => trigger();
}

Order _order(
  String id, {
  String status = 'Pending',
  String due = '2026-09-30',
  int paid = 0,
  int total = 100,
}) => Order(
  id: id,
  name: 'N$id',
  phone: '9',
  date: '2026-09-01',
  due: due,
  status: status,
  lines: [
    OrderLine(
      productId: 'p',
      name: 'i',
      quantity: 1,
      unit: 'PIECE',
      amount: total,
    ),
  ],
  payments: paid > 0
      ? [
          OrderPayment(
            id: 'p$id',
            amount: paid,
            date: '2026-09-01',
            method: 'Cash',
          ),
        ]
      : [],
);

void main() {
  late _Repo repo;
  late _Engine engine;
  late OrdersBloc bloc;

  setUp(() {
    repo = _Repo();
    engine = _Engine();
    SyncEngine.instance = engine;
    SyncManager.instance.completeSync(force: true);
    bloc = OrdersBloc(ordersRepository: repo);
  });
  tearDown(() async {
    await bloc.close();
    SyncEngine.instance = SyncEngine.internal();
    SyncManager.instance.completeSync(force: true);
  });

  group('first load / refresh always clear isLoading (M7)', () {
    test('trigger() throwing on the empty-cache first load', () async {
      engine.error = StateError('boom');
      bloc.add(LoadOrdersEvent());
      await pumpEventQueue();
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.loadFailed, isTrue);
    });

    test('retryNow() throwing on refresh', () async {
      engine.error = StateError('boom');
      bloc.add(RefreshOrdersEvent());
      await pumpEventQueue();
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.loadFailed, isTrue);
    });
  });

  group('loadFailed follows the run, not a stale banner', () {
    test('a stale error banner does not fail a run that succeeded', () async {
      SyncManager.instance.setError('old');
      engine.outcome = true;
      bloc.add(RefreshOrdersEvent());
      await pumpEventQueue();
      expect(bloc.state.loadFailed, isFalse);
    });

    test('a failed first sync is not shown as "No orders yet" even if the banner says synced', () async {
      engine.outcome = false;
      bloc.add(LoadOrdersEvent());
      await pumpEventQueue();
      expect(SyncManager.instance.value.isSynced, isTrue);
      expect(bloc.state.loadFailed, isTrue);
    });

    test('a failed run with orders on screen is not a failed load', () async {
      repo.cached = [_order('EL-1')];
      engine.outcome = false;
      bloc.add(RefreshOrdersEvent());
      await pumpEventQueue();
      expect(bloc.state.loadFailed, isFalse);
      expect(bloc.state.allOrders, hasLength(1));
    });
  });

  group('filters', () {
    List<String> ids(OrdersState s) =>
        s.filteredOrders.map((o) => o.id).toList();

    test('paid includes overpaid; unpaid excludes a zero-total order', () {
      final all = [
        _order('paid', paid: 100),
        _order('over', paid: 150),
        _order('unpaid'),
        _order('free', total: 0),
        _order('part', paid: 40),
      ];
      expect(ids(OrdersState(allOrders: all, paymentFilter: 'paid')), [
        'paid',
        'over',
        'free',
      ]);
      expect(ids(OrdersState(allOrders: all, paymentFilter: 'unpaid')), [
        'unpaid',
      ]);
      expect(ids(OrdersState(allOrders: all, paymentFilter: 'partial')), [
        'part',
      ]);
    });

    test('an order with no valid due date is neither due today nor late', () {
      final bad = _order('bad', due: '');
      expect(bad.hasValidDueDate, isFalse);
      expect(
        ids(OrdersState(allOrders: [bad], dueFilter: 'due_today')),
        isEmpty,
      );
      expect(ids(OrdersState(allOrders: [bad], dueFilter: 'late')), isEmpty);
      expect(ids(OrdersState(allOrders: [bad])), ['bad']);
    });

    test('hasValid*Date getters', () {
      final o = _order('x');
      expect(o.hasValidDueDate, isTrue);
      expect(o.hasValidCreatedDate, isTrue);
      expect(_order('y', due: 'garbage').hasValidDueDate, isFalse);
    });
  });
}
