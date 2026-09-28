import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/owner/presentation/expenses_screen.dart';
import 'package:myshop/features/shell/bloc/outlet_scope_cubit.dart';
import 'package:myshop/shared/widgets/outlet_title_switcher.dart';

import '../helpers/mock_dio.dart';

class _MockConnectivityService extends ConnectivityService {
  _MockConnectivityService({this.mockOffline = false}) : super.internal();
  bool mockOffline;

  @override
  bool get isOffline => mockOffline;

  @override
  Future<bool> checkIsOffline() async => mockOffline;
}

class _TestSecureStorage extends SecureStorageService {
  @override
  Future<String?> getToken() async => 'test_token';
}

class _RecordingApiClient implements ApiClient {
  final List<String> getUrls = [];
  final List<String> postUrls = [];
  final List<Map<String, String>?> postHeaders = [];
  final List<dynamic> postBodies = [];

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    getUrls.add(url);
    return <String, dynamic>{
      'todaySales': 1000,
      'todayCount': 1,
      'periodSales': 5000,
      'periodOrders': 5,
    };
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    postUrls.add(url);
    postHeaders.add(headers);
    postBodies.add(body);
    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    return <String, dynamic>{
      'id': 'exp-server-1',
      'title': map['title'] ?? 'Item',
      'category': map['category'] ?? 'Operations',
      'amount': map['amount'] ?? 1000,
      'due': map['due'] ?? '2026-09-26',
      'monthly': map['monthly'] ?? false,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingOwnerBloc extends Bloc<OwnerEvent, OwnerState>
    implements OwnerBloc {
  final List<OwnerEvent> events = [];

  _TrackingOwnerBloc([OwnerState? initial])
    : super(initial ?? OwnerState(expenses: const [])) {
    on<OwnerEvent>((event, emit) {
      events.add(event);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalCacheService localCache;
  late _MockConnectivityService mockConnectivity;

  final outlets = [
    {
      'id': 'o1',
      'outletCode': 'O01',
      'displayName': 'Indiranagar',
      'isDefault': true,
      'status': 'ACTIVE',
    },
    {
      'id': 'o2',
      'outletCode': 'O02',
      'displayName': 'Koramangala',
      'isDefault': false,
      'status': 'ACTIVE',
    },
  ];

  group('Expenses & Dashboard Outlet Scope Unit Tests', () {
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('expenses_outlet_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalCacheService.boxName);
      localCache = LocalCacheService();
    });

    setUp(() async {
      await localCache.clear();
      await localCache.setActiveStoreId('store_1');
      await localCache.setCachedStoreDetails({'role': 'OWNER'});
      await localCache.setAllowedOutletsForStore('store_1', outlets);

      mockConnectivity = _MockConnectivityService(mockOffline: false);
      ConnectivityService.instance = mockConnectivity;
    });

    tearDown(() {
      ConnectivityService.instance = ConnectivityService.internal();
    });

    tearDownAll(() async {
      if (Hive.isBoxOpen(LocalCacheService.boxName)) {
        await Hive.box(LocalCacheService.boxName).close();
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'expenses cache keys differ per outlet and all-outlets scope',
      () async {
        // Outlet o1
        await localCache.setAllOutletsScope(false);
        await localCache.setActiveOutletId('o1');
        await localCache.setCachedExpenses([
          {'id': 'e-o1', 'title': 'Rent O1', 'amount': 1000},
        ]);

        // Outlet o2
        await localCache.setActiveOutletId('o2');
        expect(localCache.getCachedExpenses(), isNull);
        await localCache.setCachedExpenses([
          {'id': 'e-o2', 'title': 'Rent O2', 'amount': 2000},
        ]);

        // All-outlets scope
        await localCache.clearActiveOutletId();
        await localCache.setAllOutletsScope(true);
        expect(localCache.getCachedExpenses(), isNull);
        await localCache.setCachedExpenses([
          {'id': 'e-all', 'title': 'Org Wide', 'amount': 3000},
        ]);

        // Verify each scope reads back its own isolated list
        expect(localCache.getCachedExpenses()!.single['id'], 'e-all');

        await localCache.setAllOutletsScope(false);
        await localCache.setActiveOutletId('o1');
        expect(localCache.getCachedExpenses()!.single['id'], 'e-o1');

        await localCache.setActiveOutletId('o2');
        expect(localCache.getCachedExpenses()!.single['id'], 'e-o2');
      },
    );

    test('queued create_expense stores outletId in outlet scope and null in all-outlets scope', () async {
      mockConnectivity.mockOffline = true;
      final apiClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: apiClient,
        localCache: localCache,
      );

      // 1. Specific outlet o1
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');

      await repo.createExpense(
        title: 'Detergent O1',
        category: 'Supplies',
        amount: 25000,
        due: '2026-09-26',
      );

      // 2. All-outlets scope
      await localCache.clearActiveOutletId();
      await localCache.setAllOutletsScope(true);

      await repo.createExpense(
        title: 'Company Insurance',
        category: 'Operations',
        amount: 90000,
        due: '2026-09-26',
      );

      final queue = localCache.getPendingOwnerActionsQueue();
      expect(queue.length, 2);

      expect(queue[0]['type'], 'create_expense');
      expect(queue[0].containsKey('outletId'), isTrue);
      expect(queue[0]['outletId'], 'o1');

      expect(queue[1]['type'], 'create_expense');
      expect(queue[1].containsKey('outletId'), isTrue);
      expect(queue[1]['outletId'], isNull);
    });

    test('replay sends outlet header for outlet-scoped action, and kNoOutletHeader (omitted on wire) for org-wide action', () async {
      // First verify the headers passed to ApiClient.post
      final recordingClient = _RecordingApiClient();
      final repoWithRecording = OwnerRepository(
        apiClient: recordingClient,
        localCache: localCache,
      );

      await localCache.setPendingOwnerActionsQueue([
        {
          'clientActionId': 'act_o1',
          'type': 'create_expense',
          'outletId': 'o1',
          'payload': {
            'localId': 'LOCAL-1',
            'title': 'Outlet 1 Bill',
            'category': 'Utilities',
            'amount': 12000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
        {
          'clientActionId': 'act_org',
          'type': 'create_expense',
          'outletId': null,
          'payload': {
            'localId': 'LOCAL-2',
            'title': 'Org Bill',
            'category': 'Operations',
            'amount': 50000,
            'due': '2026-09-26',
            'monthly': true,
          },
        },
        {
          'clientActionId': 'act_legacy',
          'type': 'create_expense',
          'payload': {
            'localId': 'LOCAL-3',
            'title': 'Legacy Bill',
            'category': 'Other',
            'amount': 8000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
      ]);

      mockConnectivity.mockOffline = false;
      final ok = await repoWithRecording.processPendingOwnerActions();
      expect(ok, isTrue);
      expect(recordingClient.postHeaders.length, 3);
      expect(recordingClient.postHeaders[0], {'X-Outlet-Id': 'o1'});
      expect(recordingClient.postHeaders[1], {'X-Outlet-Id': kNoOutletHeader});
      expect(recordingClient.postHeaders[2], isNull);

      // Now verify wire headers through Dio + AuthInterceptor even when activeOutletId is 'o2'
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o2');

      final wireHeaders = <Map<String, dynamic>>[];
      final mockDio = createMockDio((options) async {
        wireHeaders.add(Map<String, dynamic>.from(options.headers));
        return mockJsonResponse({
          'id': 'exp-wire-${wireHeaders.length}',
          'title': 'Bill',
          'category': 'Operations',
          'amount': 1000,
          'due': '2026-09-26',
          'monthly': false,
        });
      });

      final dioApiClient = ApiClient(
        dio: mockDio,
        secureStorage: _TestSecureStorage(),
        localCache: localCache,
      );
      final repoWithDio = OwnerRepository(
        apiClient: dioApiClient,
        localCache: localCache,
      );

      await localCache.setPendingOwnerActionsQueue([
        {
          'clientActionId': 'wire_o1',
          'type': 'create_expense',
          'outletId': 'o1',
          'payload': {
            'localId': 'LOCAL-10',
            'title': 'Outlet 1 Bill',
            'category': 'Utilities',
            'amount': 12000,
            'due': '2026-09-26',
            'monthly': false,
          },
        },
        {
          'clientActionId': 'wire_org',
          'type': 'create_expense',
          'outletId': null,
          'payload': {
            'localId': 'LOCAL-11',
            'title': 'Org Bill',
            'category': 'Operations',
            'amount': 50000,
            'due': '2026-09-26',
            'monthly': true,
          },
        },
      ]);

      final wireOk = await repoWithDio.processPendingOwnerActions();
      expect(wireOk, isTrue);
      expect(wireHeaders.length, 2);
      // First action had outletId: 'o1' -> wire has X-Outlet-Id: o1 (not active o2)
      expect(wireHeaders[0]['X-Outlet-Id'], 'o1');
      // Second action had outletId: null -> kNoOutletHeader stripped by AuthInterceptor -> omitted on wire!
      expect(wireHeaders[1].containsKey('X-Outlet-Id'), isFalse);
    });

    test('dashboard GET URL contains outletId=o1 in outlet scope and no outletId in all-outlets scope', () async {
      final recordingClient = _RecordingApiClient();
      final repo = OwnerRepository(
        apiClient: recordingClient,
        localCache: localCache,
      );

      // 1. Outlet scope (o1)
      await localCache.setAllOutletsScope(false);
      await localCache.setActiveOutletId('o1');
      await repo.getDashboardMetrics(from: '2026-09-01', to: '2026-09-26');

      expect(recordingClient.getUrls.length, 1);
      final outletUri = Uri.parse(recordingClient.getUrls.first);
      expect(outletUri.queryParameters['outletId'], 'o1');
      expect(outletUri.queryParameters['from'], '2026-09-01');
      expect(outletUri.queryParameters['to'], '2026-09-26');

      // 2. All-outlets scope
      recordingClient.getUrls.clear();
      await localCache.clearActiveOutletId();
      await localCache.setAllOutletsScope(true);
      await repo.getDashboardMetrics(from: '2026-09-01', to: '2026-09-26');

      expect(recordingClient.getUrls.length, 1);
      final allOutletsUri = Uri.parse(recordingClient.getUrls.first);
      expect(allOutletsUri.queryParameters.containsKey('outletId'), isFalse);
    });
  });

  group('Expenses & Dashboard Outlet Scope Widget Tests', () {
    testWidgets(
      'AddExpenseScreen shows organization-wide hint in all-outlets scope and outlet displayName hint in specific outlet scope',
      (tester) async {
        final widgetCache = _WidgetFakeLocalCache(allowedOutlets: outlets);
        final ownerBloc = _TrackingOwnerBloc();
        final outletCubit = OutletScopeCubit(localCache: widgetCache)
          ..adoptFromLogin(isOwner: true);
        addTearDown(ownerBloc.close);
        addTearDown(outletCubit.close);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<OwnerBloc>.value(value: ownerBloc),
              BlocProvider<OutletScopeCubit>.value(value: outletCubit),
            ],
            child: const MaterialApp(home: ExpensesScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // OutletTitleSwitcher is mounted in ExpensesScreen header
        expect(find.byType(OutletTitleSwitcher), findsOneWidget);
        expect(find.text('All outlets'), findsOneWidget);

        // Open AddExpenseScreen in All-outlets scope
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.byType(AddExpenseScreen), findsOneWidget);
        expect(
          find.text('This expense will be recorded as organization-wide.'),
          findsOneWidget,
        );

        // Pop back to ExpensesScreen
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Switch scope to specific outlet 'o1' (Indiranagar)
        final loadCountBefore = ownerBloc.events
            .whereType<LoadExpensesEvent>()
            .length;
        outletCubit.select('o1');
        await tester.pumpAndSettle();

        // BlocListener on ExpensesScreen dispatches LoadExpensesEvent on scope switch
        final loadCountAfter = ownerBloc.events
            .whereType<LoadExpensesEvent>()
            .length;
        expect(loadCountAfter, greaterThan(loadCountBefore));
        expect(find.text('Indiranagar'), findsOneWidget);

        // Open AddExpenseScreen in specific outlet scope
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.byType(AddExpenseScreen), findsOneWidget);
        expect(
          find.text('This expense will be recorded against Indiranagar.'),
          findsOneWidget,
        );
        expect(
          find.text('This expense will be recorded as organization-wide.'),
          findsNothing,
        );
      },
    );
  });
}

class _WidgetFakeLocalCache extends LocalCacheService {
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

  final List<Map<String, dynamic>> allowedOutlets;
  String? activeOutletId;
  bool allOutletsScope = true;

  _WidgetFakeLocalCache({required this.allowedOutlets});

  @override
  Map<String, dynamic>? getCachedStoreDetails() => const {'role': 'OWNER'};

  @override
  List<Map<String, dynamic>>? getAllowedOutlets() => allowedOutlets;

  @override
  String? getActiveOutletId() => activeOutletId;

  @override
  Future<void> setActiveOutletId(String outletId) async {
    activeOutletId = outletId;
  }

  @override
  Future<void> clearActiveOutletId() async {
    activeOutletId = null;
  }

  @override
  bool isAllOutletsScope() => allOutletsScope;

  @override
  Future<void> setAllOutletsScope(bool allOutlets) async {
    allOutletsScope = allOutlets;
  }

  @override
  Future<void> clearAllOutletsScope() async {
    allOutletsScope = false;
  }

  @override
  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) => true;
}
