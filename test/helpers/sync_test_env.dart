import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/core/sync/sync_freshness.dart';
import 'package:myshop/core/sync/sync_manager.dart';

/// Connectivity whose reading the test controls.
class FakeConnectivity extends ConnectivityService {
  FakeConnectivity([this.offline = false]) : super.internal();
  bool offline;
  @override
  bool get isOffline => offline;
  @override
  Future<bool> checkIsOffline() async => offline;
}

/// An [ApiClient] whose responses/failures the test scripts. Requests are
/// recorded; a handler may throw any exception the real client would.
class ScriptedApi extends ApiClient {
  ScriptedApi(LocalCacheService cache) : super(localCache: cache);

  Future<dynamic> Function(String url, Map<String, String>? headers)? onGet;
  Future<dynamic> Function(
    String url,
    dynamic body,
    Map<String, String>? headers,
  )?
  onPost;
  final List<String> gets = [];
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    gets.add(url);
    return onGet!(url, headers);
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    posts.add({'url': url, 'body': body, 'headers': headers});
    return onPost!(url, body, headers);
  }
}

/// Real Hive-backed cache in a temp dir, with the sync singletons reset.
class SyncTestEnv {
  SyncTestEnv._(this.dir, this.cache);
  final Directory dir;
  final LocalCacheService cache;

  static Future<SyncTestEnv> create() async {
    final dir = await Directory.systemTemp.createTemp('sync_env_');
    Hive.init(dir.path);
    await Hive.openBox(LocalCacheService.boxName);
    final env = SyncTestEnv._(dir, LocalCacheService());
    await env.cache.setActiveStoreId('store-1');
    SyncFreshness.reset();
    SyncManager.instance.completeSync(force: true);
    ConnectivityService.instance = FakeConnectivity();
    return env;
  }

  Future<void> dispose() async {
    SyncFreshness.reset();
    SyncManager.instance.completeSync(force: true);
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
