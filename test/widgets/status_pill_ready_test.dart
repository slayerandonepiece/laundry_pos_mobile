import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/shared/widgets/status_pill.dart';

void main() {
  Future<(Color, Color)> pillColors(
    WidgetTester tester,
    StatusPill pill,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: pill)));
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byWidget(pill),
        matching: find.byType(Container),
      ),
    );
    final bg = (container.decoration! as BoxDecoration).color!;
    final text = tester.widget<Text>(find.text(pill.label)).style!.color!;
    return (text, bg);
  }

  testWidgets('Ready pill is violet', (tester) async {
    final (text, bg) = await pillColors(tester, StatusPill.fromStatus('Ready'));
    expect(text, AppColors.violet);
    expect(bg, AppColors.violetBg);
  });

  testWidgets('Ready pill differs from the amber Unpaid pill', (tester) async {
    final (readyText, readyBg) = await pillColors(
      tester,
      const StatusPill(label: 'Ready', variant: PillVariant.ready),
    );
    final (unpaidText, unpaidBg) = await pillColors(
      tester,
      const StatusPill(label: 'Unpaid', variant: PillVariant.warning),
    );
    expect(unpaidText, AppColors.warning);
    expect(unpaidBg, AppColors.warningBg);
    expect(readyText, isNot(unpaidText));
    expect(readyBg, isNot(unpaidBg));
  });
}
