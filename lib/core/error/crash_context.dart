import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:myshop/core/analytics/app_analytics.dart';

abstract interface class CrashContextSink {
  Future<void> setCrashUserIdentifier(String identifier);

  Future<void> setCrashKey(String key, Object value);

  Future<void> setAnalyticsUserId(String? userId);

  Future<void> setAnalyticsRole(String? role);
}

final class FirebaseCrashContextSink implements CrashContextSink {
  @override
  Future<void> setCrashUserIdentifier(String identifier) =>
      FirebaseCrashlytics.instance.setUserIdentifier(identifier);

  @override
  Future<void> setCrashKey(String key, Object value) =>
      FirebaseCrashlytics.instance.setCustomKey(key, value);

  @override
  Future<void> setAnalyticsUserId(String? userId) =>
      AppAnalytics.setUserId(userId);

  @override
  Future<void> setAnalyticsRole(String? role) => AppAnalytics.setRole(role);
}

/// Adds only opaque identifiers and coarse authorization context to reports.
class CrashContext {
  CrashContext._();

  static CrashContextSink sink = FirebaseCrashContextSink();

  static Future<void> setAuthenticated({
    required String userId,
    required String storeId,
    String? outletId,
    required String role,
    required String environment,
  }) async {
    final normalizedRole = role.toUpperCase();
    await _bestEffort(() => sink.setCrashUserIdentifier(userId));
    await _bestEffort(() => sink.setCrashKey('store_id', storeId));
    await _bestEffort(() => sink.setCrashKey('outlet_id', outletId ?? ''));
    await _bestEffort(() => sink.setCrashKey('role', normalizedRole));
    await _bestEffort(() => sink.setCrashKey('environment', environment));
    await _bestEffort(() => sink.setAnalyticsUserId(userId));
    await _bestEffort(() => sink.setAnalyticsRole(normalizedRole));
  }

  static Future<void> clear() async {
    await _bestEffort(() => sink.setCrashUserIdentifier(''));
    await _bestEffort(() => sink.setCrashKey('store_id', ''));
    await _bestEffort(() => sink.setCrashKey('outlet_id', ''));
    await _bestEffort(() => sink.setCrashKey('role', ''));
    await _bestEffort(() => sink.setCrashKey('environment', ''));
    await _bestEffort(() => sink.setAnalyticsUserId(null));
    await _bestEffort(() => sink.setAnalyticsRole(null));
  }

  static Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {}
  }
}
