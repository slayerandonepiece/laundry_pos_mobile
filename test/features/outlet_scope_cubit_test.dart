import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';

void main() {
  late Directory tempDir;
  late LocalCacheService localCache;
  late OutletScopeCubit cubit;

  final oneOutlet = [
    {
      'id': 'outlet_1',
      'outletCode': 'OBLRCHN01',
      'displayName': 'Chinnapanahalli',
      'isDefault': true,
      'status': 'ACTIVE',
    },
  ];

  final twoOutlets = [
    ...oneOutlet,
    {
      'id': 'outlet_2',
      'outletCode': 'OBLRMTH02',
      'displayName': 'Marathahalli',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    localCache = LocalCacheService();
    cubit = OutletScopeCubit(localCache: localCache);
    await localCache.setActiveStoreId('store_a');
  });

  tearDown(() async {
    await cubit.close();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OutletScopeCubit — O3 initial scope', () {
    test('Owner with 0 outlets lands on All outlets', () async {
      await localCache.setAllowedOutletsForStore('store_a', []);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});

      cubit.adoptFromLogin(isOwner: true);

      expect(cubit.state.allOutlets, isTrue);
      expect(cubit.state.activeOutletId, isNull);
      expect(cubit.state.requiresSelection, isFalse);
      expect(cubit.state.blockedNoOutlet, isFalse);
    });

    test('Owner with outlets lands on All outlets', () async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});

      cubit.adoptFromLogin(isOwner: true);

      expect(cubit.state.allOutlets, isTrue);
      expect(cubit.state.allowed.length, 2);
    });

    test(
      'Owner with exactly 1 outlet lands on that outlet with allOutlets: false',
      () async {
        await localCache.setAllowedOutletsForStore('store_a', oneOutlet);
        await localCache.setCachedStoreDetails({'role': 'OWNER'});

        cubit.adoptFromLogin(isOwner: true);

        expect(cubit.state.allOutlets, isFalse);
        expect(cubit.state.activeOutletId, 'outlet_1');
        expect(cubit.state.allowed.length, 1);
        expect(localCache.getActiveOutletId(), 'outlet_1');
        expect(localCache.isAllOutletsScope(), isFalse);
      },
    );

    test('Employee with 0 outlets is blocked (O4)', () async {
      await localCache.setAllowedOutletsForStore('store_a', []);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});

      cubit.adoptFromLogin(isOwner: false);

      expect(cubit.state.blockedNoOutlet, isTrue);
      expect(cubit.state.requiresSelection, isFalse);
      expect(cubit.state.allOutlets, isFalse);
    });

    test('Employee with exactly 1 outlet is silently selected', () async {
      await localCache.setAllowedOutletsForStore('store_a', oneOutlet);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});

      cubit.adoptFromLogin(isOwner: false);

      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(cubit.state.requiresSelection, isFalse);
      expect(cubit.state.blockedNoOutlet, isFalse);
      expect(localCache.getActiveOutletId(), 'outlet_1');
    });

    test('Employee with 2+ outlets must pick (picker blocks shell)', () async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});

      cubit.adoptFromLogin(isOwner: false);

      expect(cubit.state.requiresSelection, isTrue);
      expect(cubit.state.activeOutletId, isNull);

      cubit.select('outlet_2');

      expect(cubit.state.requiresSelection, isFalse);
      expect(cubit.state.activeOutletId, 'outlet_2');
      expect(localCache.getActiveOutletId(), 'outlet_2');
    });

    test(
      'Employee cold start with nothing cached forces re-auth, not a guess',
      () {
        // No setAllowedOutletsForStore call at all — simulates a token that
        // survived a data clear, or a pre-this-feature cache.
        cubit.hydrate();

        expect(cubit.state.missingCache, isTrue);
        expect(cubit.state.blockedNoOutlet, isFalse);
        expect(cubit.state.requiresSelection, isFalse);
      },
    );

    test('Owner cold start with nothing cached defaults to All outlets, no re-auth', () async {
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.hydrate();

      expect(cubit.state.missingCache, isFalse);
      expect(cubit.state.allOutlets, isTrue);
    });

    test('Owner cold start with exactly 1 outlet hydrates to that outlet with allOutlets: false', () async {
      await localCache.setAllowedOutletsForStore('store_a', oneOutlet);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});

      cubit.hydrate();

      expect(cubit.state.missingCache, isFalse);
      expect(cubit.state.allOutlets, isFalse);
      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(cubit.state.allowed.length, 1);
    });

    test('reset() clears state back to empty (logout)', () async {
      await localCache.setAllowedOutletsForStore('store_a', oneOutlet);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      cubit.adoptFromLogin(isOwner: false);
      expect(cubit.state.activeOutletId, isNotNull);

      cubit.reset();

      expect(cubit.state.allowed, isEmpty);
      expect(cubit.state.activeOutletId, isNull);
      expect(cubit.state.missingCache, isFalse);
    });
  });

  group('Remembered outlet across logout', () {
    Future<void> signInEmployee(String userId) async {
      await localCache.setCachedUser({'id': userId, 'name': 'Staff'});
      await localCache.setActiveStoreId('store_a');
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      cubit.adoptFromLogin(isOwner: false);
    }

    test(
      'an employee who picked an outlet skips the picker next sign-in',
      () async {
        await signInEmployee('u1');
        expect(cubit.state.requiresSelection, isTrue);
        cubit.select('outlet_2');

        await localCache.clear(); // logout
        expect(localCache.getActiveOutletId(), isNull);

        await signInEmployee('u1');
        expect(cubit.state.requiresSelection, isFalse);
        expect(cubit.state.activeOutletId, 'outlet_2');
      },
    );

    test('the choice is per user and ignored once no longer allowed', () async {
      await signInEmployee('u1');
      cubit.select('outlet_2');
      await localCache.clear();

      await signInEmployee('u2');
      expect(cubit.state.requiresSelection, isTrue);

      await localCache.clear();
      await localCache.setCachedUser({'id': 'u1'});
      await localCache.setActiveStoreId('store_a');
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      await localCache.setAllowedOutletsForStore('store_a', [
        ...oneOutlet,
        {'id': 'outlet_3', 'displayName': 'Whitefield'},
      ]);
      cubit.adoptFromLogin(isOwner: false);
      expect(cubit.state.requiresSelection, isTrue);
    });
  });
}
