import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';
import 'package:myshop/features/auth/data/models/user_model.dart';

class FakeAuthRepository extends AuthRepository {
  bool loggedOut = false;

  FakeAuthRepository()
    : super(
        apiClient: ApiClient(),
        secureStorage: SecureStorageService(),
        localCache: LocalCacheService(),
      );

  @override
  Future<AuthResult?> checkSession() async {
    return AuthResult(
      user: User(id: 'u1', name: 'Priya', username: 'priya'),
      stores: [
        StoreSummary(storeId: 's1', storeName: 'Test Store', role: 'EMPLOYEE'),
      ],
    );
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }
}

class InMemoryLocalCache extends LocalCacheService {
  final Map<String, dynamic> _memory = {};
  String? clearedActiveOutletId;

  @override
  String? getActiveStoreId() => _memory['active_store_id'] as String?;
  @override
  Future<void> setActiveStoreId(String s) async =>
      _memory['active_store_id'] = s;

  @override
  Map<String, dynamic>? getCachedStoreDetails() =>
      _memory['store_details'] as Map<String, dynamic>?;
  @override
  Future<void> setCachedStoreDetails(Map<String, dynamic> s) async =>
      _memory['store_details'] = s;

  @override
  Future<void> setCachedAvailableStores(List<Map<String, dynamic>> l) async {}
  @override
  Future<void> setCachedUser(Map<String, dynamic> u) async {}

  @override
  String? getActiveOutletId() => _memory['active_outlet_id'] as String?;
  @override
  Future<void> clearActiveOutletId() async {
    clearedActiveOutletId = 'cleared';
    _memory.remove('active_outlet_id');
  }
}

void main() {
  group('AuthBloc._onAccessForbidden', () {
    late FakeAuthRepository authRepository;
    late InMemoryLocalCache localCache;
    late AuthBloc authBloc;

    setUp(() async {
      authRepository = FakeAuthRepository();
      localCache = InMemoryLocalCache();
      authBloc = AuthBloc(authRepository: authRepository, localCache: localCache);
      authBloc.add(CheckAuthStatusEvent());
      await authBloc.stream.firstWhere((s) => s is AuthenticatedState);
    });

    tearDown(() => authBloc.close());

    test(
      'reason-less 403 forces sign-out instead of "store locked"',
      () async {
        authBloc.add(AccessForbiddenEvent());

        await expectLater(
          authBloc.stream,
          emits(
            isA<UnauthenticatedState>().having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('sign in again'),
            ),
          ),
        );

        expect(authRepository.loggedOut, isTrue);
        expect(localCache.clearedActiveOutletId, 'cleared');
      },
    );

    test('reasoned 403 still shows the blocked screen as before', () async {
      authBloc.add(
        AccessForbiddenEvent(
          reason: 'store_locked',
          paidThroughDate: null,
        ),
      );

      await expectLater(
        authBloc.stream,
        emits(
          isA<AccessBlockedState>().having(
            (s) => s.reason,
            'reason',
            'store_locked',
          ),
        ),
      );

      expect(authRepository.loggedOut, isFalse);
    });
  });
}
