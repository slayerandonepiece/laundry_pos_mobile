import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../sync/sync_manager.dart';

/// Watches requests in flight. When one is slow (a weak connection, or the
/// database waking up) it shows the same floating "syncing" banner the
/// background sync uses, so the user keeps working instead of staring at a
/// spinner. Nothing here ever blocks a screen.
class NetworkActivity {
  NetworkActivity._();
  static final NetworkActivity instance = NetworkActivity._();

  @visibleForTesting
  static Duration slowAfter = const Duration(seconds: 4);
  static const String message = 'Slow connection · still working…';

  /// Off in widget tests: a request that never completes under fake async
  /// would leave this timer pending.
  @visibleForTesting
  static bool enabled = true;

  /// True while at least one request has been in flight longer than
  /// [slowAfter]. Screens that must wait (sign-in) can explain the delay.
  final ValueNotifier<bool> slow = ValueNotifier(false);

  final Map<RequestOptions, Timer> _timers = {};
  final Set<RequestOptions> _slowRequests = {};

  void started(RequestOptions options) {
    if (!enabled) return;
    _timers[options] = Timer(slowAfter, () {
      _timers.remove(options);
      _slowRequests.add(options);
      slow.value = true;
      // Ignored by SyncManager while it is showing pending/paused/error.
      SyncManager.instance.startSync(message);
    });
  }

  void finished(RequestOptions options) {
    final timer = _timers.remove(options);
    if (timer != null) {
      timer.cancel();
      return;
    }
    if (!_slowRequests.remove(options)) return;
    if (_slowRequests.isNotEmpty) return;
    slow.value = false;
    final state = SyncManager.instance.value;
    if (state.isSyncing && state.message == message) {
      SyncManager.instance.completeSync();
    }
  }
}

class SlowRequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    NetworkActivity.instance.started(options);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    NetworkActivity.instance.finished(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    NetworkActivity.instance.finished(err.requestOptions);
    handler.next(err);
  }
}
