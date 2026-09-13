import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_endpoints.dart';
import '../logging/app_logger.dart';
import '../storage/local_cache.dart';
import 'sync_engine.dart';
import 'sync_manager.dart';

const _tag = 'CONNECTIVITY';

/// Drives the offline indicator directly off the device's real connectivity
/// state (not just reactively, after some API call happens to fail), and
/// triggers a sync the moment connectivity comes back.
///
/// `connectivity_plus`'s OS-level signal is treated as a trigger only, never
/// as the sole source of truth for going offline: it is known to report
/// "no connectivity" on Android whenever a VPN is active even though the
/// backend is perfectly reachable (see
/// https://github.com/fluttercommunity/plus_plugins/issues/3810). Before
/// this service ever reports "offline", it confirms with one real,
/// lightweight request to the app's own backend.
class ConnectivityService {
  @visibleForTesting
  ConnectivityService.internal({
    LocalCacheService? localCache,
    Dio? dio,
    this._debounceDuration = const Duration(milliseconds: 1500),
    this._probeTimeout = const Duration(seconds: 4),
    this._probeCooldown = const Duration(seconds: 8),
  }) : _localCache = localCache ?? LocalCacheService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 4),
               receiveTimeout: const Duration(seconds: 4),
               validateStatus: (_) => true,
             ),
           );

  ConnectivityService._()
    : _localCache = LocalCacheService(),
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (_) => true,
        ),
      ),
      _debounceDuration = const Duration(milliseconds: 1500),
      _probeTimeout = const Duration(seconds: 4),
      _probeCooldown = const Duration(seconds: 8);
  static ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;
  @visibleForTesting
  static set instance(ConnectivityService value) => _instance = value;

  final LocalCacheService _localCache;
  final Dio _dio;
  final Duration _debounceDuration;
  final Duration _probeTimeout;
  final Duration _probeCooldown;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;
  bool? _isOffline;

  // Coalesces overlapping reachability probes (same pattern as the
  // generation/completer coalescing in SyncEngine.trigger()) so a burst of
  // concurrent callers — the debounced handler and checkIsOffline() both
  // firing around the same time — share one in-flight probe instead of
  // hitting the backend repeatedly, plus a short cooldown so a flapping
  // connection can't turn into a probe storm.
  Future<bool>? _inFlightProbe;
  DateTime? _lastProbeAt;
  bool? _lastProbeResult;

  bool get isOffline => _isOffline ?? false;

  Future<bool> checkIsOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final osOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      AppLogger.log(_tag, 'checkIsOffline: OS says offline=$osOffline');
      if (!osOffline) {
        _isOffline = false;
        return false;
      }

      // OS says offline — don't trust that alone (VPN false-positive class
      // of bug), confirm with a real probe first.
      final reachable = await _probeReachability();
      final offline = !reachable;
      _isOffline = offline;
      AppLogger.log(
        _tag,
        'checkIsOffline: OS said offline, probe reachable=$reachable -> '
        'reporting offline=$offline',
      );
      return offline;
    } catch (e) {
      AppLogger.log(
        _tag,
        'checkIsOffline: error, falling back to cached state',
        error: e,
      );
      return _isOffline ?? false;
    }
  }

  void start() {
    if (_subscription != null) return;
    _subscription = Connectivity().onConnectivityChanged.listen(_handle);
    Connectivity().checkConnectivity().then(_handle);
  }

  void _handle(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    AppLogger.log(
      _tag,
      'raw OS connectivity result=$results -> offline=$offline (current=$_isOffline)',
    );
    if (offline == _isOffline) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      _debounceTimer = null;
      AppLogger.log(_tag, 'debounce resolved -> candidate offline=$offline');

      if (offline) {
        // Don't flip to offline off the OS signal alone — confirm with a
        // real probe to the backend first (VPN-false-positive class of bug).
        final reachable = await _probeReachability();
        if (reachable) {
          AppLogger.log(
            _tag,
            'OS said offline but probe reached backend -> ignoring, staying online',
          );
          return;
        }
        _isOffline = true;
        var count = 0;
        try {
          count = _localCache.getTotalPendingCount();
        } catch (_) {}
        AppLogger.log(
          _tag,
          'confirmed offline (probe failed too) -> setOffline($count)',
        );
        SyncManager.instance.setOffline(
          count,
          'Offline — running on cached data',
        );
      } else {
        _isOffline = false;
        AppLogger.log(_tag, 'back online -> triggering sync');
        SyncEngine.instance.retryNow();
      }
    });
  }

  /// Issues one short-timeout GET to the app's own backend to confirm it is
  /// actually reachable. Any HTTP response — including a 401/403 — proves
  /// the socket/TLS/HTTP path to the backend works and counts as
  /// "reachable"; only a connection-level failure (timeout, socket error,
  /// DNS failure) or a 5xx counts as "unreachable". Uses the raw `http`
  /// package directly rather than the full ApiClient so a non-2xx response
  /// doesn't get turned into a thrown typed exception here.
  ///
  /// Deliberately hits `ApiEndpoints.sessionStatus` (`/api/v1/auth/status`)
  /// — it's a cheap, side-effect-free GET, and it works whether or not the
  /// caller is currently logged in: with no/invalid token the backend still
  /// answers (401), which still proves reachability.
  Future<bool> _probeReachability() {
    final now = DateTime.now();
    if (_inFlightProbe != null) {
      AppLogger.log(_tag, 'probe: joining in-flight probe');
      return _inFlightProbe!;
    }
    if (_lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _probeCooldown &&
        _lastProbeResult != null) {
      AppLogger.log(
        _tag,
        'probe: within cooldown, reusing last result=$_lastProbeResult',
      );
      return Future.value(_lastProbeResult);
    }

    final stopwatch = Stopwatch()..start();
    AppLogger.log(_tag, 'probe: starting GET ${ApiEndpoints.sessionStatus}');
    final future = _dio
        .get(
          ApiEndpoints.sessionStatus,
          options: Options(
            sendTimeout: _probeTimeout,
            receiveTimeout: _probeTimeout,
          ),
        )
        .then((response) {
          stopwatch.stop();
          // Any response at all — including 401/403 — proves the backend is
          // reachable. Only treat a server-side (5xx) failure as unreachable.
          final statusCode = response.statusCode ?? 500;
          final reachable = statusCode < 500;
          AppLogger.log(
            _tag,
            'probe: result status=$statusCode reachable=$reachable '
            'in ${stopwatch.elapsedMilliseconds}ms',
          );
          return reachable;
        })
        .catchError((Object e) {
          stopwatch.stop();
          AppLogger.log(
            _tag,
            'probe: failed after ${stopwatch.elapsedMilliseconds}ms',
            error: e,
          );
          return false;
        })
        .whenComplete(() {
          _inFlightProbe = null;
          _lastProbeAt = DateTime.now();
        });

    _inFlightProbe = future.then((result) {
      _lastProbeResult = result;
      return result;
    });
    return _inFlightProbe!;
  }

  @visibleForTesting
  void handleForTesting(List<ConnectivityResult> results) => _handle(results);

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
