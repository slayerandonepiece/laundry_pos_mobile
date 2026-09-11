import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Application deployment environments
enum AppEnvironment { dev, stage, prod }

/// Central environment configuration for MyShop
class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  /// Reads compile-time environment from `--dart-define=ENV=<dev|stage|prod>`.
  /// Defaults to `dev` if not specified.
  static const String _rawEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// Optional base URL override from `--dart-define=BASE_URL=<url>`.
  static const String _baseUrlOverride = String.fromEnvironment('BASE_URL', defaultValue: '');

  /// Active environment enum
  static AppEnvironment get current {
    switch (_rawEnv.toLowerCase()) {
      case 'stage':
      case 'staging':
        return AppEnvironment.stage;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }

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
    return 'https://express-laundry-staging.vercel.app';
  }

  /// Production URL definition (left empty per requirements, add when ready)
  static String get prodUrl {
    // Production URL — leave empty for now, add when ready:
    return '';
  }

  /// Resolves the base URL for the active environment:
  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) {
      return _baseUrlOverride;
    }

    switch (current) {
      case AppEnvironment.dev:
        return localhostUrl;
      case AppEnvironment.stage:
        final url = stageUrl;
        return url.isNotEmpty ? url : localhostUrl;
      case AppEnvironment.prod:
        return prodUrl;
    }
  }
}
