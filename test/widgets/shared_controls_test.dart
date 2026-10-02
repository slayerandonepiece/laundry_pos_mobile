import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_dropdown.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

void main() {
  group('PeriodRange', () {
    final now = DateTime(2026, 9, 30, 15);

    test('presets cover the last N days, inclusive of today', () {
      expect(PeriodRange.last7.from(now), DateTime(2026, 9, 24, 15));
      expect(PeriodRange.last30.from(now), DateTime(2026, 9, 1, 15));
      expect(PeriodRange.last90.from(now), DateTime(2026, 7, 3, 15));
      expect(PeriodRange.last7.to(now), now);
    });

    test(
      'month presets run from the 1st; previous month ends on its last day',
      () {
        expect(PeriodRange.thisMonth.from(now), DateTime(2026, 9, 1));
        expect(PeriodRange.thisMonth.to(now), now);
        expect(PeriodRange.previousMonth.from(now), DateTime(2026, 8, 1));
        expect(PeriodRange.previousMonth.to(now), DateTime(2026, 8, 31));
      },
    );

    test('contains is day-inclusive at both ends', () {
      final r = PeriodRange.last7;
      expect(r.contains(DateTime(2026, 9, 24, 0, 1), now), isTrue);
      expect(r.contains(DateTime(2026, 9, 23, 23, 59), now), isFalse);
      expect(r.contains(DateTime(2026, 9, 30, 23, 59), now), isTrue);
      expect(r.contains(DateTime(2026, 10, 1), now), isFalse);
    });

    test('granularity keeps charts readable', () {
      expect(PeriodRange.last7.granularity, 'day');
      expect(PeriodRange.last30.granularity, 'week');
      expect(PeriodRange.last90.granularity, 'month');
      PeriodRange custom(int days) => PeriodRange(
        'custom',
        customFrom: DateTime(2026, 1, 1),
        customTo: DateTime(2026, 1, 1).add(Duration(days: days - 1)),
      );
      expect(custom(10).granularity, 'day');
      expect(custom(60).granularity, 'week');
      expect(custom(200).granularity, 'month');
    });

    test(
      'only the current month is the default; equal selections compare equal',
      () {
        expect(PeriodRange.thisMonth.isDefault, isTrue);
        expect(PeriodRange.previousMonth.isDefault, isFalse);
        expect(PeriodRange.last30.isDefault, isFalse);
        expect(PeriodRange.last7.isDefault, isFalse);
        expect(PeriodRange.last7, const PeriodRange('7d'));
        expect(PeriodRange.last7 == PeriodRange.last90, isFalse);
      },
    );
  });

  group('AppDropdownField', () {
    Future<void> pump(WidgetTester tester, String value) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: AppDropdownField<String>(
                value: value,
                options: const [('all', 'Work status'), ('ready', 'Ready')],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('is 44px tall and shows the selected label', (tester) async {
      await pump(tester, 'all');
      expect(tester.getSize(find.byType(AppDropdownField<String>)).height, 44);
      expect(find.text('Work status'), findsOneWidget);
    });

    testWidgets('is tinted only while a non-default option is selected', (
      tester,
    ) async {
      Color? fill() {
        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(AppDropdownField<String>),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      await pump(tester, 'all');
      final idle = fill();
      await pump(tester, 'ready');
      expect(fill(), isNot(idle));
    });
  });

  group('Button sizes', () {
    testWidgets('shared buttons honour the three named heights', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PrimaryButton(label: 'Main', onPressed: () {}),
                PrimaryButton(
                  label: 'Inline',
                  height: AppButtonHeight.inline,
                  onPressed: () {},
                ),
                SecondaryButton(
                  label: 'Compact',
                  height: AppButtonHeight.compact,
                  onPressed: () {},
                ),
                TextActionButton(label: 'Text', onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      double heightOf(Finder f) => tester.getSize(f).height;
      expect(heightOf(find.widgetWithText(PrimaryButton, 'Main')), 52);
      expect(heightOf(find.widgetWithText(PrimaryButton, 'Inline')), 44);
      expect(heightOf(find.widgetWithText(SecondaryButton, 'Compact')), 36);
      expect(heightOf(find.byType(TextActionButton)), 44);
    });

    test(
      'no screen builds a raw Material button or a literal button height',
      () {
        final raw = RegExp(
          r'\b(ElevatedButton|OutlinedButton|FilledButton|TextButton)\s*(\.styleFrom)?\(',
        );
        final literalHeight = RegExp(r'height:\s*(4[0-9]|5[0-9])\s*,');
        final offenders = <String>[];
        for (final f in Directory('lib').listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          if (f.path.endsWith('shared/widgets/app_button.dart')) continue;
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (raw.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1} raw');
            // A literal size right after a shared button's constructor.
            if (literalHeight.hasMatch(lines[i]) &&
                lines
                    .sublist(i < 6 ? 0 : i - 6, i)
                    .any(
                      (l) =>
                          l.contains('PrimaryButton(') ||
                          l.contains('SecondaryButton('),
                    )) {
              offenders.add('${f.path}:${i + 1} literal height');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Use PrimaryButton / SecondaryButton / TextActionButton and '
              'AppButtonHeight.',
        );
      },
    );
  });
}
