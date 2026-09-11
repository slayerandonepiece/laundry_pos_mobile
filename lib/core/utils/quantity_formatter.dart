class QuantityFormatter {
  QuantityFormatter._();

  /// Formats a weight or quantity number up to [maxDecimals] places (default 3),
  /// stripping unnecessary trailing zeros and decimal points.
  ///
  /// Examples:
  /// - 2.0 -> "2"
  /// - 2.5 -> "2.5"
  /// - 2.75 -> "2.75"
  /// - 2.755 -> "2.755"
  static String format(num quantity, {int maxDecimals = 3}) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    final s = quantity.toStringAsFixed(maxDecimals);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Formats a weight quantity with the 'kg' suffix.
  ///
  /// Examples:
  /// - 2.0 -> "2 kg"
  /// - 2.755 -> "2.755 kg"
  static String formatWeight(num quantity, {int maxDecimals = 3}) {
    return '${format(quantity, maxDecimals: maxDecimals)} kg';
  }
}
