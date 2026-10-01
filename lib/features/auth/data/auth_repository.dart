import 'dart:async';

import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/storage/secure_storage.dart';
import 'package:myshop/core/sync/sync_freshness.dart';

import 'models/user_model.dart';

const _tag = 'AUTH_REPO';

/// Key prefix of the per-store slot that keeps unsynced queues across an
/// involuntary sign-out (see [AuthRepository.logout]).
const String keyParkedUnsynced = 'parked_unsynced';

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

  /// Logs in using phone and password
  Future<AuthResult> login(String phone, String password) async {
    final response = await _apiClient.post(
      ApiEndpoints.login,
      body: {'phone': phone.trim(), 'password': password},
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
        await _restoreParkedQueues(active.storeId);
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
  /// active store's fresh allowed outlets list.
  ///
  /// Returns `null` when the refresh could not be completed for a reason that
  /// says nothing about access (offline, timeout, 5xx, malformed payload): the
  /// caller must keep the user signed in with the cached outlets. A 401 signs
  /// the session out (involuntarily) and a 401/403 is rethrown as
  /// [AuthException] so the caller can tell "access lost" from "flaky network".
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
        await logout(involuntary: true);
      }
      rethrow;
    } catch (e) {
      AppLogger.log(_tag, 'refreshOutletContext failed', error: e);
      return null;
    }
  }

  /// True for failures that mean "could not reach / trust the server right
  /// now" (no connection, timeout, 5xx, rate limit) as opposed to a real
  /// answer or a malformed one.
  bool _isReachabilityFailure(Object e) {
    if (e is TimeoutException) return true;
    if (e is AuthException) return false;
    if (e is RateLimitException) return true;
    if (e is ApiException) {
      final code = e.statusCode;
      return code == null || code >= 500;
    }
    return false;
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
          await _restoreParkedQueues(active.storeId);
        }

        await _cacheOrganizationOutlets(response);

        return AuthResult(user: user, stores: stores);
      }
      return null;
    } on AuthException catch (e) {
      if (e.code == 'UNAUTHENTICATED') {
        await logout(involuntary: true);
        return null;
      }
      rethrow;
    } catch (e, st) {
      if (!_isReachabilityFailure(e)) {
        // Malformed/unexpected payload or a client error: never open a
        // session we could not verify.
        AppLogger.log(
          _tag,
          'checkSession failed (not offline)',
          error: e,
          stackTrace: st,
        );
        return null;
      }
      AppLogger.log(
        _tag,
        'checkSession offline/5xx, using cached session',
        error: e,
      );
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
    final response = await _apiClient.post(
      ApiEndpoints.setPassword,
      body: {'newPassword': newPassword},
    );
    if (response is Map) {
      final token = response['token']?.toString();
      if (token != null && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
      }
    }
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
    } on AuthException {
      rethrow;
    } catch (e) {
      AppLogger.log(_tag, 'fetchStoreDetails failed, using cache', error: e);
      final cached =
          _localCache.getCachedStoreProfile() ??
          _localCache.getCachedStoreDetails();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  /// Logs out: calls the API endpoint and wipes the local session.
  ///
  /// Voluntary (default, from the guarded logout dialog): a 401/403 means the
  /// token is already dead, so the session is wiped anyway; any other failure
  /// (offline, 5xx) rethrows and the session is preserved so the user cannot
  /// lose unsynced data by accident.
  ///
  /// [involuntary] (session revoked / access changed): never throws. The
  /// token and cache are always removed, so the app always reaches the login
  /// screen. The unsynced queues (pending orders, owner actions, both dead
  /// letter queues) are first parked under a per-store slot that survives
  /// [LocalCacheService.clear]; the next sign-in to that same store restores
  /// them so they can still sync.
  Future<void> logout({bool involuntary = false}) async {
    final token = await _secureStorage.getToken();
    Object? pendingError;
    if (token != null && token.isNotEmpty) {
      try {
        await _apiClient.post(ApiEndpoints.logout);
      } on AuthException {
        // Token already invalid server-side: nothing to revoke, wipe locally.
      } catch (e) {
        if (involuntary) {
          AppLogger.log(_tag, 'logout request failed (involuntary)', error: e);
        } else {
          pendingError = e;
        }
      }
    }
    if (pendingError != null) throw pendingError;

    Map<String, dynamic>? parked;
    String? storeId;
    if (involuntary) {
      try {
        storeId = _localCache.getActiveStoreId();
        parked = {
          'pending': _localCache.getPendingSyncQueue(),
          'dead': _localCache.getDeadLetterQueue(),
          'ownerPending': _localCache.getPendingOwnerActionsQueue(),
          'ownerDead': _localCache.getDeadLetterOwnerActionsQueue(),
        };
      } catch (e) {
        AppLogger.log(_tag, 'could not snapshot unsynced queues', error: e);
      }
    }
    try {
      await _secureStorage.deleteToken();
    } finally {
      try {
        await _localCache.clear();
        final slot = parked;
        if (slot != null &&
            storeId != null &&
            slot.values.any((v) => (v as List).isNotEmpty)) {
          await _localCache.put('$keyParkedUnsynced::$storeId', slot);
        }
      } catch (e) {
        AppLogger.log(_tag, 'clear/park failed during logout', error: e);
      } finally {
        SyncFreshness.reset();
      }
    }
  }

  /// Puts back the queues parked by an involuntary sign-out of [storeId].
  Future<void> _restoreParkedQueues(String storeId) async {
    try {
      await _restoreParkedQueuesUnsafe(storeId);
    } catch (e) {
      // Restoring is best effort: it must never block a sign-in.
      AppLogger.log(_tag, 'could not restore parked queues', error: e);
    }
  }

  Future<void> _restoreParkedQueuesUnsafe(String storeId) async {
    final key = '$keyParkedUnsynced::$storeId';
    final raw = _localCache.get(key);
    if (raw is! Map) return;
    List<Map<String, dynamic>> list(String k, List<Map<String, dynamic>> cur) {
      final saved = raw[k];
      if (saved is! List) return cur;
      return [
        ...saved.map(
          (e) => LocalCacheService.deepCopy(e) as Map<String, dynamic>,
        ),
        ...cur,
      ];
    }

    await _localCache.setPendingSyncQueue(
      list('pending', _localCache.getPendingSyncQueue()),
    );
    await _localCache.setDeadLetterQueue(
      list('dead', _localCache.getDeadLetterQueue()),
    );
    await _localCache.setPendingOwnerActionsQueue(
      list('ownerPending', _localCache.getPendingOwnerActionsQueue()),
    );
    await _localCache.setDeadLetterOwnerActionsQueue(
      list('ownerDead', _localCache.getDeadLetterOwnerActionsQueue()),
    );
    await _localCache.delete(key);
    AppLogger.log(_tag, 'restored unsynced queues for store $storeId');
  }
}
