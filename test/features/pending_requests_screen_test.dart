import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/server_action_queue.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/owner/presentation/pending_requests_screen.dart';

class _MemoryCache extends LocalCacheService {
  List<Map<String, dynamic>> stored = [];

  @override
  List<Map<String, dynamic>> getServerActions() => [
    for (final m in stored) Map<String, dynamic>.from(m),
  ];

  @override
  Future<void> setServerActions(List<Map<String, dynamic>> actions) async =>
      stored = [for (final m in actions) Map<String, dynamic>.from(m)];

  @override
  String? getActiveStoreId() => null;

  List<Map<String, dynamic>> parked = [];

  @override
  List<Map<String, dynamic>> getDeadLetterOwnerActionsQueue() => parked;

  @override
  Future<void> setDeadLetterOwnerActionsQueue(
    List<Map<String, dynamic>> queue,
  ) async => parked = queue;
}

void main() {
  late ServerActionQueue original;
  late ServerActionQueue queue;

  setUp(() {
    original = ServerActionQueue.instance;
    queue = ServerActionQueue.forTesting(_MemoryCache());
    ServerActionQueue.instance = queue;
    // Signed out, so the retry's sync trigger does nothing.
    SyncEngine.instance = SyncEngine.internal(localCache: _MemoryCache());
  });

  tearDown(() => ServerActionQueue.instance = original);

  Widget screen() => const MaterialApp(home: PendingRequestsScreen());

  testWidgets('says so when nothing is waiting', (tester) async {
    await tester.pumpWidget(screen());
    expect(find.byKey(const Key('pending_requests_empty')), findsOneWidget);
  });

  testWidgets('shows waiting and refused requests; retry and dismiss work', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await queue.enqueue(
        type: 'delete_expense',
        targetId: 'e1',
        label: 'Deleting…',
        summary: 'Delete "Rent"',
      );
      await queue.enqueue(
        type: 'cancel_order',
        targetId: '1000000002',
        label: 'Cancelling…',
        summary: 'Cancel order 1000000002',
      );
      await queue.process({
        'cancel_order': (a) async => throw TimeoutException('slow'),
        'delete_expense': (a) async =>
            throw ApiException('Bill not found.', statusCode: 400),
      });
    });
    await tester.pumpWidget(screen());

    expect(find.text('Cancel order 1000000002'), findsOneWidget);
    expect(
      find.text('Waiting for the server — sent automatically'),
      findsOneWidget,
    );
    expect(find.text('Delete "Rent"'), findsOneWidget);
    expect(find.text('Not done: Bill not found.'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Retry'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.text('Not done: Bill not found.'), findsNothing);
    expect(
      find.text('Waiting for the server — sent automatically'),
      findsNWidgets(2),
    );
  });

  testWidgets('dismiss removes a refused request', (tester) async {
    await tester.runAsync(() async {
      await queue.enqueue(
        type: 'delete_expense',
        targetId: 'e1',
        label: 'Deleting…',
        summary: 'Delete "Rent"',
      );
      await queue.process({
        'delete_expense': (a) async =>
            throw ApiException('Bill not found.', statusCode: 400),
      });
    });
    await tester.pumpWidget(screen());
    await tester.runAsync(() async {
      await tester.tap(find.text('Dismiss'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byKey(const Key('pending_requests_empty')), findsOneWidget);
  });

  testWidgets(
    'shows a refused owner change with its reason; dismiss clears it',
    (tester) async {
      final cache = _MemoryCache()
        ..parked = [
          {
            'clientActionId': 'a1',
            'type': 'update_store_profile',
            'lastError': 'Address is required',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(home: PendingRequestsScreen(cache: cache)),
      );
      expect(find.text('Store profile update'), findsOneWidget);
      expect(find.text('Not saved: Address is required'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(cache.parked, isEmpty);
      expect(find.byKey(const Key('pending_requests_empty')), findsOneWidget);
    },
  );
}
