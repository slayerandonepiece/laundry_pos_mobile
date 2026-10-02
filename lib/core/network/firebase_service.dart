import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/logging/app_logger.dart';

/// Centralized Firebase initialization and management service for KlenPOS.
class FirebaseService {
  FirebaseService._();

  static FirebaseAnalytics? analytics;
  static FirebaseMessaging? messaging;
  static FirebaseRemoteConfig? remoteConfig;
  static bool hasSuccessfulFetch = false;

  /// True once Crashlytics is initialized; until then reports are dropped.
  static bool crashlyticsReady = false;

  /// Initializes all configured Firebase services according to the active flavor/environment.
  static Future<void> initialize() async {
    // Firebase mobile plugins (Crashlytics, Messaging APNs) target iOS and Android
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      AppLogger.log(
        'FIREBASE_INIT',
        'Skipping Firebase initialization on unsupported non-mobile platform.',
      );
      return;
    }

    try {
      // 1. Core Firebase initialization
      // Config is supplied natively by google-services.json (Android) or GoogleService-Info.plist (iOS)
      await Firebase.initializeApp();
      AppLogger.log('FIREBASE_INIT', 'FirebaseCore initialized successfully.');

      // 2. Crashlytics Setup
      final crashlytics = FirebaseCrashlytics.instance;
      // Disable Crashlytics in debug mode to prevent polluting development metrics
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      crashlyticsReady = true;
      // The error handlers that feed Crashlytics live in ErrorReporting.

      // 3. Analytics Setup
      analytics = FirebaseAnalytics.instance;
      await analytics?.setUserProperty(
        name: 'environment',
        value: AppEnvironmentConfig.name,
      );

      // 4. Remote Config Setup
      remoteConfig = FirebaseRemoteConfig.instance;
      final isDevOrStage =
          AppEnvironmentConfig.isDev || AppEnvironmentConfig.isStage;
      await remoteConfig?.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: isDevOrStage
              ? const Duration(seconds: 0)
              : const Duration(hours: 12),
        ),
      );

      // Safe inert defaults so nothing blocks until explicitly set in Firebase console
      await remoteConfig?.setDefaults({
        'min_supported_version': '',
        'force_update_enabled': false,
        'ios_app_store_id': '',
        'maintenance_mode_enabled': false,
        'maintenance_message':
            "${AppEnvironmentConfig.appName} is undergoing scheduled maintenance. We'll be back shortly.",
        'maintenance_eta': '',
      });

      try {
        await remoteConfig?.fetchAndActivate();
        hasSuccessfulFetch = true;
      } catch (fetchError) {
        hasSuccessfulFetch = false;
        AppLogger.log(
          'FIREBASE_REMOTE_CONFIG',
          'Initial Remote Config fetch failed (failing open): $fetchError',
          error: fetchError,
        );
      }

      // 5. Cloud Messaging Setup (Push notifications)
      messaging = FirebaseMessaging.instance;
      final notificationSettings = await messaging?.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      AppLogger.log(
        'FIREBASE_MESSAGING',
        'Notification permission status: ${notificationSettings?.authorizationStatus}',
      );

      // Fetch and log APNs/FCM token safely (APNs might not be immediate on iOS / Simulators)
      try {
        if (Platform.isIOS) {
          final apnsToken = await messaging?.getAPNSToken();
          if (apnsToken != null) {
            final fcmToken = await messaging?.getToken();
            AppLogger.log('FIREBASE_MESSAGING', 'FCM Token: $fcmToken');
          } else {
            AppLogger.log(
              'FIREBASE_MESSAGING',
              'APNs token not yet received (normal on iOS simulator). Token will be resolved once registered.',
            );
          }
        } else {
          final fcmToken = await messaging?.getToken();
          AppLogger.log('FIREBASE_MESSAGING', 'FCM Token: $fcmToken');
        }
      } catch (tokenError) {
        AppLogger.log(
          'FIREBASE_MESSAGING',
          'Could not retrieve FCM token: $tokenError',
        );
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.log(
          'FIREBASE_MESSAGING',
          'Foreground message received: ${message.notification?.title ?? "No title"}',
        );
      });

      AppLogger.log(
        'FIREBASE_INIT',
        'Firebase successfully initialized for environment: [${AppEnvironmentConfig.name}]',
      );
    } catch (e) {
      AppLogger.log(
        'FIREBASE_INIT_ERROR',
        'Firebase initialization error: $e',
        error: e,
      );
    }
  }

  /// Reports an uncaught error to Crashlytics as fatal (no-op until ready).
  static void recordFatal(Object error, StackTrace? stack) {
    if (!crashlyticsReady) return;
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  }

  /// Reports an uncaught Flutter framework error as fatal (no-op until ready).
  static void recordFlutterFatal(FlutterErrorDetails details) {
    if (!crashlyticsReady) return;
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  /// Re-fetches and activates Remote Config values. Returns true if the network fetch succeeded.
  static Future<bool> refreshRemoteConfig() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    if (remoteConfig == null) {
      return false;
    }
    try {
      await remoteConfig!.fetchAndActivate();
      hasSuccessfulFetch = true;
      return true;
    } catch (e) {
      AppLogger.log(
        'FIREBASE_REMOTE_CONFIG',
        'Remote Config refresh failed: $e',
        error: e,
      );
      return false;
    }
  }

  // Remote Config runtime getters — dynamically read from Remote Config at runtime
  static bool get isMaintenanceModeEnabled =>
      remoteConfig?.getBool('maintenance_mode_enabled') ?? false;

  static String get maintenanceMessage =>
      remoteConfig?.getString('maintenance_message') ??
      "${AppEnvironmentConfig.appName} is undergoing scheduled maintenance. We'll be back shortly.";

  static String get maintenanceEta =>
      remoteConfig?.getString('maintenance_eta') ?? '';

  static bool get isForceUpdateEnabled =>
      remoteConfig?.getBool('force_update_enabled') ?? false;

  static String get minSupportedVersion =>
      remoteConfig?.getString('min_supported_version') ?? '';

  static String get iosAppStoreId =>
      remoteConfig?.getString('ios_app_store_id') ?? '';
}
