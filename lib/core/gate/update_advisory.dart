import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/api_endpoints.dart';

/// How strongly the backend wants this install to update.
enum UpdateLevel { none, soft, urgent }

/// Backend-driven update advisory. The API advertises it on every response via
/// `X-Update-Level` (never by rejecting a request), so ongoing work is never
/// interrupted; the UI decides when it is safe to show.
class UpdateAdvisory {
  UpdateAdvisory._();

  static const String levelHeader = 'x-update-level';
  static const String minVersionHeader = 'x-update-min-version';

  static final ValueNotifier<UpdateLevel> level = ValueNotifier(
    UpdateLevel.none,
  );

  /// Ticks on every response that carries a level, even an unchanged one, so a
  /// prompt held back at an unsafe moment is retried as soon as it is safe.
  static final ValueNotifier<int> responses = ValueNotifier(0);

  static String? _version;
  static String? _build;

  /// The minimum version behind the latest soft/urgent level, from the same
  /// reply as the level; null when the backend named none.
  static String? latestMinVersion;

  static String? get installedVersion => _version;

  /// Loads the installed version once so requests can report it.
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _build = info.buildNumber;
    } catch (_) {
      // Never block startup: without a version the backend has nothing to compare.
    }
  }

  /// Headers identifying this install; empty until [init] has run.
  static Map<String, String> get requestHeaders => {
    if (_version != null) ...{
      'X-App-Platform': Platform.isIOS ? 'ios' : 'android',
      'X-App-Version': _version!,
      'X-App-Build': _build ?? '',
    },
  };

  /// Maps a header value to a level. Unknown or missing values mean "no
  /// information" (null) so an older backend never resets a known level.
  static UpdateLevel? parse(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'none':
        return UpdateLevel.none;
      case 'soft':
        return UpdateLevel.soft;
      case 'urgent':
        return UpdateLevel.urgent;
      default:
        return null;
    }
  }

  /// Compares dotted versions numerically (`1.10.0` is newer than `1.9.0`,
  /// `1.2` equals `1.2.0`), like the backend does. Null if either side cannot
  /// be read, so a bad value is never mistaken for an answer.
  static int? compareVersions(String? a, String? b) {
    List<int>? parts(String? v) {
      final m = RegExp(r'^(\d{1,6})(?:\.(\d{1,6}))?(?:\.(\d{1,6}))?$')
          .firstMatch((v ?? '').trim());
      if (m == null) return null;
      return [for (var i = 1; i <= 3; i++) int.parse(m.group(i) ?? '0')];
    }

    final x = parts(a);
    final y = parts(b);
    if (x == null || y == null) return null;
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
    }
    return 0;
  }

  /// The level that really applies to this install: the backend's word,
  /// double-checked against the installed version. If the install is already
  /// at or above the named minimum the level is ignored, so a stale or wrong
  /// reply can never block an up-to-date app. If either version cannot be
  /// read, the backend's level stands.
  static UpdateLevel effectiveLevel({
    required UpdateLevel level,
    required String? minVersion,
    required String? installedVersion,
  }) {
    if (level == UpdateLevel.none) return UpdateLevel.none;
    final cmp = compareVersions(installedVersion, minVersion);
    if (cmp != null && cmp >= 0) return UpdateLevel.none;
    return level;
  }

  /// [effectiveLevel] for the latest reply and this install.
  static UpdateLevel get effective => effectiveLevel(
    level: level.value,
    minVersion: latestMinVersion,
    installedVersion: _version,
  );

  /// What to offer right now, or null. Kept pure so the rules are testable:
  /// nothing is offered mid-flow or at an unsafe moment, and each level is
  /// offered once until the backend returns to [UpdateLevel.none].
  static UpdateLevel? nextOffer({
    required UpdateLevel level,
    required bool flowActive,
    required bool softOffered,
    required bool urgentOffered,
    required bool safeMoment,
  }) {
    if (level == UpdateLevel.none || flowActive || !safeMoment) return null;
    if (level == UpdateLevel.soft && softOffered) return null;
    if (level == UpdateLevel.urgent && urgentOffered) return null;
    return level;
  }

  /// Asks the server for the current level with a plain, unauthenticated
  /// request. Even its 401 reply carries the level, and nothing here touches
  /// the session, so it is safe while signed out. Used while a blocker is up,
  /// when the app may otherwise be idle and never hear that it was lifted.
  /// Never throws; no connection simply changes nothing.
  static Future<void> probe({Dio? dio}) async {
    try {
      final res = await (dio ?? Dio()).get<dynamic>(
        ApiEndpoints.sessionStatus,
        options: Options(
          headers: requestHeaders,
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      record(
        res.headers.value(levelHeader),
        res.headers.value(minVersionHeader),
      );
    } catch (_) {
      // Offline or slow: keep what we know.
    }
  }

  /// Records the level (and the minimum version behind it) advertised by a
  /// response. A reply without a level says nothing and changes nothing.
  static void record(String? levelValue, [String? minVersionValue]) {
    final parsed = parse(levelValue);
    if (parsed == null) return;
    final min = minVersionValue?.trim();
    latestMinVersion = parsed == UpdateLevel.none || min == null || min.isEmpty
        ? null
        : min;
    level.value = parsed;
    responses.value++;
  }
}
