import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/auth/presentation/splash_screen.dart';

void main() {
  testWidgets(
    'SplashScreen renders branding elements and triggers callback on completion',
    (WidgetTester tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onAnimationComplete: () {
              completed = true;
            },
          ),
        ),
      );

      // Initial frame
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(completed, isFalse);

      // Verify circular logo is present on initial frame
      final clipOvalFinder = find.byType(ClipOval);
      expect(clipOvalFinder, findsOneWidget);

      final imageFinder = find.descendant(
        of: clipOvalFinder,
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);
      final Image image = tester.widget(imageFinder);
      expect(image.width, equals(160.0));
      expect(image.height, equals(160.0));

      // Verify circular reveal ClipPath is present
      expect(find.byType(ClipPath), findsOneWidget);

      // Advance animation to completion
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('KlenPOS'),
        ),
        findsOneWidget,
      );
      expect(find.text('Laundry POS counter'), findsOneWidget);
    },
  );

  testWidgets(
    'SplashScreen logo is positioned in the exact horizontal and vertical center',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        const MaterialApp(home: SplashScreen(animate: false)),
      );
      await tester.pump();

      final clipOvalFinder = find.byType(ClipOval);
      expect(clipOvalFinder, findsOneWidget);

      final center = tester.getCenter(clipOvalFinder);
      // Logical size: 1080 / 2.0 = 540, 2400 / 2.0 = 1200
      expect(center.dx, equals(270.0));
      expect(center.dy, equals(600.0));
    },
  );

  testWidgets('SplashScreen with animate: false completes immediately', (
    WidgetTester tester,
  ) async {
    bool completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          animate: false,
          onAnimationComplete: () {
            completed = true;
          },
        ),
      ),
    );

    await tester.pump();
    expect(completed, isTrue);
  });
}
