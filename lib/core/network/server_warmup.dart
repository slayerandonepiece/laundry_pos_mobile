import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../logging/app_logger.dart';

const _tag = 'WARMUP';

/// The database can take ~25s to wake after sitting idle. A cheap ping on
/// launch and resume (and while the sign-in screen is open) wakes it before
/// the first real request, so that request is fast. Fire-and-forget: never
/// awaited by a screen, errors are swallowed.
class ServerWarmup {
  ServerWarmup._();

  static const Duration _minGap = Duration(seconds: 90);
  static DateTime? _lastPing;

  /// Off in tests, which must never touch the network.
  static bool enabled = true;

  static void ping() {
    if (!enabled) return;
    final now = DateTime.now();
    final last = _lastPing;
    if (last != null && now.difference(last) < _minGap) return;
    _lastPing = now;
    _send();
  }

  static Future<void> _send() async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
          validateStatus: (_) => true,
        ),
      );
      await dio.get(ApiEndpoints.health);
      AppLogger.log(_tag, 'ping done');
    } catch (e) {
      // Offline or unreachable: nothing to warm; real requests handle it.
      AppLogger.log(_tag, 'ping failed', error: e);
    }
  }
}
