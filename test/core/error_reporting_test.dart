import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/error/error_reporting.dart';

void main() {
  late FlutterExceptionHandler? originalFlutterHandler;
  late ErrorCallback? originalPlatformHandler;
  late void Function(Object, StackTrace?) originalFatal;
  late void Function(FlutterErrorDetails) originalFlutterFatal;
  late bool originalEnabled;
  late List<Object> fatals;
  late List<FlutterErrorDetails> flutterFatals;

  setUp(() {
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
    originalFatal = ErrorReporting.fatalReporter;
    originalFlutterFatal = ErrorReporting.flutterFatalReporter;
    originalEnabled = ErrorReporting.reportingEnabled;
    fatals = [];
    flutterFatals = [];
    ErrorReporting.fatalReporter = (error, stack) => fatals.add(error);
    ErrorReporting.flutterFatalReporter = flutterFatals.add;
    ErrorReporting.reportingEnabled = true;
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
    ErrorReporting.fatalReporter = originalFatal;
    ErrorReporting.flutterFatalReporter = originalFlutterFatal;
    ErrorReporting.reportingEnabled = originalEnabled;
  });

  test(
    'an uncaught async error inside the guarded zone is reported fatal',
    () async {
      ErrorReporting.runGuarded(() async {
        Future<void>.delayed(
          Duration.zero,
          () => throw StateError('late boom'),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fatals.single, isA<StateError>());
    },
  );

  test('an error while starting up is reported, not lost', () async {
    ErrorReporting.runGuarded(() async {
      throw StateError('startup boom');
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(fatals.single, isA<StateError>());
  });

  test('Flutter framework errors are reported fatal', () {
    ErrorReporting.install();
    final details = FlutterErrorDetails(exception: StateError('build boom'));

    // presentError would dump to the console; it is not under test here.
    FlutterError.onError!(details);

    expect(flutterFatals.single.exception, isA<StateError>());
  });

  test('platform dispatcher errors are reported fatal and marked handled', () {
    ErrorReporting.install();

    final handled = PlatformDispatcher.instance.onError!(
      StateError('async boom'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    expect(fatals.single, isA<StateError>());
  });

  test('nothing is reported when reporting is off (debug runs)', () async {
    ErrorReporting.reportingEnabled = false;
    ErrorReporting.install();

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('a')));
    PlatformDispatcher.instance.onError!(StateError('b'), StackTrace.current);
    ErrorReporting.onZoneError(StateError('c'), StackTrace.current);

    expect(fatals, isEmpty);
    expect(flutterFatals, isEmpty);
  });
}
