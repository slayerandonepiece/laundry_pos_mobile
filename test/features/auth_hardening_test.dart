import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/network/dio_interceptors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';
import 'package:myshop/main.dart'
    show OutletAccessResolution, resolveOutletAccessLost;

import '../helpers/mock_dio.dart';

class _Storage extends SecureStorageService {
  String? token;
  _Storage([this.token = 'tok-secret-123456789']);
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
  int clearCount = 0;

  @override
  String? getActiveStoreId() => m['store'] as String?;
  @override
  Future<void> setActiveStoreId(String s) async => m['store'] = s;
  @override
  String? getActiveOutletId() => null;
  @override
  Future<void> clearActiveOutletId() async {}
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
  Map<String, dynamic>? getCachedStoreProfile() =>
      m['profile'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreProfile(Map<String, dynamic> d) async =>
      m['profile'] = d;
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
  ) async => m['outlets::$storeId'] = outlets;
  @override
  List<Map<String, dynamic>>? getAllowedOutlets() =>
      m['outlets::${m['store']}'] as List<Map<String, dynamic>>?;

  List<Map<String, dynamic>> _list(String k) =>
      ((m[k] as List?) ?? const []).cast<Map<String, dynamic>>().toList();
  @override
  List<Map<String, dynamic>> getPendingSyncQueue() => _list('pending');
  @override
  Future<void> setPendingSyncQueue(List<Map<String, dynamic>> q) async =>
      m['pending'] = q;
  @override
  List<Map<String, dynamic>> getDeadLetterQueue() => _list('dead');
  @override
  Future<void> setDeadLetterQueue(List<Map<String, dynamic>> q) async =>
      m['dead'] = q;
  @override
  List<Map<String, dynamic>> getPendingOwnerActionsQueue() => _list('opend');
  @override
  Future<void> setPendingOwnerActionsQueue(
    List<Map<String, dynamic>> q,
  ) async => m['opend'] = q;
  @override
  List<Map<String, dynamic>> getDeadLetterOwnerActionsQueue() => _list('odead');
  @override
  Future<void> setDeadLetterOwnerActionsQueue(
    List<Map<String, dynamic>> q,
  ) async => m['odead'] = q;

  @override
  dynamic get(String key) => m[key];
  @override
  Future<void> put(String key, dynamic value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);

  @override
  Future<void> clear() async {
    clearCount++;
    m.clear();
  }
}

const _statusBody = {
  'user': {'id': 'u1', 'name': 'Priya', 'phone': 'priya'},
  'stores': [
    {'storeId': 's1', 'storeName': 'Store 1', 'role': 'OWNER'},
  ],
};

