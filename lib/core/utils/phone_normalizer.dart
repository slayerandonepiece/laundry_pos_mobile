/// Normalises a pasted/typed Indian mobile number to its 10 local digits:
/// strips non-digits, then drops a leading `91` country code (12 digits) or
/// a trunk `0` (11 digits). Anything else is returned as bare digits —
/// never truncated — so the caller's 10-digit validation still rejects it.
String tenDigitPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return digits.substring(2);
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return digits.substring(1);
  }
  return digits;
}
