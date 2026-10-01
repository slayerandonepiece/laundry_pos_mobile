import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/date_formatter.dart';

/// A day-range selection: a preset or a custom from/to pair.
class PeriodRange {
  /// `7d`, `this_month`, `prev_month`, `custom` (or legacy `30d`, `90d`).
  final String key;
  final DateTime? customFrom;
  final DateTime? customTo;

  const PeriodRange(this.key, {this.customFrom, this.customTo});

  static const last7 = PeriodRange('7d');
  static const thisMonth = PeriodRange('this_month');
  static const previousMonth = PeriodRange('prev_month');

  // Preserved for backward compatibility in existing code / mocks
  static const last30 = PeriodRange('30d');
  static const last90 = PeriodRange('90d');

  bool get isCustom => key == 'custom';

  /// The longest custom range the server accepts, in days (inclusive).
  static const int maxCustomDays = 366;

  /// Days from [a] to [b] counting both ends; calendar days, so a daylight
  /// saving change in between cannot shave a day off.
  static int spanDays(DateTime a, DateTime b) =>
      DateTime.utc(
        b.year,
        b.month,
        b.day,
      ).difference(DateTime.utc(a.year, a.month, a.day)).inDays +
      1;

  /// Length of a custom range, both ends included.
  int get customSpanDays => spanDays(customFrom!, customTo!);

  /// The card's default period — the current month (month-to-date).
  bool get isDefault => key == 'this_month';

  static const List<String> monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Formats [d] as 3-letter month + 2-digit year (e.g. "Oct 26").
  static String formatMonthLabel(DateTime d) {
    final m = monthNames[d.month - 1];
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$m $yy';
  }

  /// Preset label for the current month (e.g. "Oct 26").
  static String currentMonthLabel([DateTime? now]) {
    return formatMonthLabel(now ?? DateTime.now());
  }

  /// Preset label for the previous month (e.g. "Sep 26").
  /// In January, correctly steps back to December of the previous year.
  static String previousMonthLabel([DateTime? now]) {
    final ref = now ?? DateTime.now();
    return formatMonthLabel(DateTime(ref.year, ref.month - 1, 1));
  }

  int get days => switch (key) {
    '7d' => 7,
    '90d' => 90,
    _ => 30,
  };

  /// Inclusive first day, relative to [now] for presets.
  DateTime from([DateTime? now]) {
    if (isCustom) return customFrom!;
    final ref = now ?? DateTime.now();
    return switch (key) {
      '7d' => ref.subtract(const Duration(days: 6)),
      'this_month' => DateTime(ref.year, ref.month, 1),
      'prev_month' => DateTime(ref.year, ref.month - 1, 1),
      '90d' => ref.subtract(const Duration(days: 89)),
      _ => ref.subtract(const Duration(days: 29)),
    };
  }

  /// Inclusive last day, relative to [now] for presets.
  DateTime to([DateTime? now]) {
    if (isCustom) return customTo!;
    final ref = now ?? DateTime.now();
    return switch (key) {
      'prev_month' => DateTime(ref.year, ref.month, 0),
      _ => ref,
    };
  }

  /// Bucket size that keeps a chart to a readable number of points.
  /// Daily for 7 days / a month (span <= 31); weekly up to 90 days; monthly beyond.
  static String granularityForSpan(int span) {
    if (span <= 31) return 'day';
    if (span <= 90) return 'week';
    return 'month';
  }

  String get granularity {
    if (isCustom) {
      final span = customSpanDays;
      return granularityForSpan(span);
    }
    return switch (key) {
      '7d' || 'this_month' || 'prev_month' => 'day',
      '90d' => 'month',
      '30d' => 'week',
      _ => 'day',
    };
  }

  String labelFor([DateTime? now]) {
    final ref = now ?? DateTime.now();
    return switch (key) {
      '7d' => 'Last 7 days',
      'this_month' => currentMonthLabel(ref),
      'prev_month' => previousMonthLabel(ref),
      'custom' => 'Selected dates',
      '90d' => 'Last 90 days',
      _ => 'Last 30 days',
    };
  }

  String get label => labelFor();

  /// Identifies the selection; compared to tell a stale reply from a current
  /// one.
  String get requestKey => '$key|$customFrom|$customTo';

  /// True when [d] falls in the range, day-inclusive.
  bool contains(DateTime d, [DateTime? now]) {
    final start = from(now);
    final end = to(now);
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(DateTime(end.year, end.month, end.day));
  }

  String get fromIso => DateFormatter.toIsoDateString(from());
  String get toIso => DateFormatter.toIsoDateString(to());

  @override
  bool operator ==(Object other) =>
      other is PeriodRange && other.requestKey == requestKey;

