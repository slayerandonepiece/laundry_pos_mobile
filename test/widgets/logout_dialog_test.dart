import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/features/profile/presentation/dialogs/logout_dialog.dart';

class MockLocalCache extends LocalCacheService {
  List<Map<String, dynamic>> queue = [];
  String? storeId = 'store-test';

  @override
  String? getActiveStoreId() => storeId;

  @override
  String? getActiveOutletId() => null;

  @override
  List<Map<String, dynamic>> getPendingSyncQueue() => queue;

  // SyncEngine's getTotalPendingCount() also reads the owner-action queue.
  @override
  List<Map<String, dynamic>> getPendingOwnerActionsQueue() => [];
}

// LogoutDialog now always syncs via SyncEngine.instance (so it shares
// SyncEngine's single-flight guard rather than racing it) instead of
// calling a repository handed to it directly, so these tests inject the
// mock by swapping SyncEngine.instance rather than via LogoutDialog's
// (now vestigial) ordersRepository parameter.
class MockOrdersRepository extends OrdersRepository {
  final MockLocalCache localCache;

  MockOrdersRepository(this.localCache);

  bool processQueueShouldSucceed = true;
  int processQueueCallCount = 0;
  int syncDeltaCallCount = 0;

  @override
  Future<bool> processPendingSyncQueue() async {
    processQueueCallCount++;
    if (processQueueShouldSucceed) {
      // Real processPendingSyncQueue() removes synced actions from the
      // queue once the server confirms them — mirror that here since
      // LogoutDialog now infers success from the queue being empty
      // afterward, not from this return value directly.
      localCache.queue = [];
    }
    return processQueueShouldSucceed;
  }

  @override
  Future<bool> syncOrdersDelta({
    int maxBatches = 10,
    int limit = 50,
    bool fromStart = false,
  }) async {
    syncDeltaCallCount++;
    return true;
  }

  // LogoutDialog goes through SyncEngine.retryNow(), which revives the
  // dead-letter queue first — the real one reads Hive, which isn't open here.
  @override
  Future<void> reviveDeadLetterQueue() async {}

  // Fired in the background after a successful sync; also reads Hive.
  @override
  Future<void> retryMissingInvoices() async {}
}

// retryNow() re-probes connectivity; the real probe goes through a platform
// channel that never completes under testWidgets' fake time.
class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService() : super.internal();

  @override
  bool get isOffline => false;

  @override
  Future<bool> checkIsOffline() async => false;
}

// SyncEngine also drains/revives owner actions on the same run; without this
// it falls back to a real OwnerRepository and throws on Hive before the push.
class MockOwnerRepository extends OwnerRepository {
  @override
  Future<bool> processPendingOwnerActions() async => true;

  @override
  Future<void> reviveDeadLetterQueue() async {}
}

class FakeAuthBloc extends AuthBloc {
  bool logoutEventReceived = false;

  FakeAuthBloc()
    : super(
        authRepository: AuthRepository(
          apiClient: ApiClient(),
          secureStorage: SecureStorageService(),
          localCache: LocalCacheService(),
        ),
      );

  @override
  void add(AuthEvent event) {
    if (event is LogoutRequestedEvent) {
      logoutEventReceived = true;
      return;
    }
    super.add(event);
  }
}

void main() {
  group('LogoutDialog Tests', () {
    late MockLocalCache mockCache;
    late MockOrdersRepository mockOrdersRepo;
    late FakeAuthBloc fakeAuthBloc;

    setUp(() {
      mockCache = MockLocalCache();
      mockOrdersRepo = MockOrdersRepository(mockCache);
      fakeAuthBloc = FakeAuthBloc();
      ConnectivityService.instance = FakeConnectivityService();
      SyncEngine.instance = SyncEngine.internal(
        ordersRepository: mockOrdersRepo,
        ownerRepository: MockOwnerRepository(),
        localCache: mockCache,
      );
    });

    tearDown(() {
      fakeAuthBloc.close();
      SyncEngine.instance = SyncEngine.internal();
      ConnectivityService.instance = ConnectivityService.internal();
    });

    testWidgets(
      'No pending orders: renders standard Log out button and logs out',
      (tester) async {
        mockCache.queue = [];

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LogoutDialog.show(
                  context,
                  ordersRepository: mockOrdersRepo,
                  localCache: mockCache,
                  authBloc: fakeAuthBloc,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);
        expect(find.text('Logout & Sync'), findsNothing);

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        expect(fakeAuthBloc.logoutEventReceived, isTrue);
        expect(mockOrdersRepo.processQueueCallCount, 0);
      },
    );

    testWidgets(
      'Pending orders present: renders Logout & Sync and runs checkpoints',
      (tester) async {
        mockCache.queue = [
          {'type': 'create_order', 'storeId': 'store-test'},
          {'type': 'record_payment', 'storeId': 'store-test'},
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LogoutDialog.show(
                  context,
                  ordersRepository: mockOrdersRepo,
                  localCache: mockCache,
                  authBloc: fakeAuthBloc,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Log out & sync?'), findsOneWidget);
        expect(
          find.text('2 unsynced orders/updates pending sync'),
          findsOneWidget,
        );
        expect(find.text('Logout & Sync'), findsOneWidget);

        await tester.tap(find.text('Logout & Sync'));
        await tester.pump();

        // Checkpoints rendered
        expect(find.text('Syncing pending orders to server'), findsOneWidget);
        expect(find.text('Pulling latest store data'), findsOneWidget);
        expect(find.text('Signing out'), findsOneWidget);

        // Let async sync complete
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(mockOrdersRepo.processQueueCallCount, 1);
        expect(mockOrdersRepo.syncDeltaCallCount, 1);
        expect(fakeAuthBloc.logoutEventReceived, isTrue);
      },
    );

    testWidgets(
      'Sync failure: shows error, Retry Sync and Log out anyway options',
      (tester) async {
        mockCache.queue = [
          {'type': 'create_order', 'storeId': 'store-test'},
        ];
        mockOrdersRepo.processQueueShouldSucceed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LogoutDialog.show(
                  context,
                  ordersRepository: mockOrdersRepo,
                  localCache: mockCache,
                  authBloc: fakeAuthBloc,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Logout & Sync'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(
            'Unable to reach server. Changes remain saved locally on this device.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry Sync'), findsOneWidget);
        expect(find.text('Log out anyway'), findsOneWidget);
        expect(fakeAuthBloc.logoutEventReceived, isFalse);

        // Tap Log out anyway
        await tester.tap(find.text('Log out anyway'));
        await tester.pumpAndSettle();

        expect(fakeAuthBloc.logoutEventReceived, isTrue);
      },
    );

    testWidgets('Logout pops all pushed screens back to root', (tester) async {
      mockCache.queue = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (pContext) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () => LogoutDialog.show(
                            pContext,
                            ordersRepository: mockOrdersRepo,
                            localCache: mockCache,
                            authBloc: fakeAuthBloc,
                          ),
                          child: const Text('Open From Subroute'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Root Screen'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Root Screen'));
      await tester.pumpAndSettle();

      expect(find.text('Open From Subroute'), findsOneWidget);

      await tester.tap(find.text('Open From Subroute'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(fakeAuthBloc.logoutEventReceived, isTrue);
      // Pushed screen must be popped, root screen visible
      expect(find.text('Root Screen'), findsOneWidget);
      expect(find.text('Open From Subroute'), findsNothing);
    });
  });
}
