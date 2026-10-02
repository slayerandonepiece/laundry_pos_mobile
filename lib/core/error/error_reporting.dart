import 'dart:async';
import 'dart:isolate' show Isolate, RawReceivePort;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/core/network/firebase_service.dart';

/// One place that decides what happens to an error nobody caught.
///
/// Every route ends in the same two outcomes: it is logged, and in non-debug
/// builds it is reported to Crashlytics as a **fatal** error. The routes are:
/// - the zone that wraps startup and `runApp` ([runGuarded]) for async errors
///   and errors during startup;
/// - `FlutterError.onError` for errors inside the framework (build, layout);
/// - `PlatformDispatcher.onError` for async errors that reach the engine;
/// - errors thrown in other isolates.
class ErrorReporting {
  ErrorReporting._();

  /// Report only outside debug builds; debug runs would pollute the stats.
  @visibleForTesting
  static bool reportingEnabled = !kDebugMode;

  /// Where fatal errors go; replaced in tests.
  @visibleForTesting
  static void Function(Object error, StackTrace? stack) fatalReporter =
      FirebaseService.recordFatal;

  /// Where framework errors go; replaced in tests.
  @visibleForTesting
  static void Function(FlutterErrorDetails details) flutterFatalReporter =
      FirebaseService.recordFlutterFatal;

  /// Runs [body] inside a guarded zone. `WidgetsFlutterBinding.ensureInitialized`
  /// and `runApp` must both happen inside [body] so they share this zone.
  static void runGuarded(Future<void> Function() body) {
    runZonedGuarded<Future<void>>(body, onZoneError);
  }

  /// Handles an error that escaped everything else.
  static void onZoneError(Object error, StackTrace stack) {
    AppLogger.log('ZONE_ERROR', '$error\n$stack', error: error);
    if (reportingEnabled) fatalReporter(error, stack);
  }

  /// Installs the framework, platform and isolate handlers. Call once, after
  /// Firebase has been initialized (the reporters do nothing until it is).
  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      // Keep the normal console dump in debug runs.
      FlutterError.presentError(details);
      AppLogger.log(
        'FLUTTER_ERROR',
        '${details.exceptionAsString()}${details.stack != null ? '\n${details.stack}' : ''}',
      );
      if (reportingEnabled) flutterFatalReporter(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.log('PLATFORM_ERROR', '$error\n$stack', error: error);
      if (reportingEnabled) fatalReporter(error, stack);
      return true;
    };

    // Errors thrown in other isolates arrive as [error, stack-as-string].
    Isolate.current.addErrorListener(
      RawReceivePort((dynamic pair) {
        final list = pair as List<dynamic>;
        final error = list.first as Object;
        final stack = StackTrace.fromString(list.last.toString());
        AppLogger.log('ISOLATE_ERROR', '$error\n$stack', error: error);
        if (reportingEnabled) fatalReporter(error, stack);
      }).sendPort,
    );

    // Release builds show a calm message instead of the grey error box.
    if (kReleaseMode) {
      ErrorWidget.builder = (FlutterErrorDetails details) =>
          const _FriendlyErrorWidget();
    }
  }
}

class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong on this screen.\nGo back and try again.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
          ),
        ),
      ),
    );
  }
}
