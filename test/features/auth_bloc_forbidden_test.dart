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
  String? blockedReason;
  String role;

  FakeAuthRepository({this.blockedReason, this.role = 'EMPLOYEE'})
    : super(
        apiClient: ApiClient(),
        secureStorage: SecureStorageService(),
        localCache: LocalCacheService(),
      );

  @override
  Future<AuthResult?> checkSession() async {
    return AuthResult(
      user: User(id: 'u1', name: 'Priya', phone: 'priya'),
      stores: [
        StoreSummary(
          storeId: 's1',
          storeName: 'Test Store',
          role: role,
          blockedReason: blockedReason,
        ),
      ],
    );
  }

  @override
  Future<void> logout({bool involuntary = false}) async {
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
      authBloc = AuthBloc(
        authRepository: authRepository,
        localCache: localCache,
      );
      authBloc.add(CheckAuthStatusEvent());
      await authBloc.stream.firstWhere((s) => s is AuthenticatedState);
    });

    tearDown(() => authBloc.close());

    test('reason-less 403 forces sign-out instead of "store locked"', () async {
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
    });

    test('reasoned 403 still shows the blocked screen as before', () async {
      authBloc.add(
        AccessForbiddenEvent(reason: 'store_locked', paidThroughDate: null),
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

    test('billing_pending 403 emits AccessBlockedState with billing_pending reason', () async {
      authBloc.add(
        AccessForbiddenEvent(reason: 'billing_pending', paidThroughDate: null),
      );

      await expectLater(
        authBloc.stream,
        emits(
          isA<AccessBlockedState>().having(
            (s) => s.reason,
            'reason',
            'billing_pending',
          ),
        ),
      );

      expect(authRepository.loggedOut, isFalse);
    });

    test('checkSession returning billing_pending store emits AccessBlockedState and never AuthenticatedState', () async {
      final blockedRepo = FakeAuthRepository(
        blockedReason: 'billing_pending',
        role: 'OWNER',
      );
      final bloc = AuthBloc(
        authRepository: blockedRepo,
        localCache: localCache,
      );
      addTearDown(bloc.close);

      bloc.add(CheckAuthStatusEvent());

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<AuthLoadingState>(),
          isA<AccessBlockedState>()
              .having((s) => s.reason, 'reason', 'billing_pending')
              .having((s) => s.isOwner, 'isOwner', isTrue),
        ]),
      );
      expect(bloc.state is AuthenticatedState, isFalse);
    });

    test(
      'checkSession re-run after block cleared emits AuthenticatedState',
      () async {
        final mutableRepo = FakeAuthRepository(
          blockedReason: 'billing_pending',
          role: 'OWNER',
        );
        final bloc = AuthBloc(
          authRepository: mutableRepo,
          localCache: localCache,
        );
        addTearDown(bloc.close);

        bloc.add(CheckAuthStatusEvent());

        await expectLater(
          bloc.stream,
          emitsInOrder([
            isA<AuthLoadingState>(),
            isA<AccessBlockedState>().having(
              (s) => s.reason,
              'reason',
              'billing_pending',
            ),
          ]),
        );

        // Now block cleared (e.g. payment completed on web)
        mutableRepo.blockedReason = null;
        bloc.add(CheckAuthStatusEvent());

        await expectLater(
          bloc.stream,
          emitsInOrder([isA<AuthLoadingState>(), isA<AuthenticatedState>()]),
        );
      },
    );
  });
}
