import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/sync/sync_manager.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';

import '../helpers/sync_test_env.dart';

Map<String, dynamic> _action(String id, {int failCount = 0, String? outlet}) =>
    {
      'type': 'update_status',
      'clientActionId': id,
      'orderCode': 'EL-1',
      'status': 'Ready',
      'storeId': 'store-1',
      'outletId': outlet ?? 'A',
      'failCount': failCount,
    };

Map<String, dynamic> _ok(
  String id, {
  String orderId = 'EL-1',
  String outlet = 'A',
}) => {
  'clientActionId': id,
  'status': 'success',
  'order': {
    'id': orderId,
    'name': 'X',
    'phone': '1',
    'status': 'Ready',
    'lines': <dynamic>[],
    'payments': <dynamic>[],
    'outletId': outlet,
  },
};

List<String> _ids(dynamic body) => [
  for (final a in (body['actions'] as List)) a['clientActionId'] as String,
];

void main() {
  orderMessageTests();
  late SyncTestEnv env;
  late ScriptedApi api;
  late OrdersRepository repo;

  setUp(() async {
    env = await SyncTestEnv.create();
    await env.cache.setActiveOutletId('A');
    api = ScriptedApi(env.cache);
    repo = OrdersRepository(apiClient: api, localCache: env.cache);
  });
  tearDown(() => env.dispose());

  group('message templates stay on the phone', () {
    Map<String, dynamic> row(String key, String body) => {
      'statusKey': key,
      'enabled': true,
      'attachment': 'NONE',
      'body': body,
    };

    test('a sync stores them, and the next sync replaces them whole', () async {
      expect(repo.getCachedMessageTemplates(), isNull);
      api.onGet = (_, _) async => {
        'templates': [row('PENDING', 'a'), row('READY', 'b')],
      };
      await repo.syncMessageTemplates();
      expect(repo.getCachedMessageTemplates()!.length, 2);

      api.onGet = (_, _) async => {
        'templates': [row('READY', 'c')],
      };
      await repo.syncMessageTemplates();
      final stored = repo.getCachedMessageTemplates()!;
      expect(stored.length, 1);
      expect(stored.single['body'], 'c');
    });

    test('a failed sync keeps what was stored', () async {
      api.onGet = (_, _) async => {
        'templates': [row('READY', 'b')],
      };
      await repo.syncMessageTemplates();
      api.onGet = (_, _) async => throw Exception('offline');
      await expectLater(repo.syncMessageTemplates(), throwsException);
      expect(repo.getCachedMessageTemplates()!.single['body'], 'b');
    });
  });

  group('push: a poison batch does not block the queue (H4)', () {
    setUp(() async {
      await env.cache.setPendingSyncQueue([
        _action('good1'),
        _action('poison'),
        _action('good2'),
      ]);
      api.onPost = (url, body, headers) async {
        final ids = _ids(body);
        if (ids.contains('poison')) {
          throw ValidationException('bad payload');
        }
        return {
          'results': [for (final id in ids) _ok(id)],
        };
      };
    });

    test(
      'other actions still go through; only the poison one is charged',
      () async {
        final ok = await repo.processPendingSyncQueue();

        final queue = env.cache.getPendingSyncQueue();
        expect(queue.map((a) => a['clientActionId']), ['poison']);
        expect(queue.single['failCount'], 1);
        expect(queue.single['lastError'], contains('bad payload'));
        // Rejected requests reached the server: not a connectivity failure.
        expect(ok, isTrue);
      },
    );

    test(
      'after enough rejections it is dead-lettered and the push reports it',
      () async {
        await env.cache.setPendingSyncQueue([_action('poison', failCount: 4)]);

        final ok = await repo.processPendingSyncQueue();

        expect(ok, isFalse);
        expect(env.cache.getPendingSyncQueue(), isEmpty);
        expect(
          env.cache.getDeadLetterQueue().single['clientActionId'],
          'poison',
        );
      },
    );

    test('413/422/404/409 are treated like 400', () async {
      for (final status in [404, 409, 413, 422]) {
        await env.cache.setPendingSyncQueue([_action('poison'), _action('g')]);
        api.onPost = (url, body, headers) async {
          if (_ids(body).contains('poison')) {
            throw ApiException('nope', statusCode: status);
          }
          return {
            'results': [for (final id in _ids(body)) _ok(id)],
          };
        };
        await repo.processPendingSyncQueue();
        final queue = env.cache.getPendingSyncQueue();
        expect(queue.map((a) => a['clientActionId']), [
          'poison',
        ], reason: '$status');
      }
    });
  });

  test('direct queue replay does not leave a Fetching banner', () async {
    await env.cache.setPendingSyncQueue([_action('a')]);
    api.onPost = (url, body, headers) async => {
      'results': [_ok('a')],
    };
    expect(await repo.processPendingSyncQueue(), isTrue);
    expect(SyncManager.instance.value.isSyncing, isFalse);
  });

  test('recoverable access 403 keeps order actions unchanged and later replays the same ids once', () async {
    final original = [_action('a'), _action('b')];
    for (final reason in [
      'payment_lapsed',
      'billing_pending',
      'store_locked',
      'membership_inactive',
      'must_change_password',
    ]) {
      await env.cache.setPendingSyncQueue(original);
      await env.cache.setDeadLetterQueue([]);
      api.posts.clear();
      api.onPost = (url, body, headers) async => throw AuthException(
        code: 'FORBIDDEN',
        reason: reason,
        statusCode: 403,
      );

      expect(await repo.processPendingSyncQueue(), isFalse, reason: reason);
      expect(env.cache.getPendingSyncQueue(), original, reason: reason);
      expect(env.cache.getDeadLetterQueue(), isEmpty, reason: reason);
      expect(api.posts, hasLength(1), reason: reason);
    }

    api.posts.clear();
    api.onPost = (url, body, headers) async => {
      'results': [_ok('a'), _ok('b')],
    };

    expect(await repo.processPendingSyncQueue(), isTrue);
    expect(env.cache.getPendingSyncQueue(), isEmpty);
    expect(api.posts, hasLength(1));
    expect(_ids(api.posts.single['body']), ['a', 'b']);
  });

  group(
    'push: unreachable / server trouble keeps everything and spends no retries',
    () {
      Future<void> expectUntouched(
        Object error, {
        bool expectPending = false,
      }) async {
        await env.cache.setPendingSyncQueue([
          _action('a', failCount: 1),
          _action('b'),
        ]);
        api.onPost = (url, body, headers) async => throw error;

        final ok = await repo.processPendingSyncQueue();

        expect(ok, isFalse);
        final queue = env.cache.getPendingSyncQueue();
        expect(queue.map((a) => a['clientActionId']), ['a', 'b']);
        expect(queue.first['failCount'], 1);
        expect(queue.last['failCount'] ?? 0, 0);
        if (expectPending) {
          expect(SyncManager.instance.value.isPendingOnline, isTrue);
        }
      }

      test(
        'timeout on a nominally-online connection -> banner pending',
        () async {
          await expectUntouched(TimeoutException('slow'), expectPending: true);
        },
      );

      test('connection error (no status code) -> banner pending', () async {
        await expectUntouched(
          ApiException('Network error'),
          expectPending: true,
        );
      });

      test(
        'persistent 500',
        () => expectUntouched(ApiException('x', statusCode: 500)),
      );
      test('429', () => expectUntouched(RateLimitException('slow down')));
      test('408', () => expectUntouched(ApiException('t', statusCode: 408)));
      test(
        '401',
        () => expectUntouched(
          AuthException(code: 'UNAUTHENTICATED', statusCode: 401),
        ),
      );
    },
  );

  group('403 outlet dead-letter is reported (C1)', () {
    test('push returns false and parks the group', () async {
      await env.cache.setPendingSyncQueue([_action('a'), _action('b')]);
      api.onPost = (url, body, headers) async =>
          throw AuthException(code: 'FORBIDDEN', statusCode: 403);

      expect(await repo.processPendingSyncQueue(), isFalse);
      expect(env.cache.getPendingSyncQueue(), isEmpty);
      expect(env.cache.getDeadLetterQueue(), hasLength(2));
    });
  });

  group('pull is not "complete" while pages remain (H8)', () {
    test(
      'returns false when the batch limit is hit with a cursor waiting',
      () async {
        var page = 0;
        api.onGet = (url, headers) async => {
          'orders': [
            {'id': 'EL-${++page}', 'outletId': 'A', 'status': 'Pending'},
          ],
          'nextCursor': 'c$page',
        };

        final ok = await repo.syncOrdersDelta(maxBatches: 2);

        expect(ok, isFalse);
        expect(api.gets, hasLength(2));
        // The cursor is kept so the next run resumes.
        expect(env.cache.getLastSyncCursorForScope('A'), 'c2');
      },
    );

    test('returns true once the server says there is no next cursor', () async {
      api.onGet = (url, headers) async => {
        'orders': <dynamic>[],
        'nextCursor': null,
      };
      expect(await repo.syncOrdersDelta(maxBatches: 2), isTrue);
    });

    test(
      'syncAllOrders and syncOrdersForScope throw on a truncated pull',
      () async {
        api.onGet = (url, headers) async => {
          'orders': <dynamic>[],
          'nextCursor': 'more',
        };
        // The fake repeats its cursor, so neither pull can make progress.
        await expectLater(repo.syncAllOrders(), throwsException);
        await expectLater(repo.syncOrdersForScope('B'), throwsException);
      },
    );

    test('repeating the same cursor is recognized as no progress', () async {
      api.onGet = (url, headers) async => {
        'orders': <dynamic>[],
        'nextCursor': 'stuck',
      };
      expect(await repo.syncOrdersDelta(maxBatches: 10), isFalse);
      expect(api.gets, hasLength(2));
      expect(env.cache.getLastSyncCursor(), 'stuck');
    });

    test('setup retry resumes after two bounded pulls', () async {
      var page = 0;
      api.onGet = (url, headers) async {
        page++;
        return {
          'orders': <dynamic>[],
          'nextCursor': page <= 200 ? 'c$page' : null,
        };
      };

      await expectLater(repo.syncAllOrders(), throwsException);
      repo = OrdersRepository(apiClient: api, localCache: env.cache);
      await expectLater(repo.syncAllOrders(), throwsException);
      repo = OrdersRepository(apiClient: api, localCache: env.cache);
      await repo.syncAllOrders();

      expect(api.gets, hasLength(201));
      expect(api.gets[100], contains('since=c100'));
      expect(api.gets[200], contains('since=c200'));
      expect(env.cache.getCachedOrders(), isEmpty);
    });
  });

  group('a dead session is surfaced, not swallowed', () {
    test('401 during the pull is rethrown (delta and named scope)', () async {
      api.onGet = (url, headers) async =>
          throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401);
      await expectLater(repo.syncOrdersDelta(), throwsA(isA<AuthException>()));
      await expectLater(
        repo.syncOrdersForScope('B'),
        throwsA(isA<AuthException>()),
      );
    });

    test('other failures still just report false', () async {
      api.onGet = (url, headers) async =>
          throw ApiException('x', statusCode: 500);
      expect(await repo.syncOrdersDelta(), isFalse);
    });

    test('403 during pull propagates for outlet access handling', () async {
      api.onGet = (url, headers) async =>
          throw AuthException(code: 'FORBIDDEN', statusCode: 403);
      await expectLater(repo.syncOrdersDelta(), throwsA(isA<AuthException>()));
    });

    test('order detail does not serve cache over 401 or 403', () async {
      await env.cache.setCachedOrders([
        {'id': 'EL-1', 'name': 'Cached', 'status': 'Pending'},
      ]);
      for (final status in [401, 403]) {
        api.onGet = (url, headers) async => throw AuthException(
          code: status == 401 ? 'UNAUTHENTICATED' : 'FORBIDDEN',
          statusCode: status,
        );
        await expectLater(
          repo.getOrderDetail('EL-1'),
          throwsA(isA<AuthException>()),
        );
      }
      api.onGet = (url, headers) async => throw ApiException('network');
      expect((await repo.getOrderDetail('EL-1')).name, 'Cached');
    });
  });

  group('a response is written to the scope it was fetched for (H2)', () {
    test(
      'delta: outlet switched mid-request -> nothing written anywhere',
      () async {
        await env.cache.setCachedOrdersForScope('B', [
          {'id': 'EL-B', 'outletId': 'B'},
        ]);
        api.onGet = (url, headers) async {
          await env.cache.setActiveOutletId('B');
          return {
            'orders': [
              {'id': 'EL-A1', 'outletId': 'A', 'status': 'Pending'},
            ],
            'nextCursor': 'cA',
          };
        };

        final ok = await repo.syncOrdersDelta();

        expect(ok, isFalse);
        expect(env.cache.getCachedOrdersForScope('B')!.map((o) => o['id']), [
          'EL-B',
        ]);
        expect(env.cache.getCachedOrdersForScope('A'), isNull);
        expect(env.cache.getLastSyncCursorForScope('B'), isNull);
      },
    );

    test('delta: store switched mid-request -> nothing written', () async {
      api.onGet = (url, headers) async {
        await env.cache.setActiveStoreId('store-2');
        return {
          'orders': [
            {'id': 'EL-A1', 'outletId': 'A', 'status': 'Pending'},
          ],
          'nextCursor': null,
        };
      };

      expect(await repo.syncOrdersDelta(), isFalse);
      await env.cache.setActiveStoreId('store-1');
      expect(env.cache.getCachedOrdersForScope('A'), isNull);
      await env.cache.setActiveStoreId('store-2');
      expect(env.cache.getCachedOrdersForScope('A'), isNull);
    });

    test(
      'push: confirmed order lands in the outlet it was sent from',
      () async {
        await env.cache.setCachedOrdersForScope('A', [
          {'id': '', 'offlineId': 'EL-1', 'outletId': 'A', 'status': 'Pending'},
        ]);
        await env.cache.setCachedOrdersForScope('B', []);
        await env.cache.setPendingSyncQueue([_action('a1')]);
        api.onPost = (url, body, headers) async {
          await env.cache.setActiveOutletId('B'); // user switches mid-request
          return {
            'results': [_ok('a1', orderId: 'EL-9', outlet: 'A')],
          };
        };

        await repo.processPendingSyncQueue();

        expect(env.cache.getCachedOrdersForScope('B'), isEmpty);
        final a = env.cache.getCachedOrdersForScope('A')!;
        expect(a.map((o) => o['id']), contains('EL-9'));
      },
    );

    test(
      'push: store switched mid-request -> confirmed order is not written',
      () async {
        await env.cache.setCachedOrdersForScope('A', []);
        await env.cache.setPendingSyncQueue([_action('a1')]);
        api.onPost = (url, body, headers) async {
          await env.cache.setActiveStoreId('store-2');
          return {
            'results': [_ok('a1', orderId: 'EL-9', outlet: 'A')],
          };
        };

        await repo.processPendingSyncQueue();

        await env.cache.setActiveStoreId('store-2');
        expect(env.cache.getCachedOrdersForScope('A'), isNull);
        await env.cache.setActiveStoreId('store-1');
        expect(env.cache.getCachedOrdersForScope('A'), isEmpty);
      },
    );

    test(
      'invoice: fetched for A, outlet switched -> merged into A only',
      () async {
        await env.cache.setCachedOrdersForScope('A', [_paidDelivered('EL-1')]);
        await env.cache.setCachedOrdersForScope('B', [_paidDelivered('EL-1')]);
        api.onGet = (url, headers) async {
          await env.cache.setActiveOutletId('B');
          return {'exists': true, 'invoiceSeq': 7, 'accessToken': 't'};
        };

        await repo.getOrCreateInvoice('EL-1');

        expect(
          env.cache.getCachedOrdersForScope('A')!.single['invoice'],
          isNotNull,
        );
        expect(
          env.cache.getCachedOrdersForScope('B')!.single['invoice'],
          isNull,
        );
      },
    );
  });

  group('missing-invoice retry', () {
    late DateTime clock;
    setUp(() {
      clock = DateTime(2026, 9, 30, 12);
      repo.now = () => clock;
    });

    Future<void> seed(int n) => env.cache.setCachedOrders([
      for (var i = 1; i <= n; i++) _paidDelivered('EL-$i'),
    ]);

    test(
      '403/404/409 are retried after the backoff, not for the whole session',
      () async {
        await seed(1);
        api.onGet = (url, headers) async => throw AuthException(
          code: 'FORBIDDEN',
          reason: 'payment_lapsed',
          statusCode: 403,
        );
        await repo.retryMissingInvoices();
        expect(api.gets, hasLength(1));

        // Within the backoff: not asked again.
        clock = clock.add(const Duration(seconds: 30));
        await repo.retryMissingInvoices();
        expect(api.gets, hasLength(1));

        // Backoff over and the server has recovered.
        clock = clock.add(const Duration(minutes: 3));
        api.onGet = (url, headers) async => {
          'exists': true,
          'invoiceSeq': 1,
          'accessToken': 't',
        };
        await repo.retryMissingInvoices();
        expect(api.gets, hasLength(2));
        expect(env.cache.getCachedOrders()!.single['invoice'], isNotNull);
      },
    );

    test('400 is not retried this session', () async {
      await seed(1);
      api.onGet = (url, headers) async => throw ValidationException('bad');
      await repo.retryMissingInvoices();
      clock = clock.add(const Duration(hours: 1));
      await repo.retryMissingInvoices();
      expect(api.gets, hasLength(1));
    });

    test('5xx and timeouts are retried on the very next cycle', () async {
      await seed(1);
      api.onGet = (url, headers) async =>
          throw ApiException('x', statusCode: 503);
      await repo.retryMissingInvoices();
      api.onGet = (url, headers) async => throw TimeoutException('t');
      await repo.retryMissingInvoices();
      expect(api.gets, hasLength(2));
    });

    test('401 stops the run: later batches are never requested', () async {
      await seed(9); // batches of 4
      api.onGet = (url, headers) async =>
          throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401);
      await repo.retryMissingInvoices();
      expect(api.gets, hasLength(4)); // only the first batch went out
    });

    test('stops when the store changes between batches', () async {
      await seed(9);
      api.onGet = (url, headers) async {
        await env.cache.setActiveStoreId('store-2');
        throw ApiException('x', statusCode: 503);
      };
      await repo.retryMissingInvoices();
      expect(api.gets, hasLength(4));
    });
  });

  group('local Delivered keeps the completed date in step', () {
    test('Delivered sets today and cannot be undone', () async {
      await env.cache.setCachedOrders([
        {
          'id': 'EL-1',
          'name': 'X',
          'phone': '1',
          'status': 'Ready',
          'lines': <dynamic>[],
          'payments': <dynamic>[],
        },
      ]);
      final d = DateTime.now();
      final today =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final delivered = await repo.updateStatus('EL-1', 'Delivered');
      expect(delivered.completed, today);

      await expectLater(
        repo.updateStatus('EL-1', 'Ready'),
        throwsA(isA<OrderRuleException>()),
      );
    });
  });

  group('order rules', () {
    Map<String, dynamic> order(String status, {int paid = 0}) => {
      'id': 'EL-9',
      'name': 'X',
      'phone': '1',
      'status': status,
      'lines': [
        {
          'productId': 'p',
          'name': 'i',
          'quantity': 1,
          'unit': 'PIECE',
          'amount': 100,
        },
      ],
      'payments': [
        if (paid > 0)
          {'id': 'p1', 'amount': paid, 'date': '2026-09-01', 'method': 'Cash'},
      ],
    };

    test(
      'Delivered is refused while a balance is due, and queues nothing',
      () async {
        await env.cache.setCachedOrders([order('Ready')]);
        await expectLater(
          repo.updateStatus('EL-9', 'Delivered'),
          throwsA(isA<OrderRuleException>()),
        );
        expect(env.cache.getPendingSyncQueue(), isEmpty);
      },
    );

    test('collect then deliver queues payment first, then status', () async {
      await env.cache.setCachedOrders([order('Ready')]);
      await repo.recordPayment('EL-9', 100, 'Cash');
      await repo.updateStatus('EL-9', 'Delivered');
      expect(env.cache.getPendingSyncQueue().map((a) => a['type']).toList(), [
        'record_payment',
        'update_status',
      ]);
    });

    test('a repeated collect or delivered tap queues nothing extra', () async {
      await env.cache.setCachedOrders([order('Ready')]);
      await repo.recordPayment('EL-9', 100, 'Cash');
      await repo.updateStatus('EL-9', 'Delivered');
      await expectLater(
        repo.recordPayment('EL-9', 100, 'Cash'),
        throwsA(isA<OrderRuleException>()),
      );
      await repo.updateStatus('EL-9', 'Delivered'); // same status: no-op
      expect(env.cache.getPendingSyncQueue(), hasLength(2));
    });

    test('status cannot move backwards', () async {
      await env.cache.setCachedOrders([order('Ready', paid: 100)]);
      await expectLater(
        repo.updateStatus('EL-9', 'In Progress'),
        throwsA(isA<OrderRuleException>()),
      );
    });

    group('queued actions survive a server copy', () {
      Map<String, dynamic> queuedPayment(String id) => {
        'type': 'record_payment',
        'clientActionId': id,
        'orderCode': 'EL-9',
        'amount': 100,
        'method': 'Cash',
        'queuedAt': '2026-10-07T07:22:00',
      };
      Map<String, dynamic> queuedDelivered() => {
        'type': 'update_status',
        'clientActionId': 'a-del',
        'orderCode': 'EL-9',
        'status': 'Delivered',
        'queuedAt': '2026-10-07T07:22:01',
      };

      test(
        'server copy is Ready/unpaid but payment and delivery are queued',
        () async {
          await env.cache.setCachedOrders([order('Ready')]);
          await env.cache.setPendingSyncQueue([
            queuedPayment('a-pay'),
            queuedDelivered(),
          ]);
          final shown = repo.getCachedOrdersList().single;
          expect(shown.balanceDue, 0);
          expect(shown.status, 'Delivered');
        },
      );

      test(
        'a second collect is refused while the first is still queued',
        () async {
          await env.cache.setCachedOrders([order('Ready')]);
          await env.cache.setPendingSyncQueue([queuedPayment('a-pay')]);
          await expectLater(
            repo.recordPayment('EL-9', 100, 'Cash'),
            throwsA(isA<OrderRuleException>()),
          );
          expect(env.cache.getPendingSyncQueue(), hasLength(1));
        },
      );

      test(
        'once the server echoes the payment it is not counted twice',
        () async {
          final served = order('Ready', paid: 100);
          (served['payments'] as List).first['clientActionId'] = 'a-pay';
          await env.cache.setCachedOrders([served]);
          await env.cache.setPendingSyncQueue([queuedPayment('a-pay')]);
          final shown = repo.getCachedOrdersList().single;
          expect(shown.payments, hasLength(1));
          expect(shown.balanceDue, 0);
        },
      );

      test('an action that left the queue is no longer shown', () async {
        await env.cache.setCachedOrders([order('Ready')]);
        await env.cache.setPendingSyncQueue([]);
        final shown = repo.getCachedOrdersList().single;
        expect(shown.balanceDue, 100);
        expect(shown.status, 'Ready');
      });

      test(
        'the local collect carries the same id as the queued action',
        () async {
          await env.cache.setCachedOrders([order('Ready')]);
          await repo.recordPayment('EL-9', 100, 'Cash');
          final queuedId = env.cache
              .getPendingSyncQueue()
              .single['clientActionId'];
          final raw = env.cache.getCachedOrders()!.single['payments'] as List;
          expect(raw.single['clientActionId'], queuedId);
          // laid over itself, the payment is still counted once
          expect(repo.getCachedOrdersList().single.payments, hasLength(1));
        },
      );
    });

    test('a payment above the balance is refused', () async {
      await env.cache.setCachedOrders([order('Ready', paid: 40)]);
      await expectLater(
        repo.recordPayment('EL-9', 100, 'Cash'),
        throwsA(isA<OrderRuleException>()),
      );
    });
  });
}

