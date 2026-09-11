import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_engine.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/profile/presentation/profile_screen.dart';

import '../helpers/mock_dio.dart';

class MockSecureStorage extends SecureStorageService {
  String? _token;

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}

class MockLocalCache extends LocalCacheService {
  List<Map<String, dynamic>> queue = [];
  bool clearCalled = false;

  @override
  String? getActiveStoreId() => 'store-1';

  @override
  List<Map<String, dynamic>> getPendingSyncQueue() => queue;

  @override
  Future<void> clear() async {
    clearCalled = true;
  }
}

class FakeConnectivityService extends ConnectivityService {
  bool offline = false;

  FakeConnectivityService({this.offline = false}) : super.internal();

  @override
  Future<bool> checkIsOffline() async => offline;
}

class FakeSyncEngine extends SyncEngine {
  bool retryNowCalled = false;
  VoidCallback? onRetry;

  FakeSyncEngine({this.onRetry}) : super.internal();

  @override
  Future<void> retryNow() async {
    retryNowCalled = true;
    onRetry?.call();
  }
}

class FakeAuthBloc extends AuthBloc {
  bool logoutEventReceived = false;

  FakeAuthBloc({required super.authRepository, super.localCache}) {
    emit(
      AuthenticatedState(
        user: User(id: 'u1', name: 'John Doe', username: 'john'),
        currentStore: StoreSummary(
          storeId: 's1',
          storeName: 'Main Store',
          role: 'OWNER',
        ),
        availableStores: [
          StoreSummary(storeId: 's1', storeName: 'Main Store', role: 'OWNER'),
        ],
        isFreshLogin: false,
      ),
    );
  }

  @override
  void add(AuthEvent event) {
    if (event is LogoutRequestedEvent) {
      logoutEventReceived = true;
      emit(UnauthenticatedState());
      return;
    }
    super.add(event);
  }
}

