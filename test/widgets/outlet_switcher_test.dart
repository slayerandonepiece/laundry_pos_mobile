import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_switcher.dart';

/// Map-backed LocalCacheService, mirroring its store-scoped outlet keying.
/// Real Hive can't be used here: its disk writes never complete under
/// testWidgets' FakeAsync zone, and every later write/close queues behind them.
class FakeLocalCache extends LocalCacheService {

  @override
  Map<String, dynamic>? getCachedUser() => null;

  final Map<String, String> _rememberedOutlets = {};
  @override
  String? getRememberedOutlet(String userId, String storeId) =>
      _rememberedOutlets['$userId::$storeId'];
  @override
  Future<void> setRememberedOutlet(
    String userId,
    String storeId,
    String outletId,
  ) async => _rememberedOutlets['$userId::$storeId'] = outletId;

  final Map<String, dynamic> _memory = {};

  String _scoped(String base) => '$base::${getActiveStoreId() ?? 'none'}';

  @override
  String? getActiveStoreId() =>
      _memory[LocalCacheService.keyActiveStoreId] as String?;
  @override
  Future<void> setActiveStoreId(String storeId) async =>
      _memory[LocalCacheService.keyActiveStoreId] = storeId;

  @override
  Map<String, dynamic>? getCachedStoreDetails() =>
      _memory[LocalCacheService.keyCachedStoreDetails]
          as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> storeMap) async =>
      _memory[LocalCacheService.keyCachedStoreDetails] = storeMap;

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() =>
      _memory[_scoped(LocalCacheService.keyAllowedOutlets)]
          as List<Map<String, dynamic>>?;
  @override
  Future<void> setAllowedOutletsForStore(
    String storeId,
    List<Map<String, dynamic>> outlets,
  ) async => _memory['${LocalCacheService.keyAllowedOutlets}::$storeId'] =
      outlets;

  @override
  String? getActiveOutletId() =>
      _memory[_scoped(LocalCacheService.keyActiveOutletId)] as String?;
  @override
  Future<void> setActiveOutletId(String outletId) async =>
      _memory[_scoped(LocalCacheService.keyActiveOutletId)] = outletId;
  @override
  Future<void> clearActiveOutletId() async =>
      _memory.remove(_scoped(LocalCacheService.keyActiveOutletId));

  @override
  bool isAllOutletsScope() =>
      _memory[_scoped(LocalCacheService.keyAllOutletsScope)] as bool? ??
      false;
  @override
  Future<void> setAllOutletsScope(bool value) async =>
      _memory[_scoped(LocalCacheService.keyAllOutletsScope)] = value;
  @override
  Future<void> clearAllOutletsScope() async =>
      _memory.remove(_scoped(LocalCacheService.keyAllOutletsScope));
}

void main() {
  late FakeLocalCache localCache;
  late OutletScopeCubit cubit;

  final twoOutlets = [
    {
      'id': 'outlet_1',
      'outletCode': 'OBLRCHN01',
      'displayName': 'Chinnapanahalli',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'outlet_2',
      'outletCode': 'OBLRMTH02',
      'displayName': 'Marathahalli',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  setUp(() async {
    localCache = FakeLocalCache();
    cubit = OutletScopeCubit(localCache: localCache);
    await localCache.setActiveStoreId('store_a');
  });

  tearDown(() => cubit.close());

  Widget wrap(Widget child) => MaterialApp(
    home: BlocProvider<OutletScopeCubit>.value(
      value: cubit,
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'Hidden entirely for an employee with exactly one outlet — one outlet is not a choice',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', [
        twoOutlets.first,
      ]);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      cubit.adoptFromLogin(isOwner: false);

      await tester.pumpWidget(wrap(const OutletSwitcher()));

      expect(find.byType(OutletSwitcher), findsOneWidget);
      expect(find.text('Chinnapanahalli'), findsNothing);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
    },
  );

  testWidgets('Shows the active outlet name for an employee with 2 outlets', (
    tester,
  ) async {
    await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
    await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
    cubit.adoptFromLogin(isOwner: false);
    cubit.select('outlet_2');

    await tester.pumpWidget(wrap(const OutletSwitcher()));

    expect(find.text('Marathahalli'), findsOneWidget);
  });

  testWidgets(
    'Owner with one outlet still shows the switcher — All outlets is a real choice',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', [
        twoOutlets.first,
      ]);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.adoptFromLogin(isOwner: true);

      await tester.pumpWidget(
        wrap(const OutletSwitcher(showAllOutletsOption: true)),
      );

      expect(find.text('All outlets'), findsOneWidget);
    },
  );

  testWidgets(
    'Owner: tapping the pill opens a sheet, picking an outlet narrows the scope',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.adoptFromLogin(isOwner: true);

      await tester.pumpWidget(
        wrap(const OutletSwitcher(showAllOutletsOption: true)),
      );
      expect(find.text('All outlets'), findsOneWidget);

      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();

      expect(find.text('Switch outlet'), findsOneWidget);
      expect(find.text('Chinnapanahalli'), findsOneWidget);
      expect(find.text('Marathahalli'), findsOneWidget);

      await tester.tap(find.text('Marathahalli'));
      await tester.pumpAndSettle();

      expect(cubit.state.activeOutletId, 'outlet_2');
      expect(cubit.state.allOutlets, isFalse);
    },
  );
}
