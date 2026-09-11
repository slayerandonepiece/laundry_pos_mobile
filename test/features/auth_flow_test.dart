import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/auth/bloc/auth_bloc.dart';
import 'package:myshop/features/auth/bloc/auth_event.dart';
import 'package:myshop/features/auth/bloc/auth_state.dart';
import 'package:myshop/features/auth/data/auth_repository.dart';

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
  Future<void> clear() async => _activeStoreId = null;
}

void main() {
  group('Auth Flow & 401 Loop Prevention Tests', () {
    test(
      'Login 401 failure does NOT trigger onUnauthorized callback',
      () async {
        bool unauthorizedCalled = false;

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/api/v1/auth/login')) {
            return http.Response(
              '{"error":"Invalid username or password"}',
              401,
            );
          }
          return http.Response('{"ok":true}', 200);
        });

        final secureStorage = MockSecureStorage();
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          client: mockClient,
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

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/api/v1/orders')) {
            return http.Response('{"error":"Session expired"}', 401);
          }
          return http.Response('{"ok":true}', 200);
        });

        final secureStorage = MockSecureStorage();
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          client: mockClient,
          secureStorage: secureStorage,
          localCache: localCache,
          onUnauthorized: () {
            unauthorizedCalled = true;
          },
        );

        expect(
          () => apiClient.get('https://example.com/api/v1/orders'),
          throwsA(isA<AuthException>()),
        );

        // Allow microtask
        await Future.delayed(Duration.zero);
        expect(unauthorizedCalled, isTrue);
      },
    );

    test(
      'SessionRevokedEvent is a no-op when already unauthenticated',
      () async {
        final mockClient = MockClient(
          (request) async => http.Response('{"ok":true}', 200),
        );
        final secureStorage = MockSecureStorage();
        final localCache = MockLocalCache();

        final apiClient = ApiClient(
          client: mockClient,
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
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/api/v1/auth/change-password')) {
            return http.Response(
              '{"ok":true,"token":"new-session-token-xyz"}',
              200,
            );
          }
          return http.Response('{"error":"Not found"}', 404);
        });
        final secureStorage = MockSecureStorage();
        await secureStorage.saveToken('old-token');
        final localCache = MockLocalCache();
        final apiClient = ApiClient(
          client: mockClient,
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
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/auth/change-password')) {
          return http.Response(
            '{"error":"Current password is incorrect."}',
            400,
          );
        }
        return http.Response('{"error":"Not found"}', 404);
      });
      final secureStorage = MockSecureStorage();
      final localCache = MockLocalCache();
      final apiClient = ApiClient(
        client: mockClient,
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
