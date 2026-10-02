import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app version, e.g. "Version 1.0.5 (7)", with the environment
/// appended outside production ("Version 1.0.5 (7) · Stage"). Shown on the
/// login screen and the profile screens so support can tell builds apart.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key});

  // Read once; the answer never changes while the app runs. A missing platform
  // plugin (tests) simply yields no text.
  static final Future<PackageInfo?> _info = PackageInfo.fromPlatform()
      .then<PackageInfo?>((info) => info)
      .catchError((_) => null);

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
    return FutureBuilder<PackageInfo?>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null
            ? ''
            : format(
                info.version,
                info.buildNumber,
                AppEnvironmentConfig.current,
              );
        return Text(
          text,
          key: const Key('app_version_text'),
          style: AppTextStyles.hint,
          textAlign: TextAlign.center,
        );
      },
    );
  }
}
