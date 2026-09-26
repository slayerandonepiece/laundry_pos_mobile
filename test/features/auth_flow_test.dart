import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';

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
  String? _activeStoreId;

  @override
  String? getActiveStoreId() => _activeStoreId;

  @override
  Future<void> setActiveStoreId(String storeId) async =>
      _activeStoreId = storeId;

  @override
  String? getActiveOutletId() => null;

  @override
  Future<void> clear() async => _activeStoreId = null;
}

void main() {
  group('Auth Flow & 401 Loop Prevention Tests', () {
    test(
      'Login 401 failure does NOT trigger onUnauthorized callback',
      () async {
        bool unauthorizedCalled = false;

        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/auth/login')) {
            return mockJsonResponse({
              'error': 'Invalid username or password',
            }, statusCode: 401);
          }
          return mockJsonResponse({'ok': true});
        });

        final secureStorage = MockSecureStorage();
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: secureStorage,
          localCache: localCache,
          onUnauthorized: () {
            unauthorizedCalled = true;
          },
        );

        final authRepo = AuthRepository(
          apiClient: apiClient,
          secureStorage: secureStorage,
          localCache: localCache,
        );

        final authBloc = AuthBloc(
          authRepository: authRepo,
          localCache: localCache,
        );

        // Submit login with bad credentials
        authBloc.add(LoginSubmittedEvent(username: 'invalid', password: 'bad'));

        await expectLater(
          authBloc.stream,
          emitsInOrder([
            isA<AuthLoadingState>().having(
              (s) => s.isInitialCheck,
              'isInitialCheck',
              isFalse,
            ),
            isA<UnauthenticatedState>().having(
              (s) => s.errorMessage,
              'errorMessage',
              'Invalid username or password',
            ),
          ]),
        );

        // Verify onUnauthorized was NOT called for login endpoint
        expect(unauthorizedCalled, isFalse);

        authBloc.close();
      },
    );

    test(
      'Protected endpoint 401 DOES trigger onUnauthorized callback',
      () async {
        bool unauthorizedCalled = false;

        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/orders')) {
            return mockJsonResponse({
              'error': 'Session expired',
            }, statusCode: 401);
          }
          return mockJsonResponse({'ok': true});
        });

        final secureStorage = MockSecureStorage();
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          dio: mockDio,
          secureStorage: secureStorage,
          localCache: localCache,
          onUnauthorized: () {
            unauthorizedCalled = true;
          },
        );

        await expectLater(
          apiClient.get('https://example.com/api/v1/orders'),
          throwsA(isA<AuthException>()),
        );

        expect(unauthorizedCalled, isTrue);
      },
    );

    test(
      'SessionRevokedEvent is a no-op when already unauthenticated',
      () async {
        final mockDio = createMockDio(
          (options) async => mockJsonResponse({'ok': true}),
        );
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

        final authBloc = AuthBloc(
          authRepository: authRepo,
          localCache: localCache,
        );

        // Initial state is AuthInitialState (not AuthenticatedState)
        authBloc.add(SessionRevokedEvent());

        // Should not emit anything because state is not AuthenticatedState
        await Future.delayed(const Duration(milliseconds: 50));
        expect(authBloc.state, isA<AuthInitialState>());

        authBloc.close();
      },
    );

    test(
      'AuthRepository.changePassword saves updated token on success',
      () async {
        final mockDio = createMockDio((options) async {
          if (options.uri.path.contains('/api/v1/auth/change-password')) {
            return mockJsonResponse({
              'ok': true,
              'token': 'new-session-token-xyz',
            }, statusCode: 200);
          }
          return mockJsonResponse({'error': 'Not found'}, statusCode: 404);
        });
        final secureStorage = MockSecureStorage();
        await secureStorage.saveToken('old-token');
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

        await authRepo.changePassword('oldpass123', 'newpass123');
        expect(await secureStorage.getToken(), equals('new-session-token-xyz'));
      },
    );

    test('AuthRepository.changePassword propagates error when current password is wrong', () async {
      final mockDio = createMockDio((options) async {
        if (options.uri.path.contains('/api/v1/auth/change-password')) {
          return mockJsonResponse({
            'error': 'Current password is incorrect.',
          }, statusCode: 400);
        }
        return mockJsonResponse({'error': 'Not found'}, statusCode: 404);
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

      expect(
        () => authRepo.changePassword('wrongpass', 'newpass123'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Current password is incorrect.'),
          ),
        ),
      );
    });
  });
}
