import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

import '../../features/orders/bloc/orders_state.dart';
import '../../features/pos/bloc/cart_state.dart';
import '../logging/app_logger.dart';
import '../network/firebase_service.dart';

/// The result of evaluating app startup or resume gate conditions.
enum GateDecision { proceed, maintenance, androidForceUpdate, iosForceUpdate }

/// Custom Upgrader messages that show "Update" as the primary action.
class ForceUpdateUpgraderMessages extends UpgraderMessages {
  @override
  String? message(UpgraderMessage messageKey) {
    if (messageKey == UpgraderMessage.buttonTitleUpdate) {
      return 'Update';
    }
    return super.message(messageKey);
  }
}

/// Upgrader store for iOS that looks up the product via [iosAppStoreId].
/// Fails open gracefully if [appStoreId] is empty or iTunes Lookup fails.
class IosAppStoreUpgraderStore extends UpgraderStore {
  final String appStoreId;

  IosAppStoreUpgraderStore({required this.appStoreId});

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    // Fail open if app store ID is empty (no store listing yet)
    if (appStoreId.trim().isEmpty || state.packageInfo == null) {
      return UpgraderVersionInfo();
    }

    try {
      final iTunes = ITunesSearchAPI();
      iTunes.debugLogging = state.debugLogging;
      iTunes.client = state.client;
      iTunes.clientHeaders = state.clientHeaders;

      final response = await iTunes.lookupById(
        appStoreId.trim(),
        country: country ?? 'US',
      );

      if (response == null) {
        return UpgraderVersionInfo();
      }

      final versionStr = iTunes.version(response);
      Version? appStoreVersion;
      if (versionStr != null) {
        try {
          appStoreVersion = Version.parse(versionStr);
        } catch (_) {}
      }

      final appStoreListingURL =
          iTunes.trackViewUrl(response) ??
          'https://apps.apple.com/app/id${appStoreId.trim()}';
      final releaseNotes = iTunes.releaseNotes(response);
      final minAppVersion = iTunes.minAppVersion(response);

      return UpgraderVersionInfo(
        installedVersion: installedVersion,
        appStoreListingURL: appStoreListingURL,
        appStoreVersion: appStoreVersion,
        minAppVersion: minAppVersion,
        releaseNotes: releaseNotes,
      );
    } catch (e) {
      AppLogger.log(
        'APP_GATE_IOS',
        'iTunes lookup failed (failing open): $e',
        error: e,
      );
      // Fail open on any lookup error
      return UpgraderVersionInfo();
    }
  }
}

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

  /// Performs Android immediate update via Google Play Core (in_app_update).
  /// Fails open gracefully if offline, sideloaded, or on any error.
  static Future<void> performAndroidForceUpdateIfNeeded() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!FirebaseService.hasSuccessfulFetch ||
        !FirebaseService.isForceUpdateEnabled) {
      return;
    }

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable &&
          updateInfo.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      AppLogger.log(
        'APP_GATE_ANDROID',
        'InAppUpdate check/perform failed (failing open): $e',
        error: e,
      );
    }
  }

  /// Builds a configured [Upgrader] instance for iOS force-update flow.
  /// If [forceUpdateEnabled] is false, or store ID is empty, Upgrader no-ops safely.
  static Upgrader createUpgrader({
    bool? forceUpdateEnabled,
    String? minSupportedVersion,
    String? iosAppStoreId,
    UpgraderStore? customStore,
  }) {
    final isEnabled =
        forceUpdateEnabled ?? FirebaseService.isForceUpdateEnabled;
    final minVer = (minSupportedVersion ?? FirebaseService.minSupportedVersion)
        .trim();
    final storeId = (iosAppStoreId ?? FirebaseService.iosAppStoreId).trim();

    final shouldEnforce = isEnabled && minVer.isNotEmpty && storeId.isNotEmpty;

    return Upgrader(
      minAppVersion: shouldEnforce ? minVer : null,
      showOnlyMandatoryUpdates: true,
      storeController: UpgraderStoreController(
        oniOS: () =>
            customStore ?? IosAppStoreUpgraderStore(appStoreId: storeId),
      ),
      messages: ForceUpdateUpgraderMessages(),
    );
  }
}
