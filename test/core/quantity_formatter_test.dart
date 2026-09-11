import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/utils/quantity_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/pos/bloc/cart_state.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

void main() {
  group('QuantityFormatter Tests', () {
    test('Formats integer and round values without decimal places', () {
      expect(QuantityFormatter.format(2), equals('2'));
      expect(QuantityFormatter.format(2.0), equals('2'));
      expect(QuantityFormatter.formatWeight(2.0), equals('2 kg'));
      expect(QuantityFormatter.format(10.0), equals('10'));
    });

    test('Formats 1 and 2 decimal places stripping trailing zeros', () {
      expect(QuantityFormatter.format(2.5), equals('2.5'));
      expect(QuantityFormatter.formatWeight(2.5), equals('2.5 kg'));
      expect(QuantityFormatter.format(2.75), equals('2.75'));
      expect(QuantityFormatter.formatWeight(2.75), equals('2.75 kg'));
    });

    test('Formats up to 3 decimal places without truncation', () {
      expect(QuantityFormatter.format(2.755), equals('2.755'));
      expect(QuantityFormatter.formatWeight(2.755), equals('2.755 kg'));
      expect(QuantityFormatter.format(0.125), equals('0.125'));
      expect(QuantityFormatter.formatWeight(0.125), equals('0.125 kg'));
    });

    test('OrderLine displayQuantity formats weight with up to 3 decimals and strips zeros', () {
      final line1 = OrderLine(
        productId: 'p1',
        name: 'Wash & Fold',
        quantity: 2.755,
        unit: 'WEIGHT',
        amount: 300,
      );
      expect(line1.displayQuantity, equals('2.755 kg'));

      final line2 = OrderLine(
        productId: 'p1',
        name: 'Wash & Fold',
        quantity: 4.0,
        unit: 'WEIGHT',
        amount: 300,
      );
      expect(line2.displayQuantity, equals('4 kg'));

      final line3 = OrderLine(
        productId: 'p1',
        name: 'Wash & Fold',
        quantity: 3.5,
        unit: 'WEIGHT',
        amount: 300,
      );
      expect(line3.displayQuantity, equals('3.5 kg'));
    });

    test('CartItem displayQuantity formats weight with up to 3 decimals and strips zeros', () {
      final product = Product(
        id: 'p1',
        name: 'Wash & Fold',
        category: 'wash',
        type: 'weight',
        slabs: [PricingSlab(limit: 5.0, price: 300)],
      );

      final item1 = CartItem(product: product, quantity: 2.755);
      expect(item1.displayQuantity, equals('2.755 kg'));

      final item2 = CartItem(product: product, quantity: 3.0);
      expect(item2.displayQuantity, equals('3 kg'));

      final item3 = CartItem(product: product, quantity: 3.5);
      expect(item3.displayQuantity, equals('3.5 kg'));
    });
  });
}
