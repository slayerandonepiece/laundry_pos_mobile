import '../../../core/network/api_exceptions.dart';
import '../../../core/storage/local_cache.dart';
import 'models/outlet_model.dart';

/// Refuses a write for an outlet whose cached billing says it is blocked, so
/// nothing is created locally or queued. The server stays the authority: a
/// stale cache is caught by its 403 `payment_lapsed`.
class OutletBillingGuard {
  /// Set by the app shell: re-reads `/auth/status` and republishes the scope.
  static Future<void> Function()? refresh;

  static Outlet? _outlet(LocalCacheService cache, String? outletId) {
    if (outletId == null || outletId.isEmpty) return null;
    for (final m in cache.getAllowedOutlets() ?? const []) {
      if (m['id']?.toString() == outletId) return Outlet.fromJson(m);
    }
    return null;
  }

  static bool isBlocked(LocalCacheService cache, String? outletId) =>
      _outlet(cache, outletId)?.isBlocked ?? false;

  static bool _isOwner(LocalCacheService cache) =>
      cache.getCachedStoreDetails()?['role']?.toString().toUpperCase() ==
      'OWNER';

  static void ensureWritable(LocalCacheService cache, String? outletId) {
    final outlet = _outlet(cache, outletId);
    if (outlet != null && outlet.isBlocked) {
      throw OutletBlockedException(
        outlet.displayName,
        isOwner: _isOwner(cache),
      );
    }
  }

  /// Turns a 403 `payment_lapsed` on [outletId] into the blocked message and
  /// refreshes billing. Anything else is returned unchanged.
  static Future<Object> translate(
    LocalCacheService cache,
    String? outletId,
    Object error,
  ) async {
    if (error is! AuthException ||
        error.code != 'FORBIDDEN' ||
        error.reason != 'payment_lapsed') {
      return error;
    }
    await refresh?.call();
    final outlet = _outlet(cache, outletId);
    if (outlet == null) return error;
    return OutletBlockedException(outlet.displayName, isOwner: _isOwner(cache));
  }
}
