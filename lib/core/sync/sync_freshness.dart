/// When the phone last pulled fresh data from the server. Screens that open
/// right after a sync (sign-in, a background sync) read their local cache
/// instead of asking the server for the same data again.
class SyncFreshness {
  SyncFreshness._();

  static const Duration window = Duration(seconds: 30);
  static DateTime? _syncedAt;

  static void mark() => _syncedAt = DateTime.now();

  static void reset() => _syncedAt = null;

  static bool get isFresh {
    final at = _syncedAt;
    return at != null && DateTime.now().difference(at) < window;
  }
}
