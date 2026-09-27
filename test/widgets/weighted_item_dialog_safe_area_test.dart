import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';
import 'package:myshop/features/pos/presentation/dialogs/weighted_item_dialog.dart';

void main() {
  testWidgets(
    'WeightedItemDialog sheet top edge respects top safe area (status bar / Dynamic Island) when keyboard is open',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewInsets();
      });

      final product = Product(
        id: 'prod-wf',
        name: 'Wash & Fold',
        category: 'Laundry',
        type: 'weight',
        slabs: [
          PricingSlab(limit: 5, price: 25000),
          PricingSlab(limit: 10, price: 45000),
          PricingSlab(limit: 15, price: 65000),
          PricingSlab(limit: 20, price: 85000),
        ],
        extra: 5000,
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.8),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    WeightedItemDialog.show(
                      context,
                      product: product,
                      onAdd: (_) {},
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // The sheet's top edge must be at or below the top safe area (59pt for Dynamic Island)
      final sheetTop = tester.getTopLeft(find.byType(WeightedItemDialog)).dy;
      expect(sheetTop, greaterThanOrEqualTo(59.0));

      // 'Add to sale' is in the sticky footer and must stay visible above the keyboard (874 - 336 = 538)
      final addToSaleFinder = find.text('Add to sale');
      expect(addToSaleFinder, findsOneWidget);
      expect(tester.getTopLeft(addToSaleFinder).dy, lessThan(874 - 336));
      expect(tester.getBottomRight(addToSaleFinder).dy, lessThanOrEqualTo(874 - 336));
    },
  );
}