void main() {
  group('AuthRepository.logout() Tests', () {
    test('Successful logout calls POST /auth/logout, deletes token, and clears cache', () async {
      bool postLogoutCalled = false;
      final mockDio = createMockDio((options) async {
        if (options.uri.path.contains('/api/v1/auth/logout')) {
          postLogoutCalled = true;
          return mockJsonResponse({'ok': true});
        }
        return mockJsonResponse({'error': 'Not found'}, statusCode: 404);
      });

      final secureStorage = MockSecureStorage();
      await secureStorage.saveToken('test-session-token');
      final localCache = MockLocalCache();

      final apiClient = ApiClient(
        dio: mockDio,
        secureStorage: secureStorage,
        localCache: localCache,
      );

      final authRepo = AuthRepository(
        apiClient: apiClient,
        secureStorage: secureStorage,
        localCache: localCache,
      );

      await authRepo.logout();

      expect(postLogoutCalled, isTrue);
      expect(await secureStorage.getToken(), isNull);
      expect(localCache.clearCalled, isTrue);
    });

    test(
      'Network failure on logout rethrows and preserves token and local cache',
      () async {
        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/auth/logout')) {
            return mockJsonResponse({'error': 'Server error'}, statusCode: 500);
          }
          return mockJsonResponse({'error': 'Not found'}, statusCode: 404);
        });

        final secureStorage = MockSecureStorage();
        await secureStorage.saveToken('test-session-token');
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: secureStorage,
          localCache: localCache,
        );

        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: secureStorage,
          localCache: localCache,
        );

        expect(() => authRepo.logout(), throwsA(isA<ApiException>()));

        // Verify token and local cache remain intact
        expect(await secureStorage.getToken(), equals('test-session-token'));
        expect(localCache.clearCalled, isFalse);
      },
    );

    test('Skip network call if already logged out (token null)', () async {
      bool postLogoutCalled = false;
      final mockDio = createMockDio((options) async {
        postLogoutCalled = true;
        return mockJsonResponse({'ok': true});
      });

      final secureStorage = MockSecureStorage();
      final localCache = MockLocalCache();

      final apiClient = ApiClient(
        dio: mockDio,
        secureStorage: secureStorage,
        localCache: localCache,
      );

      final authRepo = AuthRepository(
        apiClient: apiClient,
        secureStorage: secureStorage,
        localCache: localCache,
      );

      await authRepo.logout();

      expect(postLogoutCalled, isFalse);
      expect(await secureStorage.getToken(), isNull);
      expect(localCache.clearCalled, isTrue);
    });
  });

  group('ProfileScreen Hardened Logout Flow Tests', () {
    late MockSecureStorage mockSecureStorage;
    late MockLocalCache mockLocalCache;

    Widget createTestableWidget({
      required ConnectivityService connectivityService,
      required LocalCacheService localCache,
      required SyncEngine syncEngine,
      required AuthRepository authRepository,
      required AuthBloc authBloc,
    }) {
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: authRepository),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: MaterialApp(
            home: ProfileScreen(
              connectivityService: connectivityService,
              localCache: localCache,
              syncEngine: syncEngine,
              authRepository: authRepository,
            ),
          ),
        ),
      );
    }

    setUp(() {
      mockSecureStorage = MockSecureStorage();
      mockLocalCache = MockLocalCache();
    });

    testWidgets(
      'Scenario 1: Offline -> shows offline dialog, stops, does not show confirm dialog',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        final fakeConnectivity = FakeConnectivityService(offline: true);
        final fakeSyncEngine = FakeSyncEngine();

        final apiClient = ApiClient(
          dio: createMockDio((_) async => mockJsonResponse({'ok': true})),
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        // Tap "Log out" row
        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        // Should show offline error dialog
        expect(find.text("You're offline"), findsOneWidget);
        expect(
          find.text("You're offline. Connect to the internet to log out."),
          findsOneWidget,
        );
        expect(find.text('OK'), findsOneWidget);

        // Confirm dialog should NOT be shown
        expect(find.text('Log out?'), findsNothing);

        // Tap "OK" to dismiss
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text("You're offline"), findsNothing);
        expect(fakeAuthBloc.logoutEventReceived, isFalse);
        expect(await mockSecureStorage.getToken(), equals('valid-token'));
      },
    );

    testWidgets(
      'Scenario 2a: Online, unsynced orders -> shows dialog, Cancel aborts logout',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [
          {'id': 'order-1', 'type': 'create'},
        ];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        final fakeSyncEngine = FakeSyncEngine();

        final apiClient = ApiClient(
          dio: createMockDio((_) async => mockJsonResponse({'ok': true})),
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        // Should show unsynced orders dialog
        expect(find.text('Unsynced orders'), findsOneWidget);
        expect(
          find.text('You have unsynced orders. Please sync them first.'),
          findsOneWidget,
        );
        expect(find.text('Sync now'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Tap Cancel -> dialog closes, no state change
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Unsynced orders'), findsNothing);
        expect(find.text('Log out?'), findsNothing);
        expect(fakeAuthBloc.logoutEventReceived, isFalse);
        expect(await mockSecureStorage.getToken(), equals('valid-token'));
      },
    );

    testWidgets(
      'Scenario 2b: Online, unsynced orders -> Sync now fails, shows inline error and remains open',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [
          {'id': 'order-1', 'type': 'create'},
        ];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        // Sync engine does not clear queue, simulating failure
        final fakeSyncEngine = FakeSyncEngine();

        final apiClient = ApiClient(
          dio: createMockDio((_) async => mockJsonResponse({'ok': true})),
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        // Tap "Sync now"
        await tester.tap(find.text('Sync now'));
        await tester.pumpAndSettle();

        expect(fakeSyncEngine.retryNowCalled, isTrue);
        // Inline error in the same dialog
        expect(
          find.text('Sync failed. Check your connection and try again.'),
          findsOneWidget,
        );
        expect(find.text('Sync now'), findsOneWidget);
        expect(find.text('Log out?'), findsNothing);
        expect(fakeAuthBloc.logoutEventReceived, isFalse);
      },
    );

    testWidgets(
      'Scenario 2c: Online, unsynced orders -> Sync now succeeds, proceeds to Log out? confirm dialog',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [
          {'id': 'order-1', 'type': 'create'},
        ];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        final fakeSyncEngine = FakeSyncEngine(
          onRetry: () {
            // Clear queue on retry
            mockLocalCache.queue = [];
          },
        );

        final apiClient = ApiClient(
          dio: createMockDio((_) async => mockJsonResponse({'ok': true})),
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        // Tap "Sync now"
        await tester.tap(find.text('Sync now'));
        await tester.pumpAndSettle();

        // Unsynced dialog closed, confirm dialog opened
        expect(find.text('Unsynced orders'), findsNothing);
        expect(find.text('Log out?'), findsOneWidget);
        expect(
          find.text(
            'You\'ll need to sign in again to take sales or manage orders.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Scenario 3a: Confirm dialog -> Cancel dismisses, stays logged in',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        final fakeSyncEngine = FakeSyncEngine();

        final apiClient = ApiClient(
          dio: createMockDio((_) async => mockJsonResponse({'ok': true})),
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsOneWidget);

        // Tap Cancel in confirm dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsNothing);
        expect(fakeAuthBloc.logoutEventReceived, isFalse);
        expect(await mockSecureStorage.getToken(), equals('valid-token'));
      },
    );

    testWidgets(
      'Scenario 3b: Confirm dialog -> API fails, surfaces error, stays logged in',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        final fakeSyncEngine = FakeSyncEngine();

        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/auth/logout')) {
            return mockJsonResponse({'error': 'Server error'}, statusCode: 500);
          }
          return mockJsonResponse({'ok': true});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        // Find the ElevatedButton 'Log out' in the confirm dialog
        final logoutButton = find.widgetWithText(ElevatedButton, 'Log out');
        await tester.tap(logoutButton);
        await tester.pumpAndSettle();

        // Dialog surfaces error and keeps user logged in
        expect(
          find.text("Couldn't log out. Please try again."),
          findsOneWidget,
        );
        expect(fakeAuthBloc.logoutEventReceived, isFalse);
        expect(await mockSecureStorage.getToken(), equals('valid-token'));
        expect(mockLocalCache.clearCalled, isFalse);
      },
    );

    testWidgets(
      'Scenario 3c: Confirm dialog -> API succeeds, flips AuthBloc state and clears session',
      (tester) async {
        await mockSecureStorage.saveToken('valid-token');
        mockLocalCache.queue = [];

        final fakeConnectivity = FakeConnectivityService(offline: false);
        final fakeSyncEngine = FakeSyncEngine();

        int apiCallCount = 0;
        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/auth/logout')) {
            apiCallCount++;
            return mockJsonResponse({'ok': true});
          }
          return mockJsonResponse({'ok': true});
        });

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: mockSecureStorage,
          localCache: mockLocalCache,
        );
        final fakeAuthBloc = FakeAuthBloc(
          authRepository: authRepo,
          localCache: mockLocalCache,
        );

        await tester.pumpWidget(
          createTestableWidget(
            connectivityService: fakeConnectivity,
            localCache: mockLocalCache,
            syncEngine: fakeSyncEngine,
            authRepository: authRepo,
            authBloc: fakeAuthBloc,
          ),
        );

        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        final logoutButton = find.widgetWithText(ElevatedButton, 'Log out');
        await tester.tap(logoutButton);
        await tester.pumpAndSettle();

        // Verify exactly ONE network call to /auth/logout
        expect(apiCallCount, equals(1));
        // AuthBloc received event and emitted unauthenticated
        expect(fakeAuthBloc.logoutEventReceived, isTrue);
        expect(fakeAuthBloc.state, isA<UnauthenticatedState>());
        // Token deleted and local cache cleared
        expect(await mockSecureStorage.getToken(), isNull);
        expect(mockLocalCache.clearCalled, isTrue);
      },
    );
  });
}
