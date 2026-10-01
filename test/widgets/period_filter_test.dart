import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

/// Behaviour tests for [PeriodFilter] and [PeriodRange]. Dates are picked in
/// the previous calendar month (always selectable, whatever today is).
void main() {
  group('PeriodRange edges', () {
    PeriodRange span(int days) => PeriodRange(
      'custom',
      customFrom: DateTime(2026, 1, 1),
      customTo: DateTime(2026, 1, 1).add(Duration(days: days - 1)),
    );

    test('granularity switches at 31/32 and 90/91 day spans', () {
      // Up to a full month stays daily, so a custom range spanning a month
      // draws like the month presets.
      expect(span(14).granularity, 'day');
      expect(span(15).granularity, 'day');
      expect(span(31).granularity, 'day');
      expect(span(32).granularity, 'week');
      expect(span(90).granularity, 'week');
      expect(span(91).granularity, 'month');
    });

    test('presets: 7 days and both month presets are daily', () {
      expect(PeriodRange.last7.granularity, 'day');
      expect(PeriodRange.thisMonth.granularity, 'day');
      expect(PeriodRange.previousMonth.granularity, 'day');
    });

    test('month-to-date runs from the 1st to today', () {
      final now = DateTime(2026, 10, 17, 14, 30);
      expect(PeriodRange.thisMonth.from(now), DateTime(2026, 10, 1));
      expect(PeriodRange.thisMonth.to(now), now);
      expect(PeriodRange.thisMonth.label, PeriodRange.currentMonthLabel());
      expect(PeriodRange.thisMonth.labelFor(now), 'Oct 26');
      expect(PeriodRange.thisMonth.isDefault, isTrue);
      expect(PeriodRange.thisMonth.contains(DateTime(2026, 10, 1), now), isTrue);
      expect(
        PeriodRange.thisMonth.contains(DateTime(2026, 9, 30, 23, 59), now),
        isFalse,
      );
      // On the 1st the range is that single day, never empty or inverted.
      final first = DateTime(2026, 10, 1, 9);
      expect(PeriodRange.thisMonth.from(first), DateTime(2026, 10, 1));
      expect(PeriodRange.thisMonth.contains(DateTime(2026, 10, 1), first), isTrue);
    });

    test('previous month in January is December of the previous year', () {
      final now = DateTime(2027, 1, 15);
      expect(PeriodRange.previousMonthLabel(now), 'Dec 26');
      expect(PeriodRange.previousMonth.labelFor(now), 'Dec 26');
      expect(PeriodRange.previousMonth.from(now), DateTime(2026, 12, 1));
      expect(PeriodRange.previousMonth.to(now), DateTime(2026, 12, 31));
      // Current month label is unaffected.
      expect(PeriodRange.currentMonthLabel(now), 'Jan 27');
    });

    test('previous month ends on Feb 29 in a leap year and Feb 28 otherwise', () {
      final leap = DateTime(2028, 3, 10);
      expect(PeriodRange.previousMonthLabel(leap), 'Feb 28');
      expect(PeriodRange.previousMonth.from(leap), DateTime(2028, 2, 1));
      expect(PeriodRange.previousMonth.to(leap), DateTime(2028, 2, 29));

      final common = DateTime(2027, 3, 10);
      expect(PeriodRange.previousMonth.from(common), DateTime(2027, 2, 1));
      expect(PeriodRange.previousMonth.to(common), DateTime(2027, 2, 28));

      // Being in the leap February itself: previous month is January, and the
      // current month-to-date starts on the 1st.
      final inFeb = DateTime(2028, 2, 29);
      expect(PeriodRange.previousMonth.from(inFeb), DateTime(2028, 1, 1));
      expect(PeriodRange.previousMonth.to(inFeb), DateTime(2028, 1, 31));
      expect(PeriodRange.thisMonth.from(inFeb), DateTime(2028, 2, 1));
      expect(PeriodRange.thisMonth.to(inFeb), inFeb);
    });

    test('previous month contains its own days and nothing from this month', () {
      final now = DateTime(2026, 10, 5);
      final r = PeriodRange.previousMonth;
      expect(r.contains(DateTime(2026, 9, 1), now), isTrue);
      expect(r.contains(DateTime(2026, 9, 30, 23, 59, 59), now), isTrue);
      expect(r.contains(DateTime(2026, 8, 31, 23, 59), now), isFalse);
      expect(r.contains(DateTime(2026, 10, 1), now), isFalse);
    });

    test('custom range is capped at 366 days, both ends counted', () {
      expect(PeriodRange.maxCustomDays, 366);
      final from = DateTime(2027, 1, 1);
      // 2027-01-01 .. 2028-01-01 is exactly 366 days, the longest accepted.
      final ok = PeriodRange(
        'custom',
        customFrom: from,
        customTo: DateTime(2028, 1, 1),
      );
      expect(ok.customSpanDays, 366);
      expect(ok.customSpanDays <= PeriodRange.maxCustomDays, isTrue);
      final tooLong = PeriodRange(
        'custom',
        customFrom: from,
        customTo: DateTime(2028, 1, 2),
      );
      expect(tooLong.customSpanDays, 367);
      expect(tooLong.customSpanDays > PeriodRange.maxCustomDays, isTrue);
    });

    test('custom range: from/to return the picked dates, contains is '
        'day-inclusive at midnight edges', () {
      final r = PeriodRange(
        'custom',
        customFrom: DateTime(2026, 3, 10),
        customTo: DateTime(2026, 3, 12),
      );
      expect(r.from(), DateTime(2026, 3, 10));
      expect(r.to(), DateTime(2026, 3, 12));
      expect(r.contains(DateTime(2026, 3, 10)), isTrue);
      expect(r.contains(DateTime(2026, 3, 9, 23, 59, 59)), isFalse);
      expect(r.contains(DateTime(2026, 3, 12, 23, 59, 59)), isTrue);
      expect(r.contains(DateTime(2026, 3, 13)), isFalse);
    });

    test('presets with an injected midnight now', () {
      final now = DateTime(2026, 9, 30); // 00:00
      expect(PeriodRange.last7.contains(DateTime(2026, 9, 24), now), isTrue);
      expect(
        PeriodRange.last7.contains(DateTime(2026, 9, 23, 23, 59, 59), now),
        isFalse,
      );
      expect(PeriodRange.last7.contains(DateTime(2026, 9, 30), now), isTrue);
      expect(
        PeriodRange.last7.contains(DateTime(2026, 9, 30, 23, 59, 59), now),
        isTrue,
      );
      final lateNow = DateTime(2026, 9, 30, 23, 59, 59);
      expect(
        PeriodRange.last7.contains(DateTime(2026, 9, 24), lateNow),
        isTrue,
      );
      expect(
        PeriodRange.last7.contains(DateTime(2026, 10, 1), lateNow),
        isFalse,
      );
    });

    test(
      'requestKey differs by dates so a stale custom reply is detectable',
      () {
        final a = PeriodRange(
          'custom',
          customFrom: DateTime(2026, 3, 1),
          customTo: DateTime(2026, 3, 2),
        );
        final b = PeriodRange(
          'custom',
          customFrom: DateTime(2026, 3, 1),
          customTo: DateTime(2026, 3, 3),
        );
        expect(a.requestKey, isNot(b.requestKey));
        expect(a == b, isFalse);
      },
    );
  });

  group('PeriodFilter widget', () {
    final now = DateTime.now();
    DateTime prevMonth(int day) => DateTime(now.year, now.month - 1, day);

    late ValueNotifier<PeriodRange> value;
    late List<PeriodRange> emitted;

    setUp(() {
      value = ValueNotifier(PeriodRange.last7);
      emitted = [];
    });
    tearDown(() => value.dispose());

    Widget host({ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<PeriodRange>(
            valueListenable: value,
            builder: (_, v, _) =>
                PeriodFilter(value: v, onChanged: emitted.add),
          ),
        ),
      ),
    );

    Future<void> openCustom(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pump();
    }

    /// Opens the FROM/TO picker, optionally steps back one month, taps [day].
    Future<void> pickDay(
      WidgetTester tester, {
      required bool from,
      required int day,
      bool stepBack = false,
    }) async {
      await tester.tap(find.text(from ? 'FROM' : 'TO'));
      await tester.pumpAndSettle();
      if (stepBack) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('$day')),
      );
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('picking FROM only does not call onChanged', (tester) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: true, day: 10, stepBack: true);

      expect(emitted, isEmpty);
      expect(
        find.text(DateFormatter.formatShort(prevMonth(10))),
        findsOneWidget,
      );
      expect(find.text('Pick date'), findsOneWidget);
    });

    testWidgets('picking TO after FROM emits once with key custom and the '
        'picked dates', (tester) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: true, day: 10, stepBack: true);
      await pickDay(tester, from: false, day: 20); // opens on FROM's month

      expect(emitted, hasLength(1));
      expect(emitted.single.key, 'custom');
      expect(emitted.single.customFrom, prevMonth(10));
      expect(emitted.single.customTo, prevMonth(20));
    });

    testWidgets('TO earlier than FROM clamps FROM to TO', (tester) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: true, day: 20, stepBack: true);
      await pickDay(tester, from: false, day: 10);

      expect(emitted, hasLength(1));
      expect(emitted.single.customFrom, prevMonth(10));
      expect(emitted.single.customTo, prevMonth(10));
    });

    testWidgets('FROM later than TO clamps TO to FROM', (tester) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: false, day: 10, stepBack: true);
      expect(emitted, isEmpty);
      // FROM's picker opens on today's month (nothing picked there yet).
      await pickDay(tester, from: true, day: 20, stepBack: true);

      expect(emitted, hasLength(1));
      expect(emitted.single.customFrom, prevMonth(20));
      expect(emitted.single.customTo, prevMonth(20));
    });

    testWidgets('a preset picked after a half-finished custom clears it', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: true, day: 10, stepBack: true);
      await tester.tap(find.text(PeriodRange.previousMonthLabel()));
      await tester.pump();

      expect(emitted.single, PeriodRange.previousMonth);
      expect(find.text('FROM'), findsNothing);
    });

    testWidgets('rebuilding with a preset closes the custom row and clears '
        'the picked dates', (tester) async {
      await tester.pumpWidget(host());
      await openCustom(tester);
      await pickDay(tester, from: true, day: 10, stepBack: true);
      expect(find.text('FROM'), findsOneWidget);

      value.value = PeriodRange.thisMonth;
      await tester.pump();
      expect(find.text('FROM'), findsNothing);

      // Reopening shows empty cells, not the old FROM.
      await openCustom(tester);
      expect(find.text('Pick date'), findsNWidgets(2));
    });

    testWidgets('rebuilding with a custom value keeps the row open', (
      tester,
    ) async {
      final a = PeriodRange(
        'custom',
        customFrom: prevMonth(5),
        customTo: prevMonth(6),
      );
      value.value = a;
      await tester.pumpWidget(host());
      expect(find.text('FROM'), findsOneWidget);
      expect(find.text('Pick date'), findsNothing);

      value.value = PeriodRange(
        'custom',
        customFrom: prevMonth(7),
        customTo: prevMonth(8),
      );
      await tester.pump();
      expect(find.text('FROM'), findsOneWidget);
      expect(find.text('TO'), findsOneWidget);
    });

    testWidgets('chips and the calendar toggle are at least 44 high and '
        'expose selected button semantics', (tester) async {
      await tester.pumpWidget(host());
      for (final label in [
        '7 days',
        PeriodRange.currentMonthLabel(),
        PeriodRange.previousMonthLabel(),
      ]) {
        final box = find.ancestor(
          of: find.text(label),
          matching: find.byType(ConstrainedBox),
        );
        final h = tester.getSize(box.first).height;
        expect(h, greaterThanOrEqualTo(44), reason: label);
      }
      final toggle = tester.getSize(find.byTooltip('Custom range'));
      expect(toggle.height, greaterThanOrEqualTo(44));

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('7 days')),
        matchesSemantics(
          label: '7 days',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
          hasSelectedState: true,
          hasEnabledState: false,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('no overflow at 320pt, 2x text, custom row open '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        value.value = PeriodRange(
          'custom',
          customFrom: DateTime(2026, 1, 1),
          customTo: DateTime(2026, 12, 31),
        );
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: host(theme: dark ? ThemeData.dark() : ThemeData.light()),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('366-day limit', () {
    test('spanDays is calendar-inclusive; customSpanDays uses it', () {
      final from = DateTime(2026, 1, 1);
      expect(PeriodRange.spanDays(from, from), 1);
      expect(PeriodRange.spanDays(from, DateTime(2026, 12, 31)), 365);
      expect(PeriodRange.spanDays(from, DateTime(2027, 1, 1)), 366);
      expect(PeriodRange.spanDays(from, DateTime(2027, 1, 2)), 367);
      expect(
        PeriodRange(
          'custom',
          customFrom: from,
          customTo: DateTime(2027, 1, 1),
        ).customSpanDays,
        PeriodRange.maxCustomDays,
      );
    });

    final now = DateTime.now();
    DateTime daysAgo(int n) => DateTime(now.year, now.month, now.day - n);

    late List<PeriodRange> emitted;
    setUp(() => emitted = []);

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeriodFilter(value: PeriodRange.last7, onChanged: emitted.add),
        ),
      ),
    );

    /// TO = today (the picker opens on it), then FROM = [fromAgo] days ago,
    /// reached by stepping the calendar back month by month.
    Future<void> pickTodayThenFrom(WidgetTester tester, int fromAgo) async {
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pump();
      await tester.tap(find.text('TO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);

      final target = daysAgo(fromAgo);
      final months = (now.year - target.year) * 12 + now.month - target.month;
      await tester.tap(find.text('FROM'));
      await tester.pumpAndSettle();
      for (var i = 0; i < months; i++) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('${target.day}'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('the hint is shown under the open From/To row only', (
      tester,
    ) async {
      await pump(tester);
      const hint = ValueKey('period-filter-limit-hint');
      expect(find.byKey(hint), findsNothing);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pump();
      expect(find.byKey(hint), findsOneWidget);
      expect(find.text('Ranges are limited to 1 year'), findsOneWidget);
    });

    testWidgets('a 366-day span is accepted as picked', (tester) async {
      await pump(tester);
      await pickTodayThenFrom(tester, 365);
      expect(emitted, hasLength(1));
      expect(emitted.single.customFrom, daysAgo(365));
      expect(emitted.single.customTo, daysAgo(0));
      expect(emitted.single.customSpanDays, 366);
    });

    testWidgets('a 367-day span keeps the picked FROM and pulls TO in to '
        '366 days', (tester) async {
      await pump(tester);
      await pickTodayThenFrom(tester, 366);
      expect(emitted, hasLength(1));
      expect(emitted.single.customFrom, daysAgo(366));
      expect(emitted.single.customTo, daysAgo(1));
      expect(emitted.single.customSpanDays, 366);
    });

    testWidgets('picking TO last after an older FROM keeps TO and pulls FROM '
        'in to 366 days', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pump();

      Future<void> pickIn(
        String caption,
        DateTime target,
        DateTime opensOn,
      ) async {
        await tester.tap(find.text(caption));
        await tester.pumpAndSettle();
        final diff =
            (target.year - opensOn.year) * 12 + target.month - opensOn.month;
        for (var i = 0; i < diff.abs(); i++) {
          await tester.tap(
            find.byTooltip(diff < 0 ? 'Previous month' : 'Next month'),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('${target.day}'),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      // FROM 400 days ago (its picker opens on today's month).
      await pickIn('FROM', daysAgo(400), now);
      expect(emitted, isEmpty);
      // TO's picker opens no earlier than 366 days ago; pick today.
      await pickIn('TO', daysAgo(0), daysAgo(366));

      expect(emitted, hasLength(1));
      expect(emitted.single.customTo, daysAgo(0));
      expect(emitted.single.customFrom, daysAgo(365));
      expect(emitted.single.customSpanDays, 366);
    });
  });
}
