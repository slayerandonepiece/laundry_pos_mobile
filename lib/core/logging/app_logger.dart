import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Central structured logger for KlenPOS.
///
/// In debug mode: prints timestamped formatted logs to the console (`debugPrint`).
/// In release/staging mode: forwards logs to Firebase Crashlytics as breadcrumbs,
/// ensuring all diagnostics and non-fatal errors are captured in real-time.
class AppLogger {
  AppLogger._();

  static void log(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = DateTime.now();
    final ts =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.${_three(now.millisecond)}';
    final suffix = error != null ? ' — $error' : '';
    final logLine = '[$ts][$tag] $message$suffix';

    if (kDebugMode) {
      debugPrint(logLine);
    } else {
      try {
        FirebaseCrashlytics.instance.log(logLine);
        if (error != null) {
          FirebaseCrashlytics.instance.recordError(
            error,
            stackTrace,
            reason: '[$tag] $message',
          );
        }
      } catch (_) {
        // Ignored if Firebase is not yet initialized or on unsupported platform
      }
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _three(int v) => v.toString().padLeft(3, '0');
}
