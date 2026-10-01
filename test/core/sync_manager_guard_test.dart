import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/sync/sync_manager.dart';

import '../helpers/sync_test_env.dart';

void main() {
  late SyncTestEnv env;
  final manager = SyncManager.instance;

  setUp(() async => env = await SyncTestEnv.create());
  tearDown(() => env.dispose());

  Future<void> queueOne() => env.cache.enqueueSyncAction({
    'type': 'update_status',
    'clientActionId': 'a1',
    'orderCode': 'EL-1',
    'status': 'Ready',
  });

  Future<void> deadLetterOne() => env.cache.setDeadLetterQueue([
    {'type': 'update_status', 'clientActionId': 'd1'},
  ]);

  group('completeSync() never hides unsent work', () {
    test('a read finishing does not clear "N changes pending"', () async {
      await queueOne();
      manager.setPendingOnline(1);

      manager.completeSync();

      expect(manager.value.isPendingOnline, isTrue);
      expect(manager.value.pendingCount, 1);
    });

    test(
      'a read finishing does not clear an error while changes wait',
      () async {
        await queueOne();
        manager.setError('Sync failed — tap to retry');

        manager.completeSync();

        expect(manager.value.hasError, isTrue);
      },
    );

    test('a read finishing does not clear a dead-letter banner', () async {
      await deadLetterOne();
      manager.setDeadLettered(1);

      manager.completeSync();

      expect(manager.value.isSyncPaused, isTrue);
      expect(manager.value.message, contains("couldn't be saved"));
    });

    test('an owner dead-letter queue counts too', () async {
      await env.cache.setDeadLetterOwnerActionsQueue([
        {'clientActionId': 'o1'},
      ]);
      manager.setDeadLettered(1);

      manager.completeSync();

      expect(manager.value.isSyncPaused, isTrue);
    });

    test(
      'a transient "syncing" state is replaced by the pending state',
      () async {
        await queueOne();
        manager.startSync('Fetching latest from cloud...');

        manager.completeSync();

        expect(manager.value.isPendingOnline, isTrue);
        expect(manager.value.pendingCount, 1);
      },
    );

    test('with nothing unsent it still completes', () {
      manager.startSync('Fetching…');
      manager.completeSync();
      expect(manager.value.isSynced, isTrue);
    });

    test(
      'force (the engine, after checking the queues) always completes',
      () async {
        await queueOne();
        manager.setPendingOnline(1);

        manager.completeSync(force: true);

        expect(manager.value.isSynced, isTrue);
      },
    );
  });

  group('startSync() does not downgrade a persistent state', () {
    test('paused, error and pending survive a plain startSync', () {
      manager.setSyncPaused(2);
      manager.startSync('Fetching…');
      expect(manager.value.isSyncPaused, isTrue);

      manager.setError('boom');
      manager.startSync('Fetching…');
      expect(manager.value.hasError, isTrue);

      manager.setPendingOnline(3);
      manager.startSync('Fetching…');
      expect(manager.value.isPendingOnline, isTrue);
    });

    test('the engine push (force) may replace them', () {
      manager.setError('boom');
      manager.startSync('Saving changes to cloud...', true);
      expect(manager.value.isSyncing, isTrue);
    });

    test('from synced a plain startSync still shows syncing', () {
      manager.startSync('Fetching…');
      expect(manager.value.isSyncing, isTrue);
    });
  });
}
