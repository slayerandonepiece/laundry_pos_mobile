import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/utils/phone_normalizer.dart';

void main() {
  group('tenDigitPhone', () {
    test('strips +91 country code and spaces', () {
      expect(tenDigitPhone('+91 98765 43210'), '9876543210');
    });

    test('strips leading trunk 0', () {
      expect(tenDigitPhone('09876543210'), '9876543210');
    });

    test('strips spaces from a 10-digit number', () {
      expect(tenDigitPhone('98765 43210'), '9876543210');
    });

    test('strips bare 91 prefix on a 12-digit number', () {
      expect(tenDigitPhone('919876543210'), '9876543210');
    });

    test('leaves a short number as-is (not padded)', () {
      expect(tenDigitPhone('12345'), '12345');
    });

    test('never truncates a 13-digit number', () {
      expect(tenDigitPhone('9198765432101'), '9198765432101');
    });
  });
}
