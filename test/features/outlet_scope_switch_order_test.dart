import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

class _Cache extends LocalCacheService {
  final List<String> events = [];
  String role;
  List<Map<String, dynamic>> outlets;
  String? active;
  bool all;

  _Cache({
    this.role = 'EMPLOYEE',
    this.active = 'o1',
    this.all = false,
    int outletCount = 2,
  }) : outlets = [
         for (var n = 1; n <= outletCount; n++)
           {
             'id': 'o$n',
             'outletCode': 'C$n',
             'displayName': 'Outlet $n',
             'isDefault': n == 1,
             'status': 'ACTIVE',
           },
       ];

  @override
  Map<String, dynamic>? getCachedStoreDetails() => {'role': role};
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => outlets;
  @override
  String? getActiveOutletId() => active;
  @override
  Future<void> setActiveOutletId(String id) async {
    active = id;
    events.add('active:$id');
  }

  @override
  Future<void> clearActiveOutletId() async => active = null;
  @override
  bool isAllOutletsScope() => all;
  @override
  Future<void> setAllOutletsScope(bool v) async => all = v;
  @override
  Future<void> clearAllOutletsScope() async => all = false;
  @override
  Map<String, dynamic>? getCachedUser() => null;
  @override
  Future<void> clearScopeData(String scope) async => events.add('clear:$scope');
}

void main() {
  group('selectClearingPrevious ordering', () {
    late _Cache cache;
    late OutletScopeCubit cubit;

    setUp(() {
      cache = _Cache();
      cubit = OutletScopeCubit(localCache: cache)..hydrate();
      cache.events.clear();
    });
    tearDown(() => cubit.close());

    test('selects the new outlet, syncs it, and only then clears the old '
        'one', () async {
      final ok = await cubit.selectClearingPrevious(
        'o2',
        syncNewScope: () async {
          cache.events.add('sync');
          expect(cubit.state.activeOutletId, 'o2'); // already switched
          expect(cache.events, isNot(contains('clear:o1'))); // not yet
          return true;
        },
      );
      expect(ok, isTrue);
      expect(cache.events, ['active:o2', 'sync', 'clear:o1']);
      expect(cubit.state.activeOutletId, 'o2');
    });

    test(
      'a failed sync keeps the old outlet and its data and rolls back',
      () async {
        final ok = await cubit.selectClearingPrevious(
          'o2',
          syncNewScope: () async => false,
        );
        expect(ok, isFalse);
        expect(cache.events, ['active:o2', 'active:o1']);
        expect(cubit.state.activeOutletId, 'o1');
        expect(cache.active, 'o1');
      },
    );

    test('a second switch while one is running is refused', () async {
      final gate = Completer<bool>();
      final first = cubit.selectClearingPrevious(
        'o2',
        syncNewScope: () => gate.future,
      );
      expect(cubit.isSwitching, isTrue);
      expect(await cubit.selectClearingPrevious('o1'), isFalse);
      expect(cubit.state.activeOutletId, 'o2');

      gate.complete(true);
      expect(await first, isTrue);
      expect(cubit.isSwitching, isFalse);
      expect(cache.events, ['active:o2', 'clear:o1']);
    });

    test('the busy flag is released after a failed sync', () async {
      await cubit.selectClearingPrevious('o2', syncNewScope: () async => false);
      expect(cubit.isSwitching, isFalse);
    });

    test('the same outlet again does not sync or clear', () async {
      var synced = false;
      final ok = await cubit.selectClearingPrevious(
        'o1',
        syncNewScope: () async => synced = true,
      );
      expect(ok, isTrue);
      expect(synced, isFalse);
      expect(cache.events.where((e) => e.startsWith('clear')), isEmpty);
    });
  });

  group('hydrate persists a single-outlet scope', () {
    test('an owner with one outlet persists it like an employee does', () {
      final cache = _Cache(
        role: 'OWNER',
        active: null,
        all: true,
        outletCount: 1,
      );
      final cubit = OutletScopeCubit(localCache: cache)..hydrate();
      addTearDown(cubit.close);

      expect(cubit.state.activeOutletId, 'o1');
      expect(cubit.state.allOutlets, isFalse);
      expect(cache.getActiveOutletId(), 'o1');
      expect(cache.isAllOutletsScope(), isFalse);
    });

    test('an owner with several outlets is not forced into one', () {
      final cache = _Cache(role: 'OWNER', active: null, all: true);
      final cubit = OutletScopeCubit(localCache: cache)..hydrate();
      addTearDown(cubit.close);

      expect(cubit.state.allOutlets, isTrue);
      expect(cache.getActiveOutletId(), isNull);
    });
  });
}
