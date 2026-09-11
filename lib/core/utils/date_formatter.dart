import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static final DateFormat _dayMonth = DateFormat('d MMM', 'en_US');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy', 'en_US');
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');

  /// Parses an ISO calendar date string (e.g. "2026-09-13" or "2026-09-13T00:00:00.000Z")
  /// strictly as an IST calendar date without applying local device timezone shifts.
  static DateTime? parseCalendarDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final trimmed = raw.trim();
      if (trimmed.length >= 10) {
        final year = int.parse(trimmed.substring(0, 4));
        final month = int.parse(trimmed.substring(5, 7));
        final day = int.parse(trimmed.substring(8, 10));
        return DateTime(year, month, day);
      }
      return DateTime.tryParse(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// Formats to "d MMM" (e.g. "13 Sep")
  static String formatShort(dynamic date) {
    final dt = date is DateTime ? date : parseCalendarDate(date?.toString());
    if (dt == null) return '';
    return _dayMonth.format(dt);
  }

  static String formatDate(dynamic date) => formatShort(date);

  /// Formats to "d MMM yyyy" (e.g. "13 Sep 2026")
  static String formatFull(dynamic date) {
    final dt = date is DateTime ? date : parseCalendarDate(date?.toString());
    if (dt == null) return '';
    return _dayMonthYear.format(dt);
  }

  static String formatFullDate(dynamic date) => formatFull(date);

  static final DateFormat _dateTime = DateFormat('d MMM, h:mm a', 'en_US');

  /// Formats to "d MMM, h:mm a" (e.g. "13 Sep, 10:40 am")
  static String formatDateTime(dynamic date) {
    final dt = date is DateTime ? date : parseCalendarDate(date?.toString());
    if (dt == null) return '';
    return _dateTime.format(dt);
  }

  /// Converts a DateTime into "YYYY-MM-DD" wire format for the backend API
  static String toIsoDateString(DateTime date) {
    return _isoDate.format(date);
  }

  /// Returns today's calendar date string in YYYY-MM-DD
  static String todayIsoDateString() {
    return _isoDate.format(DateTime.now());
  }
}
