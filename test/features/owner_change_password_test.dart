import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';

class _PostRecordingApiClient implements ApiClient {
  Object? lastBody;

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    lastBody = body;
    return {'ok': true, 'token': 'tok_rotated'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureStorage extends SecureStorageService {
  String? token = 'tok_old';

  @override
  Future<void> saveToken(String t) async => token = t;
}

void main() {
  test(
    'owner changePassword sends oldPassword and stores the rotated token',
    () async {
      final api = _PostRecordingApiClient();
      final storage = _FakeSecureStorage();
      final repo = OwnerRepository(
        apiClient: api,
        localCache: LocalCacheService(),
        secureStorage: storage,
      );

      await repo.changePassword(
        currentPassword: 'OldPass123',
        newPassword: 'NewPass123',
      );

      expect(api.lastBody, {
        'oldPassword': 'OldPass123',
        'newPassword': 'NewPass123',
      });
      expect(storage.token, 'tok_rotated');
    },
  );
}
