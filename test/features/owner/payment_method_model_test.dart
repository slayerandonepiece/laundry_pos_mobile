import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';

void main() {
  group('StorePaymentMethod.fromJson tolerance (O0.A)', () {
    test('parses active: true when active is explicitly true', () {
      final model = StorePaymentMethod.fromJson({
        'id': 'pm_1',
        'name': 'Cash',
        'active': true,
      });
      expect(model.active, isTrue);
    });

    test('parses active: false when active is explicitly false', () {
      final model = StorePaymentMethod.fromJson({
        'id': 'pm_1',
        'name': 'Cash',
        'active': false,
      });
      expect(model.active, isFalse);
    });

    test('falls back to enabled: true when active is null/absent', () {
      final model = StorePaymentMethod.fromJson({
        'id': 'pm_2',
        'name': 'UPI',
        'enabled': true,
      });
      expect(model.active, isTrue);
    });

    test('falls back to enabled: false when active is null/absent', () {
      final model = StorePaymentMethod.fromJson({
        'id': 'pm_2',
        'name': 'UPI',
        'enabled': false,
      });
      expect(model.active, isFalse);
    });

    test('active takes precedence over enabled when both are present', () {
      final modelActiveFalse = StorePaymentMethod.fromJson({
        'id': 'pm_3',
        'name': 'Card',
        'active': false,
        'enabled': true,
      });
      expect(modelActiveFalse.active, isFalse);

      final modelActiveTrue = StorePaymentMethod.fromJson({
        'id': 'pm_3',
        'name': 'Card',
        'active': true,
        'enabled': false,
      });
      expect(modelActiveTrue.active, isTrue);
    });

    test('defaults to true when both active and enabled are null/absent', () {
      final model = StorePaymentMethod.fromJson({
        'id': 'pm_4',
        'name': 'GPay',
      });
      expect(model.active, isTrue);
    });
  });
}
