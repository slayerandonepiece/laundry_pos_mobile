import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_environment.dart';
import 'package:myshop/shared/widgets/app_version_text.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('AppVersionText.format', () {
    test('shows version and build; prod has no environment suffix', () {
      expect(
        AppVersionText.format('1.0.5', '7', AppEnvironment.prod),
        'Version 1.0.5 (7)',
      );
    });

    test('marks stage and dev builds', () {
      expect(
        AppVersionText.format('1.0.5', '7', AppEnvironment.stage),
        'Version 1.0.5 (7) · Stage',
      );
      expect(
        AppVersionText.format('1.0.5', '7', AppEnvironment.dev),
        'Version 1.0.5 (7) · Dev',
      );
    });

    test(
      'drops a missing build number and shows nothing without a version',
      () {
        expect(
          AppVersionText.format('1.0.5', '', AppEnvironment.prod),
          'Version 1.0.5',
        );
        expect(AppVersionText.format('', '7', AppEnvironment.prod), '');
      },
    );
  });

  testWidgets('renders the installed version from the platform', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'KlenPOS',
      packageName: 'com.reddygona.klenpos',
      version: '1.0.5',
      buildNumber: '7',
      buildSignature: '',
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionText())),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // The test environment is dev, so the label says so.
    expect(find.text('Version 1.0.5 (7) · Dev'), findsOneWidget);
  });
}