  @override
  int get hashCode => requestKey.hashCode;
}

/// Preset chips (7 days, current month, previous month) plus a custom-range picker.
/// The owner holds the [PeriodRange] and reacts to [onChanged]. Custom only emits
/// once both dates are picked; until then the calendar button shows selected and the
/// from/to row is open.
class PeriodFilter extends StatefulWidget {
  final PeriodRange value;
  final ValueChanged<PeriodRange> onChanged;
  final DateTime? now;

  const PeriodFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.now,
  });

  @override
  State<PeriodFilter> createState() => _PeriodFilterState();
}

class _PeriodFilterState extends State<PeriodFilter> {
  static const double _minTapTarget = 44;

  bool _customOpen = false;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _customOpen = widget.value.isCustom;
    _from = widget.value.customFrom;
    _to = widget.value.customTo;
  }

  @override
  void didUpdateWidget(covariant PeriodFilter old) {
    super.didUpdateWidget(old);
    // The owner reset the selection (e.g. an outlet switch).
    if (!widget.value.isCustom && old.value != widget.value) {
      _customOpen = false;
      _from = null;
      _to = null;
    }
  }

  Future<void> _pick({required bool isFrom}) async {
    final now = widget.now ?? DateTime.now();
    final otherPicked = isFrom ? _to != null : _from != null;
    // With one end chosen, nothing older than the longest range is offered.
    final firstDate = otherPicked
        ? DateTime(now.year, now.month, now.day - PeriodRange.maxCustomDays)
        : DateTime(2020);
    final wanted = isFrom ? (_from ?? now) : (_to ?? _from ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: wanted.isBefore(firstDate)
          ? firstDate
          : (wanted.isAfter(now) ? now : wanted),
      firstDate: firstDate,
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme
              .copyWith(primary: AppColors.primary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) {
          _to = picked;
        } else if (_to != null &&
            PeriodRange.spanDays(picked, _to!) > PeriodRange.maxCustomDays) {
          // Keep what was just picked; pull the other end in.
          final newTo = DateTime(
            picked.year,
            picked.month,
            picked.day + PeriodRange.maxCustomDays - 1,
          );
          _to = newTo.isAfter(now) ? now : newTo;
        }
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(picked)) {
          _from = picked;
        } else if (_from != null &&
            PeriodRange.spanDays(_from!, picked) > PeriodRange.maxCustomDays) {
          _from = DateTime(
            picked.year,
            picked.month,
            picked.day - (PeriodRange.maxCustomDays - 1),
          );
        }
      }
    });
    if (_from != null && _to != null) {
      widget.onChanged(PeriodRange('custom', customFrom: _from, customTo: _to));
    }
  }

  void _preset(PeriodRange r) {
    setState(() {
      _customOpen = false;
      _from = null;
      _to = null;
    });
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final now = widget.now ?? DateTime.now();
    final currentMonthLabel = PeriodRange.currentMonthLabel(now);
    final prevMonthLabel = PeriodRange.previousMonthLabel(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chip('7 days', v.key == '7d', () => _preset(PeriodRange.last7)),
              const SizedBox(width: 6),
              _chip(
                currentMonthLabel,
                v.key == PeriodRange.thisMonth.key,
                () => _preset(PeriodRange.thisMonth),
              ),
              const SizedBox(width: 6),
              _chip(
                prevMonthLabel,
                v.key == PeriodRange.previousMonth.key,
                () => _preset(PeriodRange.previousMonth),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Custom range',
                child: Semantics(
                  button: true,
                  selected: _customOpen,
                  onTap: () => setState(() => _customOpen = true),
                  label: 'Custom range',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _customOpen = true),
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _minTapTarget,
                        minWidth: _minTapTarget,
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _customOpen
                                ? AppColors.primary
                                : AppColors.selectedSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _customOpen
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: _customOpen
                                ? Colors.white
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_customOpen) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.selectedSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _dateCell('FROM', _from, true)),
                Container(width: 1, height: 26, color: AppColors.border),
                const SizedBox(width: 14),
                Expanded(child: _dateCell('TO', _to, false)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Ranges are limited to 1 year',
              key: ValueKey('period-filter-limit-hint'),
              style: TextStyle(
                fontFamily: AppTextStyles.fontBody,
                fontSize: 11,
                color: AppColors.mutedText,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateCell(String caption, DateTime? value, bool isFrom) {
    return InkWell(
      onTap: () => _pick(isFrom: isFrom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minTapTarget),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppColors.mutedText,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.mutedText,
                    ),
                  ),
                  Text(
                    value != null
                        ? DateFormatter.formatShort(value)
                        : 'Pick date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontBody,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.selectedSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontBody,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
