import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/server_action_queue.dart';

class _MemoryCache extends LocalCacheService {
  List<Map<String, dynamic>> stored = [];

  @override
  List<Map<String, dynamic>> getServerActions() => [
    for (final m in stored) Map<String, dynamic>.from(m),
  ];

  @override
  Future<void> setServerActions(List<Map<String, dynamic>> actions) async =>
      stored = [for (final m in actions) Map<String, dynamic>.from(m)];
}

void main() {
  late _MemoryCache cache;
  late ServerActionQueue queue;

  setUp(() {
    cache = _MemoryCache();
    queue = ServerActionQueue.forTesting(cache);
  });

  Future<void> add(String id, {String type = 'delete_expense'}) =>
      queue.enqueue(type: type, targetId: id, label: 'Deleting…').then((_) {});

  test(
    'enqueue returns at once and a second request for the same target waits',
    () async {
      await add('e1');
      expect(queue.actions.value, hasLength(1));
      expect(queue.forTarget('e1')!.label, 'Deleting…');
      expect(() => add('e1'), throwsStateError);
      await add('e2');
      expect(queue.actions.value, hasLength(2));
    },
  );

  test('a confirmed request leaves the queue; order is kept', () async {
    await add('e1');
    await add('e2');
    final sent = <String>[];
    final allDone = await queue.process({
      'delete_expense': (a) async => sent.add(a.targetId),
    });
    expect(allDone, isTrue);
    expect(sent, ['e1', 'e2']);
    expect(queue.actions.value, isEmpty);
    expect(cache.stored, isEmpty);
  });

  test(
    'the server refusing parks that request with its reason and moves on',
    () async {
      await add('e1');
      await add('e2');
      final sent = <String>[];
      final allDone = await queue.process({
        'delete_expense': (a) async {
          if (a.targetId == 'e1') {
            throw ApiException(
              'Delivered orders cannot be cancelled.',
              statusCode: 400,
            );
          }
          sent.add(a.targetId);
        },
      });
      expect(allDone, isTrue);
      expect(sent, ['e2']);
      final left = queue.actions.value.single;
      expect(left.targetId, 'e1');
      expect(left.isFailed, isTrue);
      expect(left.lastError, 'Delivered orders cannot be cancelled.');
    },
  );

  test(
    'a slow or unreachable server keeps everything queued, in order',
    () async {
      await add('e1');
      await add('e2');
      var calls = 0;
      for (final failure in [
        TimeoutException('slow'),
        ApiException('Bad gateway', statusCode: 502),
        ApiException('Network error occurred'),
        ApiException('Slow down', statusCode: 429),
      ]) {
        final allDone = await queue.process({
          'delete_expense': (a) async {
            calls++;
            throw failure;
          },
        });
        expect(allDone, isFalse);
        expect(queue.actions.value.map((a) => a.targetId), ['e1', 'e2']);
        expect(queue.actions.value.every((a) => !a.isFailed), isTrue);
      }
      expect(calls, 4, reason: 'stops at the first one each time');
    },
  );

  test('a signed-out session is handed to the caller', () async {
    await add('e1');
    await expectLater(
      queue.process({
        'delete_expense': (a) async =>
            throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401),
      }),
      throwsA(isA<AuthException>()),
    );
    expect(queue.actions.value.single.isFailed, isFalse);
  });

  test('retry puts failed requests back; dismiss removes one', () async {
    await add('e1');
    await add('e2');
    await queue.process({
      'delete_expense': (a) async => throw ApiException('No', statusCode: 400),
    });
    expect(queue.actions.value.every((a) => a.isFailed), isTrue);

    await queue.reviveFailed();
    expect(queue.actions.value.every((a) => !a.isFailed), isTrue);

    await queue.dismiss(queue.actions.value.first.id);
    expect(queue.actions.value, hasLength(1));
  });

  test('a new request on a refused target replaces the refused one', () async {
    await add('e1');
    await queue.process({
      'delete_expense': (a) async => throw ApiException('No', statusCode: 400),
    });
    await add('e1');
    expect(queue.actions.value, hasLength(1));
    expect(queue.actions.value.single.isFailed, isFalse);
  });

  test('an unknown request type is parked, not retried forever', () async {
    await add('e1', type: 'old_type');
    await queue.process({});
    expect(queue.actions.value.single.isFailed, isTrue);
  });
}
