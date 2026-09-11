import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _inrWholeFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _inrDecimalFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _pdfWholeFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs. ',
    decimalDigits: 0,
  );

  static final NumberFormat _pdfDecimalFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs. ',
    decimalDigits: 2,
  );

  /// Formats amount in paise for UI display (e.g. 30000 paise -> ₹300, 2550 paise -> ₹25.50)
  static String format(num amountInPaise) {
    final rupees = amountInPaise / 100.0;
    if (rupees == rupees.roundToDouble()) {
      return _inrWholeFormatter.format(rupees.toInt());
    }
    return _inrDecimalFormatter.format(rupees);
  }

  /// Formats amount in paise for PDF documents (e.g. 30000 paise -> Rs. 300)
  static String formatPdf(num amountInPaise) {
    final rupees = amountInPaise / 100.0;
    if (rupees == rupees.roundToDouble()) {
      return _pdfWholeFormatter.format(rupees.toInt());
    }
    return _pdfDecimalFormatter.format(rupees);
  }
}
