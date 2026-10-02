import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:myshop/core/analytics/app_analytics.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the dev/stage diagnostics dialog can do (injectable for tests).
class DiagnosticsActions {
  const DiagnosticsActions({
    required this.sendTestEvent,
    required this.recordNonFatal,
    required this.forceCrash,
  });

  final Future<void> Function() sendTestEvent;
  final Future<void> Function() recordNonFatal;
  final Future<void> Function() forceCrash;
}

/// The installed app version, e.g. "Version 1.0.5 (7)", with the environment
/// appended outside production ("Version 1.0.5 (7) · Stage"). Shown on the
/// login screen and the profile screens so support can tell builds apart.
/// On dev and stage builds a long-press opens a diagnostics dialog.
class AppVersionText extends StatelessWidget {
  const AppVersionText({
    super.key,
    this.environment,
    this.diagnosticsActions,
    this.infoFuture,
  });

  final AppEnvironment? environment;
  final DiagnosticsActions? diagnosticsActions;
  final Future<PackageInfo?>? infoFuture;

  // Read once; the answer never changes while the app runs. A missing platform
  // plugin (tests) simply yields no text.
  static final Future<PackageInfo?> _info = PackageInfo.fromPlatform()
      .then<PackageInfo?>((info) => info)
      .catchError((_) => null);

  static bool diagnosticsEnabled(AppEnvironment environment) =>
      environment != AppEnvironment.prod;

  static DiagnosticsActions _defaultActions() => DiagnosticsActions(
    sendTestEvent: AppAnalytics.diagnosticsTest,
    recordNonFatal: () => FirebaseCrashlytics.instance.recordError(
      StateError('KlenPOS diagnostics test non-fatal'),
      StackTrace.current,
      fatal: false,
    ),
    forceCrash: () async => FirebaseCrashlytics.instance.crash(),
  );

  Future<void> _showDiagnostics(BuildContext context) async {
    final actions = diagnosticsActions ?? _defaultActions();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextActionButton(
              label: 'Send test event',
              onPressed: actions.sendTestEvent,
            ),
            TextActionButton(
              label: 'Record test non-fatal error',
              onPressed: actions.recordNonFatal,
            ),
            TextActionButton(
              label: 'Force test crash',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Force test crash?'),
                    content: const Text(
                      'The app will close immediately. Continue?',
                    ),
                    actions: [
                      TextActionButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.pop(confirmContext, false),
                      ),
                      TextActionButton(
                        label: 'Force crash',
                        onPressed: () => Navigator.pop(confirmContext, true),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await actions.forceCrash();
              },
            ),
          ],
        ),
        actions: [
          TextActionButton(
            label: 'Close',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  /// "Version 1.0.5 (7)" plus " · Stage" / " · Dev" outside production.
  static String format(
    String version,
    String buildNumber,
    AppEnvironment environment,
  ) {
    if (version.isEmpty) return '';
    final build = buildNumber.isNotEmpty ? ' ($buildNumber)' : '';
    final env = switch (environment) {
      AppEnvironment.stage => ' · Stage',
      AppEnvironment.dev => ' · Dev',
      AppEnvironment.prod => '',
    };
    return 'Version $version$build$env';
  }

  @override
  Widget build(BuildContext context) {
    final activeEnvironment = environment ?? AppEnvironmentConfig.current;
    return FutureBuilder<PackageInfo?>(
      future: infoFuture ?? _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null
            ? ''
            : format(info.version, info.buildNumber, activeEnvironment);
        return GestureDetector(
          onLongPress: diagnosticsEnabled(activeEnvironment)
              ? () => _showDiagnostics(context)
              : null,
          child: Text(
            text,
            key: const Key('app_version_text'),
            style: AppTextStyles.hint,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}
