import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/features/auth/presentation/account_restore_screen.dart';
import 'package:myshop/features/profile/presentation/delete_account_screen.dart';

import '../helpers/mock_dio.dart';

class _Storage extends SecureStorageService {
  String? token = 'tok-secret-123456789';
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> saveToken(String t) async => token = t;
  @override
  Future<void> deleteToken() async => token = null;
}

/// In-memory stand-in for the Hive-backed cache.
class _Cache extends LocalCacheService {
  final Map<String, dynamic> m = {};

  @override
  String? getActiveStoreId() => m['store'] as String?;
  @override
  Future<void> setActiveStoreId(String s) async => m['store'] = s;
  @override
  String? getActiveOutletId() => null;
  @override
  Map<String, dynamic>? getCachedUser() => m['user'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedUser(Map<String, dynamic> u) async => m['user'] = u;
  @override
  Map<String, dynamic>? getCachedStoreDetails() =>
      m['details'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> d) async =>
      m['details'] = d;
  @override
  List<Map<String, dynamic>>? getCachedAvailableStores() =>
      (m['stores'] as List?)?.cast<Map<String, dynamic>>();
  @override
  Future<void> setCachedAvailableStores(List<Map<String, dynamic>> l) async =>
      m['stores'] = l;
  @override
  Future<void> setAllowedOutletsForStore(
    String storeId,
    List<Map<String, dynamic>> outlets,
  ) async {}
  @override
  List<Map<String, dynamic>> getPendingSyncQueue() =>
      ((m['pending'] as List?) ?? const []).cast<Map<String, dynamic>>();
  @override
  List<Map<String, dynamic>> getDeadLetterQueue() => const [];
  @override
  List<Map<String, dynamic>> getPendingOwnerActionsQueue() => const [];
  @override
  List<Map<String, dynamic>> getDeadLetterOwnerActionsQueue() => const [];
  @override
  Future<void> setPendingSyncQueue(List<Map<String, dynamic>> q) async =>
      m['pending'] = q;
  @override
  Future<void> setDeadLetterQueue(List<Map<String, dynamic>> q) async {}
  @override
  Future<void> setPendingOwnerActionsQueue(
    List<Map<String, dynamic>> q,
  ) async {}
  @override
  Future<void> setDeadLetterOwnerActionsQueue(
    List<Map<String, dynamic>> q,
  ) async {}
  @override
  dynamic get(String key) => m[key];
  @override
  Future<void> put(String key, dynamic value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
  @override
  Future<void> clear() async => m.clear();
}

class _Connectivity extends ConnectivityService {
  _Connectivity({this.offline = false}) : super.internal();
  final bool offline;
  @override
  Future<bool> checkIsOffline() async => offline;
}

class _MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _MockAuthBloc(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthRepository _repo(_Storage s, _Cache c, MockDioHandler handler) =>
    AuthRepository(
      apiClient: ApiClient(
        dio: createMockDio(handler),
        secureStorage: s,
        localCache: c,
      ),
      secureStorage: s,
      localCache: c,
    );

AuthenticatedState _signedIn({required String role}) => AuthenticatedState(
  user: User(id: 'u1', name: 'Priya', phone: '9876543210'),
  currentStore: StoreSummary(storeId: 's1', storeName: 'Store 1', role: role),
  availableStores: [
    StoreSummary(storeId: 's1', storeName: 'Store 1', role: role),
  ],
);

Widget _host(Widget child, AuthBloc bloc) => MaterialApp(
  home: BlocProvider<AuthBloc>.value(value: bloc, child: child),
);

void main() {
  late _Storage storage;
  late _Cache cache;

  setUp(() {
    storage = _Storage();
    cache = _Cache();
    SyncFreshness.reset();
  });
  tearDown(SyncFreshness.reset);

  group('AuthRepository', () {
    test(
      'requestAccountDeletion posts the store id and returns the date',
      () async {
        RequestOptions? seen;
        final repo = _repo(storage, cache, (o) async {
          seen = o;
          return mockJsonResponse({
            'status': 'PENDING',
            'scheduledFor': '2027-01-02T00:00:00.000Z',
          });
        });

        final date = await repo.requestAccountDeletion(storeId: 's1');

        expect(date, '2027-01-02T00:00:00.000Z');
        expect(seen!.uri.path, '/api/v1/account/deletion');
        expect(seen!.data, {'storeId': 's1'});
      },
    );

    test('requestAccountDeletion rejects a reply without a date', () async {
      final repo = _repo(
        storage,
        cache,
        (o) async => mockJsonResponse({'status': 'PENDING'}),
      );

      expect(
        repo.requestAccountDeletion(storeId: 's1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('restoreAccount posts to the restore endpoint', () async {
      RequestOptions? seen;
      final repo = _repo(storage, cache, (o) async {
        seen = o;
        return mockJsonResponse({'status': 'RESTORED'});
      });

      await repo.restoreAccount();

      expect(seen!.method, 'POST');
      expect(seen!.uri.path, '/api/v1/account/deletion/restore');
    });
  });

  group('AuthBloc', () {
    Map<String, dynamic> status({
      String? scheduledFor,
      String role = 'OWNER',
    }) => {
      'user': {
        'id': 'u1',
        'name': 'Priya',
        'phone': '9876543210',
        'deletionScheduledFor': ?scheduledFor,
      },
      'stores': [
        {'storeId': 's1', 'storeName': 'Store 1', 'role': role},
      ],
    };

    test(
      'a pending deletion lands on the restore state, not the app',
      () async {
        final bloc = AuthBloc(
          authRepository: _repo(
            storage,
            cache,
            (o) async => mockJsonResponse(
              status(scheduledFor: '2027-01-02T00:00:00.000Z'),
            ),
          ),
          localCache: cache,
        );

        bloc.add(CheckAuthStatusEvent());
        await bloc.stream.firstWhere((s) => s is DeletionPendingState);

        final state = bloc.state as DeletionPendingState;
        expect(state.scheduledFor, '2027-01-02T00:00:00.000Z');
        expect(state.isOwner, isTrue);
        await bloc.close();
      },
    );

    test('no pending deletion signs in normally', () async {
      final bloc = AuthBloc(
        authRepository: _repo(
          storage,
          cache,
          (o) async => mockJsonResponse(status(role: 'EMPLOYEE')),
        ),
        localCache: cache,
      );

      bloc.add(CheckAuthStatusEvent());
      await bloc.stream.firstWhere((s) => s is AuthenticatedState);
      await bloc.close();
    });
  });

  group('DeleteAccountScreen', () {
    testWidgets('owner must type DELETE before the button works', (
      tester,
    ) async {
      var requested = 0;
      final bloc = _MockAuthBloc(_signedIn(role: 'OWNER'));
      final repo = _repo(storage, cache, (o) async {
        requested++;
        return mockJsonResponse({'scheduledFor': '2027-01-02T00:00:00.000Z'});
      });

      await tester.pumpWidget(
        _host(
          DeleteAccountScreen(
            connectivityService: _Connectivity(),
            localCache: cache,
            authRepository: repo,
          ),
          bloc,
        ),
      );

      await tester.tap(find.text('Delete store and all data'));
      await tester.pump();
      expect(requested, 0);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete store and all data'));
      await tester.pumpAndSettle();

      expect(requested, 1);
      expect(find.text('Deletion requested'), findsOneWidget);
      expect(find.textContaining('2 Jan 2027'), findsOneWidget);
    });

    testWidgets('employee sees only their phone and no typed confirmation', (
      tester,
    ) async {
      final bloc = _MockAuthBloc(_signedIn(role: 'EMPLOYEE'));

      await tester.pumpWidget(
        _host(
          DeleteAccountScreen(
            connectivityService: _Connectivity(),
            localCache: cache,
            authRepository: _repo(
              storage,
              cache,
              (o) async => mockJsonResponse({}),
            ),
          ),
          bloc,
        ),
      );

      expect(find.text('9876543210'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Delete my account'), findsOneWidget);
      expect(find.text('Keep my account'), findsOneWidget);
    });

    testWidgets('offline blocks the request with a message', (tester) async {
      var requested = 0;
      final bloc = _MockAuthBloc(_signedIn(role: 'EMPLOYEE'));

      await tester.pumpWidget(
        _host(
          DeleteAccountScreen(
            connectivityService: _Connectivity(offline: true),
            localCache: cache,
            authRepository: _repo(storage, cache, (o) async {
              requested++;
              return mockJsonResponse({});
            }),
          ),
          bloc,
        ),
      );

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();

      expect(requested, 0);
      expect(find.textContaining("You're offline"), findsOneWidget);
    });

    testWidgets('unsynced orders block the request', (tester) async {
      var requested = 0;
      cache.m['pending'] = [
        {'id': 'o1'},
      ];
      final bloc = _MockAuthBloc(_signedIn(role: 'EMPLOYEE'));

      await tester.pumpWidget(
        _host(
          DeleteAccountScreen(
            connectivityService: _Connectivity(),
            localCache: cache,
            authRepository: _repo(storage, cache, (o) async {
              requested++;
              return mockJsonResponse({});
            }),
          ),
          bloc,
        ),
      );

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();

      expect(requested, 0);
      expect(find.textContaining('unsynced orders'), findsOneWidget);
    });
  });

  group('AccountRestoreScreen', () {
    testWidgets('restore calls the server then hands control back', (
      tester,
    ) async {
      var restored = 0;
      var signedOut = 0;
      RequestOptions? seen;
      final repo = _repo(storage, cache, (o) async {
        seen = o;
        return mockJsonResponse({'status': 'RESTORED'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AccountRestoreScreen(
            scheduledFor: '2027-01-02T00:00:00.000Z',
            isOwner: true,
            authRepository: repo,
            onRestored: () => restored++,
            onSignOut: () => signedOut++,
          ),
        ),
      );

      expect(find.textContaining('2 Jan 2027'), findsOneWidget);

      await tester.tap(find.text('Restore my account'));
      // The spinner stays up until the re-check replaces this screen, so it
      // never settles when the screen is hosted alone.
      await tester.pump(const Duration(milliseconds: 100));

      expect(seen!.uri.path, '/api/v1/account/deletion/restore');
      expect(restored, 1);
      expect(signedOut, 0);
    });

    testWidgets('a failed restore shows the error and stays put', (
      tester,
    ) async {
      var restored = 0;
      final repo = _repo(
        storage,
        cache,
        (o) async => mockJsonResponse({'error': 'Too late'}, statusCode: 400),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AccountRestoreScreen(
            scheduledFor: '2027-01-02T00:00:00.000Z',
            isOwner: false,
            authRepository: repo,
            onRestored: () => restored++,
            onSignOut: () {},
          ),
        ),
      );

      await tester.tap(find.text('Restore my account'));
      await tester.pumpAndSettle();

      expect(restored, 0);
      expect(find.text('Too late'), findsOneWidget);
    });

    testWidgets('continue with deletion signs out', (tester) async {
      var signedOut = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AccountRestoreScreen(
            scheduledFor: '2027-01-02T00:00:00.000Z',
            isOwner: false,
            authRepository: _repo(
              storage,
              cache,
              (o) async => mockJsonResponse({}),
            ),
            onRestored: () {},
            onSignOut: () => signedOut++,
          ),
        ),
      );

      await tester.tap(find.text('Continue with deletion'));
      await tester.pump();

      expect(signedOut, 1);
    });
  });
}
