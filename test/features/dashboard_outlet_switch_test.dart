import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/owner_dashboard_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

/// Guards the real outlet switch on the dashboard (OutletScopeCubit ->
/// OwnerDashboardScreen listener -> `_resetCards`, and the scope-aware
/// `_cardKey`). The older "outlet switch" test only bumps a reset signal.
class _Cache extends LocalCacheService {
  String? active = 'outlet_1';
  bool all = false;

  @override
  Map<String, dynamic>? getCachedUser() => null;
  @override
  String? getRememberedOutlet(String userId, String storeId) => null;
  @override
  Future<void> setRememberedOutlet(String u, String s, String o) async {}
  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': 'OWNER'};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => [
    for (final n in [1, 2])
      {
        'id': 'outlet_$n',
        'outletCode': 'O$n',
        'displayName': 'Outlet $n',
        'isDefault': n == 1,
        'status': 'ACTIVE',
      },
  ];
  @override
  String? getActiveOutletId() => active;
  @override
  Future<void> setActiveOutletId(String id) async => active = id;
  @override
  Future<void> clearActiveOutletId() async => active = null;
  @override
  bool isAllOutletsScope() => all;
  @override
  Future<void> setAllOutletsScope(bool v) async => all = v;
  @override
  Future<void> clearAllOutletsScope() async => all = false;
  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
}

class _Repo implements OwnerRepository {
  final base = DashboardMetrics(
    todo: 3,
    serviceMix: [ServiceMixItem(label: 'PageService', amount: 100)],
  );
  final periodMetrics = DashboardMetrics(
    serviceMix: [ServiceMixItem(label: 'PeriodOnlyService', amount: 900)],
  );
  Completer<void>? periodGate;

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) async => base;

  @override
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) async {
    if (periodGate != null) await periodGate!.future;
    return periodMetrics;
  }

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => base;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _Auth() : super(UnauthenticatedState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orders extends Bloc<OrdersEvent, OrdersState> implements OrdersBloc {
  _Orders() : super(OrdersState()) {
    on<LoadOrdersEvent>((e, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Repo repo;
  late OwnerBloc ownerBloc;
  late _Orders ordersBloc;
  late _Auth authBloc;
  late OutletScopeCubit cubit;

  const filterDate = ValueKey('filter-salesByDate');
  const filterService = ValueKey('filter-salesByService');

  setUp(() {
    SyncFreshness.reset();
    repo = _Repo();
    ownerBloc = OwnerBloc(ownerRepository: repo);
    ordersBloc = _Orders();
    authBloc = _Auth();
    cubit = OutletScopeCubit(localCache: _Cache())..hydrate();
  });

  tearDown(() async {
    await ownerBloc.close();
    await ordersBloc.close();
    await authBloc.close();
    await cubit.close();
    SyncFreshness.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OwnerBloc>.value(value: ownerBloc),
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OutletScopeCubit>.value(value: cubit),
        ],
        child: const MaterialApp(home: OwnerDashboardScreen()),
      ),
    );
    await settle(tester);
  }

  PeriodRange rangeOf(WidgetTester tester, Key key) =>
      tester.widget<PeriodFilter>(find.byKey(key)).value;

  Finder inFilter(Key key, String text) =>
      find.descendant(of: find.byKey(key), matching: find.text(text));

  testWidgets(
    'switching outlet resets both cards to the current month and clears cards',
    (tester) async {
      await pumpScreen(tester);
      await tester.tap(inFilter(filterDate, '7 days'));
      await settle(tester);
      await tester.tap(inFilter(filterService, PeriodRange.previousMonthLabel()));
      await settle(tester);
      expect(rangeOf(tester, filterDate), PeriodRange.last7);
      expect(rangeOf(tester, filterService), PeriodRange.previousMonth);
      expect(ownerBloc.state.cards, hasLength(2));

      cubit.select('outlet_2');
      await settle(tester);

      expect(cubit.state.activeOutletId, 'outlet_2');
      expect(rangeOf(tester, filterDate), PeriodRange.thisMonth);
      expect(rangeOf(tester, filterService), PeriodRange.thisMonth);
      expect(ownerBloc.state.cards, isEmpty);
    },
  );

  testWidgets('a period reply requested under outlet A is dropped after the '
      'switch to outlet B', (tester) async {
    await pumpScreen(tester);
    repo.periodGate = Completer<void>();
    await tester.tap(inFilter(filterService, '7 days'));
    await tester.pump();
    expect(ownerBloc.state.cards.values.single.loading, isTrue);

    cubit.select('outlet_2');
    await settle(tester);
    expect(ownerBloc.state.cards, isEmpty);

    // Outlet A's reply lands only now.
    repo.periodGate!.complete();
    await settle(tester);

    expect(ownerBloc.state.cards, isEmpty);
    expect(find.text('PeriodOnlyService'), findsNothing);
    expect(rangeOf(tester, filterService), PeriodRange.thisMonth);
  });

  testWidgets('the same period asked under outlet B is keyed to B, so a stale '
      'reply from A cannot fill it', (tester) async {
    await pumpScreen(tester);
    repo.periodGate = Completer<void>();
    await tester.tap(inFilter(filterService, '7 days'));
    await tester.pump();
    final keyA = ownerBloc.state.cards.values.single.key;

    cubit.select('outlet_2');
    await settle(tester);
    await tester.tap(inFilter(filterService, '7 days'));
    await tester.pump();
    final keyB = ownerBloc.state.cards.values.single.key;
    expect(keyB, isNot(keyA));

    repo.periodGate!.complete();
    await settle(tester);
    final slice = ownerBloc.state.cards.values.single;
    expect(slice.key, keyB);
    expect(slice.metrics, isNotNull);
  });
}
