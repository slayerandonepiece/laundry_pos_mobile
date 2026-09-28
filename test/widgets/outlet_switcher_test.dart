import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';

class _MockConnectivityService extends ConnectivityService {
  _MockConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

/// Map-backed LocalCacheService, mirroring its store-scoped outlet keying.
class FakeLocalCache extends LocalCacheService {
  final Set<String> cachedOutletIds = {'outlet_1', 'outlet_2', '__all__'};

  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) {
    if (allOutlets) return cachedOutletIds.contains('__all__');
    return outletId != null && cachedOutletIds.contains(outletId);
  }

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
      _memory[LocalCacheService.keyCachedStoreDetails] as Map<String, dynamic>?;
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
  ) async =>
      _memory['${LocalCacheService.keyAllowedOutlets}::$storeId'] = outlets;

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
      _memory[_scoped(LocalCacheService.keyAllOutletsScope)] as bool? ?? false;
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
  late _MockConnectivityService mockConnectivity;

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
    mockConnectivity = _MockConnectivityService(mockOffline: false);
    ConnectivityService.instance = mockConnectivity;
  });

  tearDown(() {
    ConnectivityService.instance = ConnectivityService.internal();
    cubit.close();
  });

  Widget wrap(Widget child) => MaterialApp(
    home: BlocProvider<OutletScopeCubit>.value(
      value: cubit,
      child: Scaffold(
        appBar: AppBar(title: child),
        body: const SizedBox.shrink(),
      ),
    ),
  );

  testWidgets(
    'Single-outlet employee (allowed.length <= 1): shows plain title without chevron and tapping does not open menu',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', [twoOutlets.first]);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      cubit.adoptFromLogin(isOwner: false);

      await tester.pumpWidget(
        wrap(
          const OutletTitleSwitcher(
            screenLabel: 'Orders',
            showAllOutletsOption: false,
          ),
        ),
      );

      expect(find.byType(OutletTitleSwitcher), findsOneWidget);
      expect(find.text('ORDERS'), findsOneWidget);
      expect(find.text('Chinnapanahalli'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

      await tester.tap(find.text('Chinnapanahalli'));
      await tester.pumpAndSettle();

      expect(find.text('SWITCH OUTLET'), findsNothing);
    },
  );

  testWidgets(
    'Multi-outlet owner: shows All outlets with chevron, opens menu with check mark, and selecting an outlet updates scope and title',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.adoptFromLogin(isOwner: true);

      await tester.pumpWidget(
        wrap(
          const OutletTitleSwitcher(
            screenLabel: 'Overview',
            showAllOutletsOption: true,
          ),
        ),
      );

      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(find.text('All outlets'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      expect(find.text('SWITCH OUTLET'), findsOneWidget);
      expect(find.text('Chinnapanahalli'), findsOneWidget);
      expect(find.text('Marathahalli'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.text('Marathahalli'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(cubit.state.activeOutletId, 'outlet_2');
      expect(cubit.state.allOutlets, isFalse);
      expect(find.text('Marathahalli'), findsOneWidget);
    },
  );

  testWidgets(
    'Multi-outlet employee: shows chevron and both outlets in menu without All outlets row',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'EMPLOYEE'});
      cubit.hydrate();

      await tester.pumpWidget(
        wrap(
          const OutletTitleSwitcher(
            screenLabel: 'Orders',
            showAllOutletsOption: false,
          ),
        ),
      );

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      await tester.tap(find.byType(OutletTitleSwitcher));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Chinnapanahalli'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Marathahalli'),
        ),
        findsOneWidget,
      );
      expect(find.text('All outlets'), findsNothing);
    },
  );

  testWidgets(
    'Menu rows show On this phone for cached outlet and Not on this phone yet for uncached outlet',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.adoptFromLogin(isOwner: true);

      localCache.cachedOutletIds
        ..clear()
        ..addAll(['__all__', 'outlet_1']);

      await tester.pumpWidget(
        wrap(
          const OutletTitleSwitcher(
            screenLabel: 'Orders',
            showAllOutletsOption: true,
          ),
        ),
      );

      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();

      final outlet1Item = find.ancestor(
        of: find.text('Chinnapanahalli'),
        matching: find.byType(PopupMenuItem<String>),
      );
      final outlet2Item = find.ancestor(
        of: find.text('Marathahalli'),
        matching: find.byType(PopupMenuItem<String>),
      );

      expect(
        find.descendant(
          of: outlet1Item,
          matching: find.textContaining('On this phone'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: outlet2Item,
          matching: find.text('Not on this phone yet'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Offline guard: tapping uncached outlet shows SnackBar and does not switch; tapping cached outlet switches normally',
    (tester) async {
      await localCache.setAllowedOutletsForStore('store_a', twoOutlets);
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      cubit.adoptFromLogin(isOwner: true);

      // outlet_1 is cached, outlet_2 is NOT cached
      localCache.cachedOutletIds
        ..clear()
        ..addAll(['__all__', 'outlet_1']);
      mockConnectivity.mockOffline = true;

      await tester.pumpWidget(
        wrap(
          const OutletTitleSwitcher(
            screenLabel: 'Dashboard',
            showAllOutletsOption: true,
          ),
        ),
      );

      // 1. Tap uncached outlet_2 (Marathahalli) while offline -> blocked with SnackBar
      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
      await tester.tap(find.text('Marathahalli'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Marathahalli isn't on this phone yet. Connect to the internet to open it.",
        ),
        findsOneWidget,
      );
      expect(cubit.state.allOutlets, isTrue);
      expect(cubit.state.activeOutletId, isNull);

      // 2. Tap cached outlet_1 (Chinnapanahalli) while offline -> switches normally
      await tester.tap(find.text('All outlets'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chinnapanahalli'));
      await tester.pumpAndSettle();

      expect(cubit.state.activeOutletId, 'outlet_1');
      expect(cubit.state.allOutlets, isFalse);
      expect(find.text('Chinnapanahalli'), findsOneWidget);
    },
  );
}
