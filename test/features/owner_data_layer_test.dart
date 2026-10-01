import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/bloc/owner_state.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/models/staff_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

class _Connectivity extends ConnectivityService {
  _Connectivity() : super.internal();
  bool offline = false;

  @override
  bool get isOffline => offline;

  @override
  Future<bool> checkIsOffline() async => offline;
}

typedef _Call = ({
  String method,
  String url,
  Map<String, String>? headers,
  dynamic body,
});

/// Every request goes through [handler], which may wait, answer or throw.
class _Api implements ApiClient {
  final List<_Call> calls = [];
  Future<dynamic> Function(String method, String url, dynamic body)? handler;

  Future<dynamic> _do(
    String method,
    String url,
    Map<String, String>? headers,
    dynamic body,
  ) {
    calls.add((method: method, url: url, headers: headers, body: body));
    return handler!(method, url, body);
  }

  Iterable<_Call> of(String method) => calls.where((c) => c.method == method);

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) => _do('GET', url, headers, null);

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) => _do('POST', url, headers, body);

  @override
  Future<dynamic> put(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) => _do('PUT', url, headers, body);

  @override
  Future<dynamic> patch(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) => _do('PATCH', url, headers, body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A sync engine that never runs, so queued actions stay queued until a test
/// drains them itself.
class _IdleEngine extends SyncEngine {
  _IdleEngine() : super.internal();

  @override
  Future<void> trigger() => Future<void>.value();
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalCacheService cache;
  late _Connectivity connectivity;
  late _Api api;
  late OwnerRepository repo;
  late SyncEngine savedEngine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('owner_data_layer_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    cache = LocalCacheService();
    await cache.setActiveStoreId('store_1');
    await cache.setActiveOutletId('o1');
    connectivity = _Connectivity();
    ConnectivityService.instance = connectivity;
    savedEngine = SyncEngine.instance;
    SyncEngine.instance = _IdleEngine();
    SyncManager.instance.completeSync(force: true);
    OwnerRepository.lastWriteQueued = false;
    api = _Api();
    repo = OwnerRepository(apiClient: api, localCache: cache);
  });

  tearDown(() async {
    SyncEngine.instance = savedEngine;
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  final metricsJson = {'todaySales': 35000, 'periodSales': 120000};

  group('H1 dashboard cache fallback only for the default period', () {
    final custom = (from: '2026-09-01', to: '2026-09-10', g: 'day');

    test('a failed non-default request rethrows instead of serving the default figures', () async {
      await cache.setCachedDashboardMetrics(metricsJson);
      api.handler = (_, _, _) async => throw Exception('boom');

      await expectLater(
        repo.getDashboardMetrics(
          from: custom.from,
          to: custom.to,
          granularity: custom.g,
        ),
        throwsException,
      );
    });

    test(
      'an offline non-default request throws rather than reading the cache',
      () async {
        await cache.setCachedDashboardMetrics(metricsJson);
        connectivity.offline = true;

        await expectLater(
          repo.getDashboardMetrics(
            from: custom.from,
            to: custom.to,
            granularity: custom.g,
          ),
          throwsException,
        );
        expect(api.calls, isEmpty);
      },
    );

    test('a failed default request still falls back to the cache', () async {
      await cache.setCachedDashboardMetrics(metricsJson);
      api.handler = (_, _, _) async => throw Exception('boom');

      final m = await repo.getDefaultDashboardMetrics();
      expect(m.todaySales, 35000);
    });

    test('a bare request asks for the daily month-to-date period and caches it as the default', () async {
      api.handler = (_, _, _) async => metricsJson;

      await repo.getDashboardMetrics();

      final uri = Uri.parse(api.calls.single.url);
      final now = DateTime.now();
      expect(uri.queryParameters['granularity'], 'day');
      expect(uri.queryParameters['to'], _iso(now));
      expect(
        uri.queryParameters['from'],
        _iso(DateTime(now.year, now.month, 1)),
      );
      expect(cache.getCachedDashboardMetrics()?['todaySales'], 35000);
    });
  });

  group('H2 cache writes go to the scope the request was made for', () {
    test(
      'dashboard reply lands in the outlet it was asked for after a switch',
      () async {
        final gate = Completer<dynamic>();
        api.handler = (_, _, _) => gate.future;

        final f = repo.getDefaultDashboardMetrics();
        await pumpEventQueue();
        await cache.setActiveOutletId('o2'); // owner switches mid-request
        gate.complete(metricsJson);
        await f;

        expect(
          cache.getCachedDashboardMetricsForScope('o1')?['todaySales'],
          35000,
        );
        expect(cache.getCachedDashboardMetricsForScope('o2'), isNull);
      },
    );

    test(
      'a reply that arrives after the store changed is not cached at all',
      () async {
        final gate = Completer<dynamic>();
        api.handler = (_, _, _) => gate.future;

        final f = repo.getDefaultDashboardMetrics();
        await pumpEventQueue();
        await cache.setActiveStoreId('store_2');
        gate.complete(metricsJson);
        await f;

        expect(cache.getCachedDashboardMetricsForScope('o1'), isNull);
        await cache.setActiveStoreId('store_1');
        expect(cache.getCachedDashboardMetricsForScope('o1'), isNull);
      },
    );

    test('listExpenses reply lands in the outlet it was asked for', () async {
      final gate = Completer<dynamic>();
      api.handler = (_, _, _) => gate.future;

      final f = repo.listExpenses();
      await pumpEventQueue();
      await cache.setActiveOutletId('o2');
      gate.complete([
        {
          'id': 'e1',
          'title': 'Soap',
          'category': 'Ops',
          'amount': 5,
          'due': 'x',
        },
      ]);
      await f;

      expect(cache.getCachedExpensesForScope('o1'), hasLength(1));
      expect(cache.getCachedExpensesForScope('o2'), isNull);
    });

    test(
      'createExpense stores the new expense under the outlet it was created in',
      () async {
        final gate = Completer<dynamic>();
        api.handler = (_, _, _) => gate.future;

        final f = repo.createExpense(
          title: 'Soap',
          category: 'Ops',
          amount: 5,
          due: '2026-09-30',
        );
        await pumpEventQueue();
        await cache.setActiveOutletId('o2');
        gate.complete({
          'id': 'e1',
          'title': 'Soap',
          'category': 'Ops',
          'amount': 5,
          'due': '2026-09-30',
        });
        await f;

        expect(cache.getCachedExpensesForScope('o1'), hasLength(1));
        expect(cache.getCachedExpensesForScope('o2'), isNull);
      },
    );

    test(
      'markExpensePaid marks the row in the outlet it was made in',
      () async {
        await cache.setCachedExpensesForScope('o1', [
          {
            'id': 'e1',
            'title': 'Soap',
            'category': 'Ops',
            'amount': 5,
            'due': 'x',
          },
        ]);
        final gate = Completer<dynamic>();
        api.handler = (_, _, _) => gate.future;

        final f = repo.markExpensePaid('e1');
        await pumpEventQueue();
        await cache.setActiveOutletId('o2');
        gate.complete({});
        await f;

        expect(
          cache.getCachedExpensesForScope('o1')!.single['paid'],
          isNotNull,
        );
      },
    );

    test(
      'a queued mark_expense_paid records its outlet and replays under it',
      () async {
        await cache.setCachedExpensesForScope('o1', [
          {
            'id': 'e1',
            'title': 'Soap',
            'category': 'Ops',
            'amount': 5,
            'due': 'x',
          },
        ]);
        connectivity.offline = true;
        await repo.markExpensePaid('e1');
        final queued = cache.getPendingOwnerActionsQueue().single;
        expect(queued['outletId'], 'o1');

        // Later, online, with another outlet selected.
        connectivity.offline = false;
        await cache.setActiveOutletId('o2');
        api.handler = (_, _, _) async => {};
        await repo.processPendingOwnerActions();

        final post = api.of('POST').single;
        expect(post.headers, {'X-Outlet-Id': 'o1'});
        expect(
          cache.getCachedExpensesForScope('o1')!.single['paid'],
          isNotNull,
        );
        expect(cache.getCachedExpensesForScope('o2'), isNull);
      },
    );

    test('a queued create_expense made in the all-outlets view replays with the no-outlet header', () async {
      await cache.clearActiveOutletId();
      await cache.setAllOutletsScope(true);
      connectivity.offline = true;
      await repo.createExpense(
        title: 'Rent',
        category: 'Ops',
        amount: 9,
        due: '2026-09-30',
      );
      expect(cache.getPendingOwnerActionsQueue().single['outletId'], isNull);

      connectivity.offline = false;
      await cache.setAllOutletsScope(false);
      await cache.setActiveOutletId('o2');
      api.handler = (_, _, _) async => {
        'id': 'srv1',
        'title': 'Rent',
        'category': 'Ops',
        'amount': 9,
        'due': '2026-09-30',
      };
      await repo.processPendingOwnerActions();

      expect(api.of('POST').single.headers, {'X-Outlet-Id': kNoOutletHeader});
      expect(
        cache.getCachedExpensesForScope(LocalCacheService.allScope),
        hasLength(1),
      );
      expect(cache.getCachedExpensesForScope('o2'), isNull);
    });
  });

  group('H3 replay only spends retry budget on real rejections', () {
    Future<void> queueTwoExpenses() async {
      connectivity.offline = true;
      for (final t in ['A', 'B']) {
        await repo.createExpense(
          title: t,
          category: 'Ops',
          amount: 1,
          due: '2026-09-30',
        );
      }
      connectivity.offline = false;
    }

    final notTheActionsFault = <String, Object>{
      '401': AuthException(code: 'UNAUTHENTICATED', statusCode: 401),
      '403': AuthException(code: 'FORBIDDEN', statusCode: 403),
      'timeout': TimeoutException('slow'),
      '503': ApiException('down', statusCode: 503),
      '500': ApiException('oops', statusCode: 500),
      'no status (connection)': ApiException('no route'),
      '429': RateLimitException('slow down'),
      'unreadable reply': Exception('Unexpected expense response'),
    };

    for (final entry in notTheActionsFault.entries) {
      test('${entry.key} stops the drain and leaves failCount alone', () async {
        await queueTwoExpenses();
        api.handler = (_, _, _) async => throw entry.value;

        for (var i = 0; i < 4; i++) {
          final ok = await repo.processPendingOwnerActions();
          expect(ok, isFalse);
        }

        final queue = cache.getPendingOwnerActionsQueue();
        expect(queue, hasLength(2));
        expect(queue.map((a) => a['failCount'] ?? 0), everyElement(0));
        expect(cache.getDeadLetterOwnerActionsQueue(), isEmpty);
        // Stopped at the first action each cycle: 4 cycles, 4 calls.
        expect(api.calls, hasLength(4));
      });
    }

    test('a 422 rejection counts, keeps the server message, and dead-letters after 3', () async {
      connectivity.offline = true;
      await repo.createExpense(
        title: 'Bad',
        category: 'Ops',
        amount: 1,
        due: '2026-09-30',
      );
      connectivity.offline = false;
      api.handler = (_, _, _) async =>
          throw ApiException('Amount must be positive', statusCode: 422);

      await repo.processPendingOwnerActions();
      var q = cache.getPendingOwnerActionsQueue().single;
      expect(q['failCount'], 1);
      expect(q['lastError'], 'Amount must be positive');

      await repo.processPendingOwnerActions();
      await repo.processPendingOwnerActions();
      expect(cache.getPendingOwnerActionsQueue(), isEmpty);
      expect(cache.getDeadLetterOwnerActionsQueue(), hasLength(1));
    });

    test('after the 401 clears, the untouched actions still drain', () async {
      await queueTwoExpenses();
      api.handler = (_, _, _) async =>
          throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401);
      await repo.processPendingOwnerActions();

      var n = 0;
      api.handler = (_, _, _) async => {
        'id': 'srv${n++}',
        'title': 'x',
        'category': 'Ops',
        'amount': 1,
        'due': '2026-09-30',
      };
      final ok = await repo.processPendingOwnerActions();
      expect(ok, isTrue);
      expect(cache.getPendingOwnerActionsQueue(), isEmpty);
    });
  });

  group('H5 staff changes never guess', () {
    Map<String, dynamic> row({bool active = true}) => {
      'id': 'e9',
      'name': 'Nia',
      'phone': '9000000009',
      'active': active,
    };

    test(
      'toggle with the row missing from the cache reads the server row first',
      () async {
        api.handler = (m, u, b) async => m == 'GET' ? [row()] : {};

        await repo.toggleStaffActive('e9');

        expect(api.of('PUT').single.body, {'active': false});
      },
    );

    test('toggle refuses when the employee cannot be found anywhere', () async {
      api.handler = (m, u, b) async => m == 'GET' ? [] : {};

      await expectLater(
        repo.toggleStaffActive('e9'),
        throwsA(isA<OwnerRefusedException>()),
      );
      expect(api.of('PUT'), isEmpty);
    });

    test(
      'toggle offline with nothing cached refuses and queues nothing',
      () async {
        connectivity.offline = true;
        await expectLater(
          repo.toggleStaffActive('e9'),
          throwsA(isA<OwnerRefusedException>()),
        );
        expect(cache.getPendingOwnerActionsQueue(), isEmpty);
      },
    );

    test(
      'offline active replay cannot overwrite a newer name or phone',
      () async {
        await cache.setCachedStaff([row()]);
        connectivity.offline = true;
        await repo.toggleStaffActive('e9');
        final queued = cache.getPendingOwnerActionsQueue().single;
        expect(queued['payload'], {'employeeId': 'e9', 'active': false});

        connectivity.offline = false;
        api.handler = (m, u, b) async => {};
        expect(await repo.processPendingOwnerActions(), isTrue);
        expect(api.of('PUT').single.body, {'active': false});
      },
    );

    test('updateStaff with an uncached row keeps a deactivated employee deactivated', () async {
      api.handler = (m, u, b) async =>
          m == 'GET' ? [row(active: false)] : row(active: false);

      await repo.updateStaff(
        employeeId: 'e9',
        name: 'Nia R',
        phone: '9000000009',
      );

      expect(api.of('PUT').single.body['active'], false);
    });

    test(
      'updateStaff refuses when the current status cannot be determined',
      () async {
        api.handler = (m, u, b) async => m == 'GET' ? [] : {};

        await expectLater(
          repo.updateStaff(
            employeeId: 'e9',
            name: 'Nia R',
            phone: '9000000009',
          ),
          throwsA(isA<OwnerRefusedException>()),
        );
        expect(api.of('PUT'), isEmpty);
      },
    );

    test('updateStaff never sends a blank name or phone', () async {
      await cache.setCachedStaff([row()]);
      api.handler = (m, u, b) async => row();

      await expectLater(
        repo.updateStaff(employeeId: 'e9', name: ' ', phone: ''),
        throwsA(isA<ValidationException>()),
      );
      expect(api.of('PUT'), isEmpty);
    });

    test('an offline edit queues no status; the replay reads the server\'s, so a web deactivation sticks', () async {
      await cache.setCachedStaff([row(active: true)]); // stale: web deactivated
      connectivity.offline = true;
      await repo.updateStaff(
        employeeId: 'e9',
        name: 'Nia R',
        phone: '9000000009',
      );
      final payload =
          cache.getPendingOwnerActionsQueue().single['payload'] as Map;
      expect(payload.containsKey('active'), isFalse);

      connectivity.offline = false;
      api.handler = (m, u, b) async =>
          m == 'GET' ? [row(active: false)] : row(active: false);
      await repo.processPendingOwnerActions();

      expect(api.of('PUT').single.body['active'], false);
    });

    test('an offline edit of an uncached employee is refused', () async {
      connectivity.offline = true;
      await expectLater(
        repo.updateStaff(employeeId: 'e9', name: 'Nia R', phone: '9000000009'),
        throwsA(isA<OwnerRefusedException>()),
      );
      expect(cache.getPendingOwnerActionsQueue(), isEmpty);
    });
  });

  group('H7 an unexpected reply is an error, never empty data', () {
    const html = '<html>Log in to the Wi-Fi</html>';

    test('staff: throws, and nothing is cached', () async {
      api.handler = (_, _, _) async => html;
      await expectLater(repo.listStaff(), throwsException);
      expect(cache.getCachedStaff(), isNull);
    });

    test(
      'staff with a cache: served from the cache, cache untouched',
      () async {
        await cache.setCachedStaff([
          {'id': 'e1', 'name': 'A', 'phone': '1', 'active': true},
        ]);
        api.handler = (_, _, _) async => html;
        final staff = await repo.listStaff();
        expect(staff.single.id, 'e1');
        expect(cache.getCachedStaff(), hasLength(1));
      },
    );

    test('expenses, payment methods and dashboard all throw', () async {
      api.handler = (_, _, _) async => html;
      await expectLater(repo.listExpenses(), throwsException);
      await expectLater(repo.listPaymentMethods(), throwsException);
      await expectLater(repo.getDefaultDashboardMetrics(), throwsException);
      expect(cache.getCachedExpenses(), isNull);
      expect(cache.getCachedPaymentMethods(), isNull);
      expect(cache.getCachedDashboardMetrics(), isNull);
    });
  });

  group('read failures preserve access errors and settle the banner', () {
    for (final status in [401, 403]) {
      test('staff $status propagates even with cached staff', () async {
        await cache.setCachedStaff([
          {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
        ]);
        api.handler = (_, _, _) async => throw AuthException(
          code: status == 401 ? 'UNAUTHENTICATED' : 'FORBIDDEN',
          statusCode: status,
        );

        await expectLater(
          repo.listStaff(),
          throwsA(
            isA<AuthException>().having((e) => e.statusCode, 'status', status),
          ),
        );
      });
    }

    test('network failure still returns cached staff', () async {
      await cache.setCachedStaff([
        {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
      ]);
      api.handler = (_, _, _) async => throw ApiException('network');
      expect((await repo.listStaff()).single.name, 'Nia');
    });

    test('first read throwing leaves no Fetching state', () async {
      api.handler = (_, _, _) async => throw ApiException('network');
      await expectLater(repo.listStaff(), throwsA(isA<ApiException>()));
      expect(SyncManager.instance.value.isSyncing, isFalse);
    });
  });

  group('M5 connection-level failures queue like offline', () {
    test(
      'createExpense on Wi-Fi without internet is queued, not failed',
      () async {
        api.handler = (_, _, _) async => throw ApiException('Connection error');

        await repo.createExpense(
          title: 'Soap',
          category: 'Ops',
          amount: 5,
          due: '2026-09-30',
        );

        expect(OwnerRepository.lastWriteQueued, isTrue);
        expect(cache.getPendingOwnerActionsQueue(), hasLength(1));
      },
    );

    test('a timeout queues a payment method toggle', () async {
      api.handler = (_, _, _) async => throw TimeoutException('slow');

      await repo.togglePaymentMethod('pm1', false);

      expect(OwnerRepository.lastWriteQueued, isTrue);
      expect(
        cache.getPendingOwnerActionsQueue().single['type'],
        'toggle_payment_method',
      );
    });

    test('a 500 is reported, not queued', () async {
      api.handler = (_, _, _) async =>
          throw ApiException('down', statusCode: 500);

      await expectLater(
        repo.createExpense(
          title: 'Soap',
          category: 'Ops',
          amount: 5,
          due: '2026-09-30',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(OwnerRepository.lastWriteQueued, isFalse);
      expect(cache.getPendingOwnerActionsQueue(), isEmpty);
    });

    test('a 422 is reported, not queued', () async {
      api.handler = (_, _, _) async =>
          throw ApiException('bad', statusCode: 422);
      await expectLater(
        repo.updateStoreProfile(
          storeName: 's',
          address: 'a',
          phone: 'p',
          name: 'n',
          email: 'e',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(cache.getPendingOwnerActionsQueue(), isEmpty);
    });
  });

  group('staff payloads', () {
    test(
      'a queued create_staff replays with its outlets and default',
      () async {
        await cache.enqueueOwnerAction({
          'clientActionId': 'a1',
          'type': 'create_staff',
          'payload': {
            'localId': 'LOCAL-1',
            'name': 'Sam',
            'phone': '9000000001',
            'password': 'password123',
            'outlets': ['o1', 'o2'],
            'defaultOutletId': 'o2',
          },
          'queuedAt': DateTime.now().toIso8601String(),
        });
        api.handler = (_, _, _) async => {
          'id': 'srv1',
          'name': 'Sam',
          'phone': '9000000001',
        };

        await repo.processPendingOwnerActions();

        final body = api.of('POST').single.body as Map;
        expect(body['outlets'], ['o1', 'o2']);
        expect(body['defaultOutletId'], 'o2');
      },
    );

    test('an online update omits defaultOutletId (and outlets) when outletIds is null', () async {
      await cache.setCachedStaff([
        {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
      ]);
      api.handler = (_, _, _) async => {
        'id': 'e9',
        'name': 'Nia',
        'phone': '9000000009',
        'active': true,
      };

      await repo.updateStaff(
        employeeId: 'e9',
        name: 'Nia',
        phone: '9000000009',
        defaultOutletId: 'o2', // ignored without outletIds
      );

      final body = api.of('PUT').single.body as Map;
      expect(body.containsKey('outlets'), isFalse);
      expect(body.containsKey('defaultOutletId'), isFalse);
    });

    test('an offline outlet edit with no default clears the cached default and never stores blank names', () async {
      await cache.setCachedStaff([
        {
          'id': 'e9',
          'name': 'Nia',
          'phone': '9000000009',
          'active': true,
          'outlets': [
            {'id': 'o1', 'name': 'Main Road'},
          ],
          'defaultOutletId': 'o1',
        },
      ]);
      connectivity.offline = true;

      final m = await repo.updateStaff(
        employeeId: 'e9',
        name: 'Nia',
        phone: '9000000009',
        outletIds: ['o1', 'zz'], // zz is unknown to this device
      );

      expect(m.defaultOutletId, isNull);
      expect(
        cache.getCachedStaff()!.single.containsKey('defaultOutletId'),
        isFalse,
      );
      // Known outlet keeps its earlier name; the unknown one has no blank name.
      expect(m.outlets!.map((o) => o.name), ['Main Road', 'zz']);
      final refs = cache.getCachedStaff()!.single['outlets'] as List;
      expect((refs[1] as Map).containsKey('name'), isFalse);
    });
  });

  group('M6 the bloc tells the truth about writes', () {
    late OwnerBloc bloc;

    setUp(() => bloc = OwnerBloc(ownerRepository: repo));
    tearDown(() => bloc.close());

    Future<OwnerState> settle(OwnerEvent e) async {
      bloc.add(e);
      await pumpEventQueue();
      return bloc.state;
    }

    test('a validation rejection shows the server\'s own message', () async {
      api.handler = (_, _, _) async =>
          throw ValidationException('That phone number is already in use');

      final s = await settle(
        AddStaffEvent(name: 'Sam', phone: '900', password: 'password123'),
      );

      expect(s.error, 'That phone number is already in use');
    });

    test(
      'a 409 conflict passes its message through; a 500 stays generic',
      () async {
        api.handler = (_, _, _) async => throw ApiException(
          'Cannot remove the last outlet',
          statusCode: 409,
        );
        await cache.setCachedStaff([
          {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
        ]);
        var s = await settle(
          UpdateStaffEvent(employeeId: 'e9', name: 'Nia', phone: '9000000009'),
        );
        expect(s.error, 'Cannot remove the last outlet');

        api.handler = (_, _, _) async =>
            throw ApiException('db', statusCode: 500);
        s = await settle(
          UpdateStaffEvent(employeeId: 'e9', name: 'Nia', phone: '9000000009'),
        );
        expect(s.error, 'Could not update staff — try again');
      },
    );

    test(
      'a staff update that was only queued does not say "updated successfully"',
      () async {
        await cache.setCachedStaff([
          {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
        ]);
        connectivity.offline = true;

        final s = await settle(
          UpdateStaffEvent(
            employeeId: 'e9',
            name: 'Nia R',
            phone: '9000000009',
          ),
        );

        expect(s.error, isNull);
        expect(s.actionMessage, contains('Saved offline'));
      },
    );

    test('an online staff update still says it was updated', () async {
      await cache.setCachedStaff([
        {'id': 'e9', 'name': 'Nia', 'phone': '9000000009', 'active': true},
      ]);
      api.handler = (m, u, b) async => {
        'id': 'e9',
        'name': 'Nia R',
        'phone': '9000000009',
        'active': true,
      };
      // The follow-up list read answers with a list, the PUT with a row.
      api.handler = (m, u, b) async => m == 'GET'
          ? [
              {
                'id': 'e9',
                'name': 'Nia R',
                'phone': '9000000009',
                'active': true,
              },
            ]
          : {
              'id': 'e9',
              'name': 'Nia R',
              'phone': '9000000009',
              'active': true,
            };

      final s = await settle(
        UpdateStaffEvent(employeeId: 'e9', name: 'Nia R', phone: '9000000009'),
      );

      expect(s.actionMessage, 'Staff member updated successfully');
    });
  });

  group('models tolerate malformed elements', () {
    test('one bad outlet entry does not fail the staff list; blank names fall back to the id', () {
      final m = StaffMember.fromJson({
        'id': 'e1',
        'name': 'A',
        'phone': '1',
        'outlets': [
          'garbage',
          {'id': 'o1', 'name': ''},
          {'id': 'o2', 'name': 'Lake View'},
        ],
      });
      expect(m.outlets!.map((o) => o.id), ['o1', 'o2']);
      expect(m.outlets!.map((o) => o.name), ['o1', 'Lake View']);
    });

    test('copyWith can clear the default outlet', () {
      final m = StaffMember(
        id: 'e1',
        name: 'A',
        phone: '1',
        defaultOutletId: 'o1',
      );
      expect(m.copyWith(name: 'B').defaultOutletId, 'o1');
      expect(m.copyWith(clearDefaultOutletId: true).defaultOutletId, isNull);
    });

    test('a malformed dashboard element is skipped, the rest is kept', () {
      final m = DashboardMetrics.fromJson({
        'todaySales': 10,
        'serviceMix': [
          'bad',
          {'label': 'Wash', 'amount': 5},
        ],
        'cash': [
          42,
          {'label': 'Mon', 'income': 1, 'expenses': 0},
        ],
        'cashRange': 'nope',
        'bars': [
          null,
          {'label': 'w1', 'amount': 3},
        ],
      });
      expect(m.todaySales, 10);
      expect(m.serviceMix, hasLength(1));
      expect(m.cash, hasLength(1));
      expect(m.cashRange, isEmpty);
      expect(m.bars, hasLength(1));
    });
  });

  group('Bloc: stale card replies (two separate gates)', () {
    late _GatedRepo gated;
    late OwnerBloc bloc;

    setUp(() {
      gated = _GatedRepo();
      bloc = OwnerBloc(ownerRepository: gated);
    });
    tearDown(() => bloc.close());

    LoadCardMetricsEvent card(PeriodRange r, String key) =>
        LoadCardMetricsEvent(
          card: DashboardCard.salesByDate,
          range: r,
          requestKey: key,
        );

    test('a late success for the superseded selection is dropped', () async {
      bloc.add(card(PeriodRange.last7, 'k7'));
      await pumpEventQueue();
      bloc.add(card(PeriodRange.last90, 'k90'));
      await pumpEventQueue();
      expect(gated.periodGates, hasLength(2));

      gated.periodGates[1].complete(
        DashboardMetrics(bars: [DashboardBar(label: 'new', amount: 9)]),
      );
      await pumpEventQueue();
      gated.periodGates[0].complete(
        DashboardMetrics(bars: [DashboardBar(label: 'old', amount: 1)]),
      );
      await pumpEventQueue();

      final slice = bloc.state.cards[DashboardCard.salesByDate]!;
      expect(slice.key, 'k90');
      expect(slice.metrics!.bars.single.label, 'new');
    });

    test('a late FAILURE for the superseded selection does not mark the new one failed', () async {
      bloc.add(card(PeriodRange.last7, 'k7'));
      await pumpEventQueue();
      bloc.add(card(PeriodRange.last90, 'k90'));
      await pumpEventQueue();

      gated.periodGates[1].complete(
        DashboardMetrics(bars: [DashboardBar(label: 'new', amount: 9)]),
      );
      await pumpEventQueue();
      gated.periodGates[0].completeError(Exception('late'));
      await pumpEventQueue();

      final slice = bloc.state.cards[DashboardCard.salesByDate]!;
      expect(slice.key, 'k90');
      expect(slice.failed, isFalse);
      expect(slice.metrics, isNotNull);
    });
  });

  group('Bloc: dashboard latest selection wins', () {
    late _GatedRepo gated;
    late OwnerBloc bloc;

    setUp(() {
      gated = _GatedRepo();
      bloc = OwnerBloc(ownerRepository: gated);
    });
    tearDown(() => bloc.close());

    test(
      'an older selection answering after a newer one does not overwrite it',
      () async {
        bloc.add(LoadDashboardEvent(requestKey: 'A', isDefaultPeriod: false));
        await pumpEventQueue();
        bloc.add(LoadDashboardEvent(requestKey: 'B', isDefaultPeriod: false));
        await pumpEventQueue();

        gated.dashGates[1].complete(DashboardMetrics(todaySales: 222));
        await pumpEventQueue();
        gated.dashGates[0].complete(DashboardMetrics(todaySales: 111));
        await pumpEventQueue();

        expect(bloc.state.dashboardKey, 'B');
        expect(bloc.state.metrics.todaySales, 222);
      },
    );

    test('an older selection failing after a newer one succeeded keeps the good figures', () async {
      bloc.add(LoadDashboardEvent(requestKey: 'A', isDefaultPeriod: false));
      await pumpEventQueue();
      bloc.add(LoadDashboardEvent(requestKey: 'B', isDefaultPeriod: false));
      await pumpEventQueue();

      gated.dashGates[1].complete(DashboardMetrics(todaySales: 222));
      await pumpEventQueue();
      gated.dashGates[0].completeError(Exception('late'));
      await pumpEventQueue();

      expect(bloc.state.dashboardKey, 'B');
      expect(bloc.state.metrics.todaySales, 222);
      expect(bloc.state.error, isNull);
    });
  });
}

/// Every per-card and dashboard request waits on its own gate, in call order.
class _GatedRepo implements OwnerRepository {
  final List<Completer<DashboardMetrics>> periodGates = [];
  final List<Completer<DashboardMetrics>> dashGates = [];

  @override
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) {
    final c = Completer<DashboardMetrics>();
    periodGates.add(c);
    return c.future;
  }

  @override
  Future<DashboardMetrics> getDashboardMetrics({
    String? from,
    String? to,
    String? granularity,
  }) {
    final c = Completer<DashboardMetrics>();
    dashGates.add(c);
    return c.future;
  }

  @override
  DashboardMetrics? getCachedDashboardMetricsSync() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