AuthRepository _repo(_Storage storage, _Cache cache, MockDioHandler handler) =>
    AuthRepository(
      apiClient: ApiClient(
        dio: createMockDio(handler),
        secureStorage: storage,
        localCache: cache,
      ),
      secureStorage: storage,
      localCache: cache,
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

  group('C2: logout with a dead session always signs out', () {
    test(
      'voluntary logout: 401 from /auth/logout still clears token+cache',
      () async {
        final repo = _repo(storage, cache, (o) async {
          return mockJsonResponse({'error': 'Unauthorized'}, statusCode: 401);
        });
        await repo.logout();
        expect(storage.token, isNull);
        expect(cache.clearCount, 1);
      },
    );

    test('involuntary logout never throws and clears on 401, 500 and no connection', () async {
      for (final status in [401, 403, 500]) {
        storage.token = 'tok';
        cache.clearCount = 0;
        final repo = _repo(storage, cache, (o) async {
          return mockJsonResponse({'error': 'x'}, statusCode: status);
        });
        await repo.logout(involuntary: true);
        expect(storage.token, isNull, reason: 'status $status');
        expect(cache.clearCount, 1, reason: 'status $status');
      }
      storage.token = 'tok';
      final offline = _repo(storage, cache, (o) async {
        throw Exception('Connection refused');
      });
      await offline.logout(involuntary: true);
      expect(storage.token, isNull);
    });

    test('involuntary logout resets SyncFreshness', () async {
      SyncFreshness.mark();
      final repo = _repo(storage, cache, (o) async => mockJsonResponse({}));
      await repo.logout(involuntary: true);
      expect(SyncFreshness.isFresh, isFalse);
    });

    test(
      'SessionRevokedEvent with a revoked token reaches UnauthenticatedState',
      () async {
        final repo = _repo(storage, cache, (o) async {
          if (o.uri.path.contains('/auth/status')) {
            return mockJsonResponse(_statusBody);
          }
          return mockJsonResponse({'error': 'Unauthorized'}, statusCode: 401);
        });
        final bloc = AuthBloc(authRepository: repo, localCache: cache);
        addTearDown(bloc.close);
        bloc.add(CheckAuthStatusEvent());
        await bloc.stream.firstWhere((s) => s is AuthenticatedState);

        bloc.add(SessionRevokedEvent());
        await expectLater(bloc.stream, emits(isA<UnauthenticatedState>()));
        expect(storage.token, isNull);
        expect(cache.clearCount, greaterThan(0));
      },
    );

    test('a logout that throws still ends in UnauthenticatedState', () async {
      final bloc = AuthBloc(
        authRepository: _ThrowingLogoutRepo(storage, cache),
        localCache: cache,
      );
      addTearDown(bloc.close);
      bloc.add(CheckAuthStatusEvent());
      await bloc.stream.firstWhere((s) => s is AuthenticatedState);

      bloc.add(AccessForbiddenEvent());
      await expectLater(bloc.stream, emits(isA<UnauthenticatedState>()));
    });

    test('involuntary sign-out keeps unsynced queues and re-login to the same store restores them', () async {
      cache.m['store'] = 's1';
      cache.m['pending'] = [
        {'id': 'a1', 'type': 'create_order'},
      ];
      cache.m['odead'] = [
        {'id': 'o1'},
      ];
      final repo = _repo(storage, cache, (o) async {
        if (o.uri.path.contains('/auth/login')) {
          return mockJsonResponse({..._statusBody, 'token': 'new-token'});
        }
        return mockJsonResponse({'error': 'Unauthorized'}, statusCode: 401);
      });

      await repo.logout(involuntary: true);
      expect(cache.getPendingSyncQueue(), isEmpty); // session wiped
      expect(cache.get('$keyParkedUnsynced::s1'), isNotNull); // but parked

      await repo.login('priya', 'pw');
      expect(cache.getPendingSyncQueue().map((a) => a['id']), ['a1']);
      expect(cache.getDeadLetterOwnerActionsQueue().map((a) => a['id']), [
        'o1',
      ]);
      expect(cache.get('$keyParkedUnsynced::s1'), isNull);
    });

    test(
      'a different store signing in does not receive the parked queue',
      () async {
        cache.m['store'] = 'other';
        cache.m['pending'] = [
          {'id': 'a1'},
        ];
        final repo = _repo(storage, cache, (o) async {
          if (o.uri.path.contains('/auth/login')) {
            return mockJsonResponse({..._statusBody, 'token': 't'});
          }
          return mockJsonResponse({}, statusCode: 401);
        });
        await repo.logout(involuntary: true);
        await repo.login('priya', 'pw'); // signs into s1
        expect(cache.getPendingSyncQueue(), isEmpty);
      },
    );

    test('voluntary logout still wipes everything (no parking)', () async {
      cache.m['store'] = 's1';
      cache.m['pending'] = [
        {'id': 'a1'},
      ];
      final repo = _repo(storage, cache, (o) async => mockJsonResponse({}));
      await repo.logout();
      expect(cache.m, isEmpty);
    });
  });

  group('M3: refreshOutletContext', () {
    test(
      '500 and connection errors return null and keep the cached outlets',
      () async {
        await cache.setActiveStoreId('s1');
        await cache.setAllowedOutletsForStore('s1', [
          {'id': 'o1'},
        ]);
        var mode = '500';
        final repo = _repo(storage, cache, (o) async {
          if (mode == 'net') throw Exception('Connection refused');
          return mockJsonResponse({'error': 'boom'}, statusCode: 500);
        });
        expect(await repo.refreshOutletContext(), isNull);
        mode = 'net';
        expect(await repo.refreshOutletContext(), isNull);
        expect(cache.getAllowedOutlets(), [
          {'id': 'o1'},
        ]);
        expect(storage.token, isNotNull);
      },
    );

    test('403 is surfaced as AuthException, not swallowed as null', () async {
      final repo = _repo(storage, cache, (o) async {
        return mockJsonResponse({'error': 'no'}, statusCode: 403);
      });
      await expectLater(
        repo.refreshOutletContext(),
        throwsA(isA<AuthException>()),
      );
    });

    test('resolveOutletAccessLost: flaky network keeps user signed in, 403 signs out', () async {
      expect(
        await resolveOutletAccessLost(
          previousOutletId: 'o1',
          refresh: () async => null,
        ),
        OutletAccessResolution.keepSignedIn,
      );
      expect(
        await resolveOutletAccessLost(
          previousOutletId: 'o1',
          refresh: () async => throw AuthException(code: 'FORBIDDEN'),
        ),
        OutletAccessResolution.signOut,
      );
      expect(
        await resolveOutletAccessLost(
          previousOutletId: 'o1',
          refresh: () async => [
            {'id': 'o2'},
          ],
        ),
        OutletAccessResolution.outletRevoked,
      );
      expect(
        await resolveOutletAccessLost(
          previousOutletId: 'o1',
          refresh: () async => [
            {'id': 'o1'},
          ],
        ),
        OutletAccessResolution.signOut,
      );
    });

    test('fetchStoreDetails rethrows 401/403 but serves the cache on a network error', () async {
      await cache.setCachedStoreProfile({'store': 'Cached'});
      var mode = '401';
      final repo = _repo(storage, cache, (o) async {
        if (mode == 'net') throw Exception('Connection refused');
        return mockJsonResponse({
          'error': 'x',
        }, statusCode: mode == '401' ? 401 : 403);
      });
      await expectLater(
        repo.fetchStoreDetails(),
        throwsA(isA<AuthException>()),
      );
      mode = '403';
      await expectLater(
        repo.fetchStoreDetails(),
        throwsA(isA<AuthException>()),
      );
      mode = 'net';
      expect(await repo.fetchStoreDetails(), {'store': 'Cached'});
    });
  });

  group('M4: checkSession fallback', () {
    Future<void> seedSession() async {
      await cache.setCachedUser({
        'id': 'u1',
        'name': 'Priya',
        'phone': 'priya',
      });
      await cache.setCachedStoreDetails({
        'storeId': 's1',
        'storeName': 'Store 1',
        'role': 'OWNER',
      });
    }

    test('5xx and connection errors fall back to the cached session', () async {
      await seedSession();
      var net = false;
      final repo = _repo(storage, cache, (o) async {
        if (net) throw Exception('Connection refused');
        return mockJsonResponse({'error': 'boom'}, statusCode: 502);
      });
      expect(await repo.checkSession(), isNotNull);
      net = true;
      expect(await repo.checkSession(), isNotNull);
    });

    test('a malformed payload does not open the cached session', () async {
      await seedSession();
      final repo = _repo(storage, cache, (o) async {
        return mockJsonResponse({'user': 'not-a-map'});
      });
      expect(await repo.checkSession(), isNull);
    });
  });

  group('M9: logging never leaks credentials', () {
    late List<String> lines;
    late DebugPrintCallback original;

    setUp(() {
      lines = [];
      original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    });
    tearDown(() => debugPrint = original);

    test('no token, password or bearer fragment appears in logs', () async {
      final client = ApiClient(
        dio: createMockDio((o) async {
          if (o.uri.path.contains('/auth/login')) {
            return mockJsonResponse({
              'token': 'LEAKED-TOKEN-VALUE',
              'user': {'phone': '9999988888'},
            });
          }
          return mockJsonResponse({
            'data': {'accessToken': 'NESTED-SECRET-TOKEN', 'ok': 1},
          });
        }),
        secureStorage: _Storage('Bearer-token-abcdefghijklmnop'),
        localCache: cache,
      );
      await client.post(
        'https://example.com/api/v1/auth/login',
        body: {'phone': '9999988888', 'password': 'hunter2-pass'},
      );
      await client.get('https://example.com/api/v1/things');
      final all = lines.join('\n');
      expect(all, isNot(contains('LEAKED-TOKEN-VALUE')));
      expect(all, isNot(contains('hunter2-pass')));
      expect(all, isNot(contains('9999988888'))); // no auth body at all
      expect(all, isNot(contains('NESTED-SECRET-TOKEN')));
      expect(all, isNot(contains('Bearer-toke')));
      expect(all, isNot(contains('mnop')));
      expect(all, contains('"ok":1')); // ordinary bodies still logged
    });
  });

  group('L4: 403 with non-string reason', () {
    test('does not throw a TypeError; reason is stringified', () async {
      final client = ApiClient(
        dio: createMockDio((o) async {
          return mockJsonResponse({
            'reason': 42,
            'paidThroughDate': 20260930,
          }, statusCode: 403);
        }),
        secureStorage: storage,
        localCache: cache,
      );
      String? seen;
      client.onForbidden = (reason, _) => seen = reason;
      await expectLater(
        client.get('https://example.com/api/v1/x'),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'code', 'FORBIDDEN'),
        ),
      );
      expect(seen, '42');
    });
  });

  group('NetworkHealth', () {
    test('counts connection errors and 5xx but not 401/404', () async {
      var status = 500;
      final client = ApiClient(
        dio: createMockDio((o) async {
          if (status == 0) throw Exception('Connection refused');
          return mockJsonResponse({'error': 'x'}, statusCode: status);
        }),
        secureStorage: storage,
        localCache: cache,
      );
      Future<int> delta(int s) async {
        status = s;
        final before = NetworkHealth.failures;
        try {
          await client.get('https://example.com/api/v1/x');
        } catch (_) {}
        return NetworkHealth.failures - before;
      }

      expect(await delta(500), 1);
      expect(await delta(0), 1);
      expect(await delta(401), 0);
      expect(await delta(404), 0);
    });
  });
}

class _ThrowingLogoutRepo extends AuthRepository {
  _ThrowingLogoutRepo(_Storage s, _Cache c)
    : super(
        apiClient: ApiClient(secureStorage: s, localCache: c),
        secureStorage: s,
        localCache: c,
      );

  @override
  Future<AuthResult?> checkSession() async => AuthResult(
    user: User(id: 'u1', name: 'Priya', phone: 'priya'),
    stores: [StoreSummary(storeId: 's1', storeName: 'S', role: 'OWNER')],
  );

  @override
  Future<void> logout({bool involuntary = false}) async =>
      throw StateError('disk full');
}
