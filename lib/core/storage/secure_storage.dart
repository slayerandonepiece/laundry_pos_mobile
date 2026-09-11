import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _keyToken = 'el_session_token';

  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// Saves the session token securely in Keychain / Keystore
  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// Retrieves the session token
  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  /// Deletes the session token (used on sign out or 401 revocation)
  Future<void> deleteToken() async {
    await _storage.delete(key: _keyToken);
  }

  /// Clears all secure storage
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
