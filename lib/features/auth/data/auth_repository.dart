import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';

import 'models/user_model.dart';

class AuthResult {
  final User user;
  final List<StoreSummary> stores;

  AuthResult({required this.user, required this.stores});
}

class AuthRepository {
  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  final LocalCacheService _localCache;

  AuthRepository({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
    LocalCacheService? localCache,
  }) : _secureStorage = secureStorage ?? SecureStorageService(),
       _localCache = localCache ?? LocalCacheService(),
       _apiClient = apiClient ?? ApiClient();

  /// Logs in using username and password
  Future<AuthResult> login(String username, String password) async {
    final response = await _apiClient.post(
      ApiEndpoints.login,
      body: {'username': username.trim(), 'password': password},
    );

    if (response is Map) {
      final token = response['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
      }

      final userJson = Map<String, dynamic>.from(response['user'] as Map);
      final user = User.fromJson(userJson);
      await _localCache.setCachedUser(user.toJson());

      final rawStores = response['stores'] as List? ?? [];
      final stores = rawStores
          .map(
            (s) => StoreSummary.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList();

      await _localCache.setCachedAvailableStores(
        stores.map((s) => s.toJson()).toList(),
      );

      if (stores.isNotEmpty) {
        final currentActive = _localCache.getActiveStoreId();
        final active = stores.firstWhere(
          (s) => s.storeId == currentActive,
          orElse: () => stores.first,
        );
        await _localCache.setActiveStoreId(active.storeId);
        await _localCache.setCachedStoreDetails(active.toJson());
      }

      await _cacheOrganizationOutlets(response);

      return AuthResult(user: user, stores: stores);
    }
    throw ApiException('Invalid response format from login endpoint');
  }

  /// Caches every organization's `allowedOutlets` (not just the active store's),
  /// the same way [setCachedAvailableStores] caches every store's summary — so
  /// switching stores later finds that store's outlets already cached.
  /// If the response has no `'organizations'` key at all (older server), does
  /// nothing so existing cached outlets are never overwritten with `[]`.
  Future<void> _cacheOrganizationOutlets(Map response) async {
    if (!response.containsKey('organizations')) return;
    final rawOrganizations = response['organizations'];
    if (rawOrganizations is! List) return;
    for (final org in rawOrganizations) {
      if (org is! Map) continue;
      final orgMap = Map<String, dynamic>.from(org);
      final orgId = orgMap['id']?.toString();
      if (orgId == null || orgId.isEmpty) continue;
      final outlets = (orgMap['allowedOutlets'] as List? ?? [])
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
      await _localCache.setAllowedOutletsForStore(orgId, outlets);
    }
  }

  /// Refreshes cached organization outlets from `/auth/status` and returns the
  /// active store's fresh allowed outlets list, or `null` on failure.
  Future<List<Map<String, dynamic>>?> refreshOutletContext() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.sessionStatus);
      if (response is Map) {
        await _cacheOrganizationOutlets(response);
        return _localCache.getAllowedOutlets();
      }
      return null;
    } on AuthException catch (e) {
      if (e.code == 'UNAUTHENTICATED') {
        await logout();
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Checks stored session token and validates status with the backend
  Future<AuthResult?> checkSession() async {
    final token = await _secureStorage.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      final response = await _apiClient.get(ApiEndpoints.sessionStatus);
      if (response is Map) {
        final userJson = Map<String, dynamic>.from(response['user'] as Map);
        final user = User.fromJson(userJson);
        await _localCache.setCachedUser(user.toJson());

        final rawStores = response['stores'] as List? ?? [];
        final stores = rawStores
            .map(
              (s) => StoreSummary.fromJson(Map<String, dynamic>.from(s as Map)),
            )
            .toList();

        await _localCache.setCachedAvailableStores(
          stores.map((s) => s.toJson()).toList(),
        );

        if (stores.isNotEmpty) {
          final currentActive = _localCache.getActiveStoreId();
          final active = stores.firstWhere(
            (s) => s.storeId == currentActive,
            orElse: () => stores.first,
          );
          await _localCache.setActiveStoreId(active.storeId);
          await _localCache.setCachedStoreDetails(active.toJson());
        }

        await _cacheOrganizationOutlets(response);

        return AuthResult(user: user, stores: stores);
      }
      return null;
    } on AuthException catch (e) {
      if (e.code == 'UNAUTHENTICATED') {
        await logout();
        return null;
      }
      rethrow;
    } catch (_) {
      // Offline fallback: restore session from local cache
      final cachedUserMap = _localCache.getCachedUser();
      final cachedStoreMap = _localCache.getCachedStoreDetails();
      final cachedStoresList = _localCache.getCachedAvailableStores();
      if (cachedUserMap != null && cachedStoreMap != null) {
        final user = User.fromJson(cachedUserMap);
        final currentStore = StoreSummary.fromJson(cachedStoreMap);
        final stores = cachedStoresList != null
            ? cachedStoresList.map((m) => StoreSummary.fromJson(m)).toList()
            : [currentStore];
        return AuthResult(user: user, stores: stores);
      }
      return null;
    }
  }

  /// Sets a new password when mustChangePassword == true
  Future<void> setPassword(String newPassword) async {
    await _apiClient.post(
      ApiEndpoints.setPassword,
      body: {'newPassword': newPassword},
    );
  }

  /// Changes password for owner/user
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final response = await _apiClient.post(
      ApiEndpoints.changePassword,
      body: {'oldPassword': currentPassword, 'newPassword': newPassword},
    );
    if (response is Map) {
      final token = response['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
      }
    }
  }

  /// Selects the active store for multi-store users
  Future<void> selectStore(String storeId) async {
    await _localCache.setActiveStoreId(storeId);
    final available = _localCache.getCachedAvailableStores();
    if (available != null) {
      final match = available.firstWhere(
        (s) => s['storeId'] == storeId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        await _localCache.setCachedStoreDetails(match);
      }
    }
  }

  /// Fetches store profile details for current active store and caches them
  Future<Map<String, dynamic>> fetchStoreDetails() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.profile);
      if (response is Map) {
        final storeMap = Map<String, dynamic>.from(response);
        await _localCache.setCachedStoreProfile(storeMap);
        return storeMap;
      }
      throw ApiException('Invalid store profile response format');
    } catch (_) {
      final cached =
          _localCache.getCachedStoreProfile() ??
          _localCache.getCachedStoreDetails();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  /// Logs out: calls API endpoint and wipes local session.
  /// The network call is mandatory: if the API request fails, the session is preserved.
  Future<void> logout() async {
    final token = await _secureStorage.getToken();
    if (token != null && token.isNotEmpty) {
      await _apiClient.post(ApiEndpoints.logout);
    }
    await _secureStorage.deleteToken();
    await _localCache.clear();
  }
}
