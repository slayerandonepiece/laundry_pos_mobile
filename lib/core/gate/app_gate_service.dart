import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_update_flutter/in_app_update_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:version/version.dart';

import '../../features/orders/bloc/orders_state.dart';
import '../../features/pos/bloc/cart_state.dart';
import '../logging/app_logger.dart';
import '../network/firebase_service.dart';

/// The result of evaluating app startup or resume gate conditions.
enum GateDecision { proceed, maintenance, androidForceUpdate, iosForceUpdate }

/// Central gateway service for Remote Config driven maintenance mode & force-updates.
class AppGateService {
  AppGateService._();

  /// Compares the installed application version against [minSupportedVersion].
  /// Returns `true` only if installed < minSupported.
  /// Fails open (returns `false`) if versions are invalid, empty, or cannot be parsed.
  static Future<bool> isInstalledVersionBelowMinSupported({
    String? minVersionOverride,
    String? installedVersionOverride,
  }) async {
    final minVerStr =
        (minVersionOverride ?? FirebaseService.minSupportedVersion).trim();
    if (minVerStr.isEmpty) return false;

    try {
      final installedStr =
          installedVersionOverride ??
          (await PackageInfo.fromPlatform()).version;
      final installed = Version.parse(installedStr);
      final minVer = Version.parse(minVerStr);
      return installed < minVer;
    } catch (e) {
      AppLogger.log(
        'APP_GATE',
        'Version compare failed (failing open): $e',
        error: e,
      );
      return false;
    }
  }

  /// Evaluates app conditions in order:
  /// 1. maintenance_mode_enabled — blocks with maintenance screen (highest priority).
  /// 2. force_update_enabled — platform-specific check.
  /// 3. proceed — continue unchanged.
  ///
  /// Fails OPEN if Remote Config fetch did not succeed or values are not explicitly enabled.
  static Future<GateDecision> evaluateGate({
    bool? hasSuccessfulFetchOverride,
    bool? isMaintenanceModeOverride,
    bool? isForceUpdateOverride,
    String? minSupportedVersionOverride,
    String? iosAppStoreIdOverride,
    String? installedVersionOverride,
  }) async {
    final hasFetch =
        hasSuccessfulFetchOverride ?? FirebaseService.hasSuccessfulFetch;
    if (!hasFetch) {
      // Offline, timeout, or outage: fail OPEN
      return GateDecision.proceed;
    }

    // 1. Maintenance Mode (Highest Priority)
    final maintenanceEnabled =
        isMaintenanceModeOverride ?? FirebaseService.isMaintenanceModeEnabled;
    if (maintenanceEnabled) {
      return GateDecision.maintenance;
    }

    // 2. Force Update
    final forceUpdateEnabled =
        isForceUpdateOverride ?? FirebaseService.isForceUpdateEnabled;
    if (forceUpdateEnabled) {
      if (!kIsWeb && Platform.isAndroid) {
        return GateDecision.androidForceUpdate;
      }
      if (!kIsWeb && Platform.isIOS) {
        final storeId = (iosAppStoreIdOverride ?? FirebaseService.iosAppStoreId)
            .trim();
        // If ios_app_store_id is empty, fail open
        if (storeId.isEmpty) {
          return GateDecision.proceed;
        }

        final isBelow = await isInstalledVersionBelowMinSupported(
          minVersionOverride: minSupportedVersionOverride,
          installedVersionOverride: installedVersionOverride,
        );
        if (isBelow) {
          return GateDecision.iosForceUpdate;
        }
      }
    }

    // 3. Normal Flow
    return GateDecision.proceed;
  }

  /// Checks whether user is mid-transaction in either the POS or Orders bloc.
  /// If true, resume checks defer showing blocking gates so live sales are never interrupted.
  static bool isMidTransaction({
    required CartState cartState,
    required OrdersState ordersState,
  }) {
    return cartState.isSubmitting ||
        ordersState.isCollectingPayment ||
        cartState.hasItems;
  }

  static final InAppUpdateFlutter _updater = InAppUpdateFlutter();

  /// Performs the Android immediate update when Remote Config enables it.
  static Future<void> performAndroidForceUpdateIfNeeded() async {
    if (!FirebaseService.hasSuccessfulFetch ||
        !FirebaseService.isForceUpdateEnabled) {
      return;
    }
    await startAndroidUpdate(immediate: true);
  }

  /// Starts the Google Play update flow: immediate (blocking) or flexible
  /// (background download). Fails open if offline, sideloaded, declined, or on
  /// any other error.
  static Future<void> startAndroidUpdate({required bool immediate}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await _updater.checkUpdateAndroid();
      if (info.updateAvailability !=
          UpdateAvailabilityAndroid.updateAvailable) {
        return;
      }
      if (immediate && info.isImmediateUpdateAllowed) {
        await _updater.startImmediateUpdateAndroid();
      } else if (!immediate && info.isFlexibleUpdateAllowed) {
        await _updater.startFlexibleUpdateAndroid();
      }
    } catch (e) {
      AppLogger.log(
        'APP_GATE_ANDROID',
        'In-app update failed (failing open): $e',
        error: e,
      );
    }
  }

  /// Download state of a flexible update, for offering "Restart to update".
  static Stream<InstallStateAndroid> get androidInstallState =>
      _updater.installStateStreamAndroid;

  static Future<void> completeAndroidUpdate() async {
    try {
      await _updater.completeUpdateAndroid();
    } catch (e) {
      AppLogger.log('APP_GATE_ANDROID', 'Complete update failed: $e', error: e);
    }
  }

  /// Opens the App Store product page in-app. Returns false without a store
  /// ID or when the sheet could not be shown.
  static Future<bool> showIosUpdateSheet() async {
    final storeId = FirebaseService.iosAppStoreId.trim();
    if (kIsWeb || !Platform.isIOS || storeId.isEmpty) return false;
    try {
      await _updater.showUpdateForIos(appStoreId: storeId);
      return true;
    } catch (e) {
      AppLogger.log('APP_GATE_IOS', 'App Store sheet failed: $e', error: e);
      return false;
    }
  }

  /// Fallback when the in-app sheet fails: opens the App Store listing itself.
  static Future<bool> openAppStorePage() async {
    final storeId = FirebaseService.iosAppStoreId.trim();
    if (kIsWeb || storeId.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse('https://apps.apple.com/app/id$storeId'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      AppLogger.log('APP_GATE_IOS', 'App Store page failed: $e', error: e);
      return false;
    }
  }
}
