import 'dart:async';

import 'package:myshop/core/network/network_activity.dart';
import 'package:myshop/core/network/server_warmup.dart';

/// Tests must never touch the network, including the launch warm-up ping.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ServerWarmup.enabled = false;
  NetworkActivity.enabled = false;
  await testMain();
}
