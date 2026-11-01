import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/network/network_activity.dart';
import 'package:myshop/core/sync/sync_manager.dart';

void main() {
  late RequestOptions request;

  setUp(() {
    NetworkActivity.enabled = true;
    NetworkActivity.slowAfter = const Duration(milliseconds: 30);
    request = RequestOptions(path: '/slow');
    SyncManager.instance.completeSync(force: true);
  });

  tearDown(() {
    NetworkActivity.slowAfter = const Duration(seconds: 4);
    NetworkActivity.enabled = false;
  });

  test('a fast request never shows the banner', () async {
    NetworkActivity.instance.started(request);
    NetworkActivity.instance.finished(request);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(SyncManager.instance.value.isSyncing, isFalse);
    expect(NetworkActivity.instance.slow.value, isFalse);
  });

  test('a slow request shows the floating banner, then clears it', () async {
    NetworkActivity.instance.started(request);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(SyncManager.instance.value.isSyncing, isTrue);
    expect(SyncManager.instance.value.message, NetworkActivity.message);
    expect(NetworkActivity.instance.slow.value, isTrue);

    NetworkActivity.instance.finished(request);
    expect(SyncManager.instance.value.isSynced, isTrue);
    expect(NetworkActivity.instance.slow.value, isFalse);
  });

  test('banner stays until the last slow request finishes', () async {
    final other = RequestOptions(path: '/other');
    NetworkActivity.instance.started(request);
    NetworkActivity.instance.started(other);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    NetworkActivity.instance.finished(request);
    expect(SyncManager.instance.value.isSyncing, isTrue);
    NetworkActivity.instance.finished(other);
    expect(SyncManager.instance.value.isSyncing, isFalse);
  });

  test('never replaces a pending-changes banner', () async {
    SyncManager.instance.setPendingOnline(2);
    NetworkActivity.instance.started(request);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(SyncManager.instance.value.isPendingOnline, isTrue);
    NetworkActivity.instance.finished(request);
    expect(SyncManager.instance.value.isPendingOnline, isTrue);
  });
}
