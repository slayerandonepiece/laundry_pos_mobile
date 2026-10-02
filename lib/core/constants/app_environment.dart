import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show appFlavor;

/// Application deployment environments
enum AppEnvironment { dev, stage, prod }

/// Central environment configuration for KlenPOS
class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  /// Canonical single source of truth for the application name.
  static const String appName = 'KlenPOS';

  /// Reads compile-time environment from `--dart-define=ENV=<dev|stage|prod>`.
  /// Empty when not given; the build flavor then decides (see [current]).
  static const String _rawEnv = String.fromEnvironment('ENV');

  /// Optional base URL override from `--dart-define=BASE_URL=<url>`.
  static const String _baseUrlOverride = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );

  static AppEnvironment? _parse(String? value) {
    switch (value?.toLowerCase()) {
      case 'stage':
      case 'staging':
        return AppEnvironment.stage;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      default:
        return null;
    }
  }

  /// A stage or prod flavor can never run as dev, whatever `ENV` says: a
  /// release built with `--flavor prod` and no `--dart-define` must not talk to
  /// localhost. Otherwise an explicit `ENV` wins, then the dev default.
  @visibleForTesting
  static AppEnvironment resolveEnvironment({String? flavor, String? explicit}) {
    final fromFlavor = _parse(flavor);
    if (fromFlavor != null && fromFlavor != AppEnvironment.dev) {
      return fromFlavor;
    }
    return _parse(explicit) ?? fromFlavor ?? AppEnvironment.dev;
  }

  /// Active environment enum
  static AppEnvironment get current =>
      resolveEnvironment(flavor: appFlavor, explicit: _rawEnv);

  static String get name => current.name;

  static bool get isDev => current == AppEnvironment.dev;
  static bool get isStage => current == AppEnvironment.stage;
  static bool get isProd => current == AppEnvironment.prod;

  /// Resolves localhost base URL based on the active platform:
  /// - Android emulator: 10.0.2.2:3000
  /// - Web: localhost:3000
  /// - iOS Simulator / macOS / Desktop: 127.0.0.1:3000
  static String get localhostUrl {
    if (kIsWeb) return 'http://localhost:3000';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }

  /// Staging URL definition (commented by default per requirements)
  static String get stageUrl {
    // Stage URL — uncomment when ready to point to remote staging:
    return 'https://klenpos-staging.vercel.app';
  }

  /// Production URL definition (left empty per requirements, add when ready)
  static String get prodUrl {
    // Production URL — leave empty for now, add when ready:
    return 'https://klenpos-prod.vercel.app';
  }

  /// Plain HTTP is for dev only. Stage and prod ignore any `BASE_URL` that is
  /// not HTTPS and use their own HTTPS URL instead.
  @visibleForTesting
  static String resolveBaseUrl({
    required AppEnvironment env,
    String override = '',
  }) {
    final String fallback;
    switch (env) {
      case AppEnvironment.dev:
        fallback = localhostUrl;
        break;
      case AppEnvironment.stage:
        fallback = stageUrl.isNotEmpty ? stageUrl : localhostUrl;
        break;
      case AppEnvironment.prod:
        fallback = prodUrl;
        break;
    }
    var resolved = override.isNotEmpty ? override : fallback;
    if (env != AppEnvironment.dev &&
        !resolved.toLowerCase().startsWith('https://')) {
      resolved = fallback;
    }
    return resolved.replaceAll(RegExp(r'/+$'), '');
  }

  /// Resolves the base URL for the active environment.
  static String get baseUrl =>
      resolveBaseUrl(env: current, override: _baseUrlOverride);
}
