import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_dropdown.dart';

void main() {
  Widget host(Widget child, {double scale = 1, double width = 320}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  group('TextActionButton', () {
    testWidgets('onPressed fires on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(TextActionButton(label: 'Retry', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Retry'));
      expect(taps, 1);
    });

    testWidgets('disabled: no callback, button reports disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const TextActionButton(label: 'Retry', onPressed: null)),
      );
      await tester.tap(find.text('Retry'), warnIfMissed: false);
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNull);
      expect(btn.enabled, isFalse);
    });

    testWidgets('tap target is at least 44 high by default and honours a '
        'custom height', (tester) async {
      await tester.pumpWidget(
        host(TextActionButton(label: 'Retry', onPressed: () {})),
      );
      expect(
        tester.getSize(find.byType(TextActionButton)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.pumpWidget(
        host(TextActionButton(label: 'Retry', height: 52, onPressed: () {})),
      );
      expect(tester.getSize(find.byType(TextActionButton)).height, 52);
    });

    testWidgets('a long label at 2x text scale does not overflow and stays '
        'tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Row(
            children: [
              Flexible(
                child: TextActionButton(
                  label: 'Discard everything and start the order again',
                  onPressed: () => taps++,
                ),
              ),
            ],
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextActionButton)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byType(TextActionButton));
      expect(taps, 1);
    });

    testWidgets('a long label in a narrow Expanded slot at 2x text scale '
        'does not overflow', (tester) async {
      await tester.pumpWidget(
        host(
          Row(
            children: [
              Expanded(
                child: TextActionButton(
                  label: 'Discard everything and start the order again',
                  onPressed: () {},
                ),
              ),
            ],
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Text>(
              find.text('Discard everything and start the order again'),
            )
            .overflow,
        TextOverflow.ellipsis,
      );
    });
  });

  group('AppDropdownField at large text', () {
    testWidgets('2x text scale in a 180pt slot keeps 44px height and throws '
        'nothing, including an open menu', (tester) async {
      String? picked;
      await tester.pumpWidget(
        host(
          AppDropdownField<String>(
            value: 'all',
            options: const [
              ('all', 'Work status with a very long label'),
              ('ready', 'Ready'),
            ],
            onChanged: (v) => picked = v,
          ),
          scale: 2,
          width: 180,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppDropdownField<String>)).height, 44);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ready').last);
      await tester.pumpAndSettle();
      expect(picked, 'ready');
    });
  });
}