Map<String, dynamic> _paidDelivered(String id) => {
  'id': id,
  'name': 'X',
  'phone': '1',
  'status': 'Delivered',
  'lines': [
    {
      'productId': 'p',
      'name': 'i',
      'quantity': 1,
      'unit': 'PIECE',
      'amount': 100,
    },
  ],
  'payments': [
    {'id': 'p1', 'amount': 100, 'date': '2026-09-01', 'method': 'Cash'},
  ],
};

void orderMessageTests() {
  group('OrderMessage.compose', () {
    test('fills {link} with origin + path', () {
      const m = OrderMessage(
        enabled: true,
        text: 'Hi {link}',
        linkPath: '/o/abc/view',
      );
      expect(m.compose('https://x.test'), 'Hi https://x.test/o/abc/view');
    });
    test('appends the link when the template has no {link}', () {
      const m = OrderMessage(
        enabled: true,
        text: 'Ready!',
        linkPath: '/i/t/view',
      );
      expect(m.compose('https://x.test'), 'Ready!\nhttps://x.test/i/t/view');
    });
    test('no link path: text only, never a stray placeholder', () {
      const m = OrderMessage(enabled: true, text: 'Hi {link}', linkPath: null);
      expect(m.compose('https://x.test'), 'Hi');
    });
  });
}
