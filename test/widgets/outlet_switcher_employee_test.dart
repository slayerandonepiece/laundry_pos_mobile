import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';

import 'outlet_switcher_test.dart' show FakeLocalCache;

class _EmployeeCache extends FakeLocalCache {
  int pending = 0;
  final List<String> events;

  _EmployeeCache(this.events);

  @override
  int getTotalPendingCount() => pending;

  @override
  Future<void> clearScopeData(String scope) async => events.add('clear:$scope');
}

class _FakeSyncEngine extends SyncEngine {
  _FakeSyncEngine(this.events, this.onTrigger) : super.internal();
  final List<String> events;
  final void Function() onTrigger;

  /// What the last run reports; a switch to a new outlet needs it true.
  bool runSucceeds = true;

  /// Set to hold a run open (e.g. to tap twice while a switch is running).
  Completer<void>? gate;

  @override
  bool? get lastRunSucceeded => runSucceeds;

  @override
  Future<void> trigger() async {
    events.add('flush');
    onTrigger();
    if (gate != null) await gate!.future;
  }
}

class _Online extends ConnectivityService {
  _Online() : super.internal();
  @override
  bool get isOffline => false;
  @override
  Future<bool> checkIsOffline() async => false;
}

void main() {
  late List<String> events;
  late _EmployeeCache cache;
  late OutletScopeCubit cubit;
  late SyncEngine originalEngine;

  final twoOutlets = [
    {
      'id': 'outlet_1',
      'outletCode': 'A1',
      'displayName': 'Chinnapanahalli',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'outlet_2',
      'outletCode': 'A2',
      'displayName': 'Marathahalli',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  setUp(() async {
    events = [];
    cache = _EmployeeCache(events);
    cubit = OutletScopeCubit(localCache: cache);
    await cache.setActiveStoreId('store_a');
    await cache.setAllowedOutletsForStore('store_a', twoOutlets);
    await cache.setCachedStoreDetails({'role': 'EMPLOYEE'});
    await cache.setActiveOutletId('outlet_1');
    cubit.hydrate();
    ConnectivityService.instance = _Online();
    originalEngine = SyncEngine.instance;
  });

  tearDown(() {
    SyncEngine.instance = originalEngine;
    ConnectivityService.instance = ConnectivityService.internal();
    cubit.close();
  });

  Widget wrap() => MaterialApp(
    home: BlocProvider<OutletScopeCubit>.value(
      value: cubit,
      child: Scaffold(
        appBar: AppBar(title: const OutletTitleSwitcher(screenLabel: 'Orders')),
        body: const SizedBox.shrink(),
      ),
    ),
  );

  Future<void> pickMarathahalli(WidgetTester tester) async {
    await tester.tap(find.byType(OutletTitleSwitcher));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text('Marathahalli'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickMarathahalliWithoutSettling(WidgetTester tester) async {
    await tester.tap(find.byType(OutletTitleSwitcher));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text('Marathahalli'),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'Employee switch: queued changes are sent first, the new outlet syncs, and only then is the old outlet cleared',
    (tester) async {
      cache.pending = 2;
      SyncEngine.instance = _FakeSyncEngine(events, () => cache.pending = 0);

      await tester.pumpWidget(wrap());
      await pickMarathahalli(tester);

      expect(events, ['flush', 'flush', 'clear:outlet_1']);
      expect(cubit.state.activeOutletId, 'outlet_2');
    },
  );

  testWidgets(
    'Employee switch: nothing queued means no queue flush, just the new outlet sync then the clear',
    (tester) async {
      SyncEngine.instance = _FakeSyncEngine(events, () {});

      await tester.pumpWidget(wrap());
      await pickMarathahalli(tester);

      expect(events, ['flush', 'clear:outlet_1']); // flush = new outlet sync
      expect(cubit.state.activeOutletId, 'outlet_2');
    },
  );

  testWidgets(
    'Employee switch: changes that will not sync abort the switch and clear nothing',
    (tester) async {
      cache.pending = 1;
      SyncEngine.instance = _FakeSyncEngine(events, () {}); // stays pending

      await tester.pumpWidget(wrap());
      await pickMarathahalli(tester);

      expect(events, ['flush']);
      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(
        find.text(
          'Some changes are still waiting to sync. Try again once they have.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Employee switch: if the new outlet fails to sync, the old outlet and its data stay and an error is shown',
    (tester) async {
      final engine = _FakeSyncEngine(events, () {})..runSucceeds = false;
      SyncEngine.instance = engine;

      await tester.pumpWidget(wrap());
      await pickMarathahalli(tester);

      expect(events, ['flush']); // synced the new outlet, cleared nothing
      expect(events.any((e) => e.startsWith('clear')), isFalse);
      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(cache.getActiveOutletId(), 'outlet_1');
      expect(
        find.text(
          "Couldn't load Marathahalli. Staying on your current outlet.",
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Employee switch: the old outlet is still on the phone while the new one syncs',
    (tester) async {
      final engine = _FakeSyncEngine(events, () {})..gate = Completer<void>();
      SyncEngine.instance = engine;

      await tester.pumpWidget(wrap());
      await tester.tap(find.byType(OutletTitleSwitcher));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Marathahalli'),
        ),
      );
      await tester.pump();
      await tester.pump();

      // New outlet selected and syncing; nothing dropped yet.
      expect(cubit.state.activeOutletId, 'outlet_2');
      expect(events, ['flush']);

      engine.gate!.complete();
      await tester.pumpAndSettle();
      expect(events, ['flush', 'clear:outlet_1']);
    },
  );

  testWidgets(
    'Employee switch: a second pick while a switch is running does nothing',
    (tester) async {
      final engine = _FakeSyncEngine(events, () {})..gate = Completer<void>();
      SyncEngine.instance = engine;

      await tester.pumpWidget(wrap());
      await pickMarathahalliWithoutSettling(tester);
      // Menu again, same pick, while the first switch's sync is still open.
      await tester.tap(find.byType(OutletTitleSwitcher));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Chinnapanahalli'),
        ),
      );
      await tester.pump();

      engine.gate!.complete();
      await tester.pumpAndSettle();
      expect(events, ['flush', 'clear:outlet_1']); // one switch only
      expect(cubit.state.activeOutletId, 'outlet_2');
    },
  );
}
