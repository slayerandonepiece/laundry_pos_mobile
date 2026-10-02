import 'package:firebase_analytics/firebase_analytics.dart';

abstract interface class AppAnalyticsSink {
  Future<void> logEvent(String name, Map<String, Object>? parameters);

  Future<void> setUserId(String? userId);

  Future<void> setUserProperty(String name, String? value);
}

final class FirebaseAppAnalyticsSink implements AppAnalyticsSink {
  FirebaseAppAnalyticsSink(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) =>
      _analytics.logEvent(name: name, parameters: parameters);

  @override
  Future<void> setUserId(String? userId) => _analytics.setUserId(id: userId);

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _analytics.setUserProperty(name: name, value: value);
}

/// Privacy-safe analytics entry point. Every operation is best-effort.
class AppAnalytics {
  AppAnalytics._();

  static AppAnalyticsSink? _sink;

  static void configure(FirebaseAnalytics? analytics) {
    _sink = analytics == null ? null : FirebaseAppAnalyticsSink(analytics);
  }

  static void setSinkForTesting(AppAnalyticsSink? sink) {
    _sink = sink;
  }

  static Future<void> _ignoreErrors(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {}
  }

  static Future<void> _event(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    final sink = _sink;
    if (sink == null) return;
    await _ignoreErrors(() => sink.logEvent(name, parameters));
  }

  static Future<void> setUserId(String? userId) async {
    final sink = _sink;
    if (sink == null) return;
    await _ignoreErrors(() => sink.setUserId(userId));
  }

  static Future<void> setRole(String? role) async {
    final sink = _sink;
    if (sink == null) return;
    await _ignoreErrors(() => sink.setUserProperty('role', role));
  }

  static Future<void> login() => _event('login');

  static Future<void> logout() => _event('logout');

  static Future<void> orderPlaced({
    required String paymentChoice,
    required int itemCount,
    required int valuePaise,
  }) => _event('order_placed', {
    'payment_choice': paymentChoice,
    'item_count': itemCount,
    'value_paise': valuePaise,
  });

  static Future<void> paymentRecorded({required int amountPaise}) =>
      _event('payment_recorded', {'amount_paise': amountPaise});

  static Future<void> invoiceViewed({required String kind}) =>
      _event('invoice_viewed', {'kind': kind});

  static Future<void> invoiceShared({required String kind}) =>
      _event('invoice_shared', {'kind': kind});

  static Future<void> syncFailed({required String reason}) =>
      _event('sync_failed', {'reason': reason});

  static Future<void> diagnosticsTest() => _event('diagnostics_test');

  static Future<void> screenView(String name) =>
      _event('screen_view', {'screen_name': name});
}
