import 'package:flutter/foundation.dart';

/// Tiny structured-logging helper for the sync/connectivity/network path.
///
/// Wraps [debugPrint] (not `print` — Android truncates long single `print`
/// lines) and is a no-op outside debug builds, so it costs nothing in
/// release. Every line is prefixed with a timestamp and a tag so device logs
/// (e.g. `adb logcat`) can be filtered per subsystem while debugging exactly
/// the kind of "why did the banner flip to offline" issue this was added
/// for.
class AppLogger {
  AppLogger._();

  static void log(String tag, String message, {Object? error}) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final ts =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.${_three(now.millisecond)}';
    final suffix = error != null ? ' — $error' : '';
    debugPrint('[$ts][$tag] $message$suffix');
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _three(int v) => v.toString().padLeft(3, '0');
}
