import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'sync_engine.dart';
import 'sync_manager.dart';

/// Drives the offline indicator directly off the device's real connectivity
/// state (not just reactively, after some API call happens to fail), and
/// triggers a sync the moment connectivity comes back.
class ConnectivityService {
  @visibleForTesting
  ConnectivityService.internal();

  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool? _isOffline;

  bool get isOffline => _isOffline ?? false;

  Future<bool> checkIsOffline() async {
    final results = await Connectivity().checkConnectivity();
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    _isOffline = offline;
    return offline;
  }

  void start() {
    if (_subscription != null) return;
    _subscription = Connectivity().onConnectivityChanged.listen(_handle);
    Connectivity().checkConnectivity().then(_handle);
  }

  void _handle(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline == _isOffline) return;
    _isOffline = offline;

    if (offline) {
      SyncManager.instance.setOffline(0, 'Offline — running on cached data');
    } else {
      SyncEngine.instance.retryNow();
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
