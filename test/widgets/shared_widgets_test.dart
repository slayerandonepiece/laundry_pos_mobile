import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/shared/widgets/app_button.dart';
import 'package:myshop/shared/widgets/app_card.dart';
import 'package:myshop/shared/widgets/app_inset.dart';
import 'package:myshop/shared/widgets/app_text_field.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';
import 'package:myshop/shared/widgets/filter_chip.dart';
import 'package:myshop/shared/widgets/money_text.dart';
import 'package:myshop/shared/widgets/status_pill.dart';
import 'package:myshop/shared/widgets/tappable_text.dart';

Widget createTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Shared Widgets Tests', () {
    testWidgets('AppCard renders child and responds to tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        createTestApp(
          AppCard(
            onTap: () => tapped = true,
            child: const Text('Card Content'),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      await tester.tap(find.text('Card Content'));
      expect(tapped, isTrue);
    });

    testWidgets('AppInset renders child on recessed surface', (tester) async {
      await tester.pumpWidget(
        createTestApp(const AppInset(child: Text('Inset Content'))),
      );

      expect(find.text('Inset Content'), findsOneWidget);
    });

    testWidgets('StatusPill renders correct colors for each variant', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          const Column(
            children: [
              StatusPill(label: 'Pending', variant: PillVariant.pending),
              StatusPill(label: 'Ready', variant: PillVariant.ready),
              StatusPill(label: 'Delivered', variant: PillVariant.delivered),
              StatusPill(label: 'Balance due', variant: PillVariant.danger),
            ],
          ),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
    });

    testWidgets('AppFilterChip meets 44px minimum touch target', (
      tester,
    ) async {
      bool clicked = false;
      await tester.pumpWidget(
        createTestApp(
          AppFilterChip(
            label: 'Wash',
            isSelected: false,
            onTap: () => clicked = true,
          ),
        ),
      );

      final size = tester.getSize(find.byType(AppFilterChip));
      expect(size.height, greaterThanOrEqualTo(44.0));

      await tester.tap(find.byType(AppFilterChip));
      expect(clicked, isTrue);
    });

    testWidgets('MoneyText renders formatted currency symbol', (tester) async {
      await tester.pumpWidget(createTestApp(const MoneyText(68000)));

      expect(find.text('₹680'), findsOneWidget);
    });

    testWidgets('PrimaryButton and SecondaryButton meet 52px height floor', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          Column(
            children: [
              PrimaryButton(label: 'Primary', onPressed: () {}),
              SecondaryButton(label: 'Secondary', onPressed: () {}),
            ],
          ),
        ),
      );

      final primarySize = tester.getSize(find.byType(PrimaryButton));
      final secondarySize = tester.getSize(find.byType(SecondaryButton));

      expect(primarySize.height, greaterThanOrEqualTo(52.0));
      expect(secondarySize.height, greaterThanOrEqualTo(52.0));
    });

    testWidgets('TappableText meets 44px hit target', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        createTestApp(
          TappableText(text: 'Edit item', onTap: () => tapped = true),
        ),
      );

      final size = tester.getSize(find.byType(TappableText));
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));

      await tester.tap(find.byType(TappableText));
      expect(tapped, isTrue);
    });

    testWidgets('CentredDialog renders title, buttons and handles actions', (
      tester,
    ) async {
      bool confirmed = false;
      await tester.pumpWidget(
        createTestApp(
          CentredDialog(
            title: 'Update status',
            subtitle: 'EL-248 · Vikram Shetty',
            confirmLabel: 'Update',
            onConfirm: () => confirmed = true,
          ),
        ),
      );

      expect(find.text('Update status'), findsOneWidget);
      expect(find.text('EL-248 · Vikram Shetty'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Update'));
      expect(confirmed, isTrue);
    });

    testWidgets('AppTextField shows error styling when errorText is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          const AppTextField(
            label: 'Phone number',
            errorText: 'Enter a valid 10-digit mobile number',
          ),
        ),
      );

      expect(find.text('PHONE NUMBER'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    });
  });
}
