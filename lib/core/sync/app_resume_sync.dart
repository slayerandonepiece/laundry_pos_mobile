import 'package:flutter/widgets.dart';

import '../network/server_warmup.dart';
import 'sync_engine.dart';

class AppResumeSync with WidgetsBindingObserver {
  final VoidCallback _onResume;

  AppResumeSync({VoidCallback? onResume})
    : _onResume =
          onResume ??
          (() {
            ServerWarmup.ping();
            SyncEngine.instance.triggerIfStale();
          }) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
