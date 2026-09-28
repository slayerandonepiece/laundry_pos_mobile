// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/theme/app_theme.dart';
import 'package:myshop/core/constants/app_colors.dart';

void main() {
  testWidgets('AppTheme configuration smoke test', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, equals(AppColors.primary));
    expect(theme.useMaterial3, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const Scaffold(body: Center(child: Text('KlenPOS Smoke Test'))),
      ),
    );

    expect(find.text('KlenPOS Smoke Test'), findsOneWidget);
  });
}
