import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/owner/bloc/owner_bloc.dart';
import 'package:myshop/features/owner/bloc/owner_event.dart';
import 'package:myshop/features/owner/data/models/dashboard_model.dart';
import 'package:myshop/features/owner/data/owner_repository.dart';
import 'package:myshop/shared/widgets/period_filter.dart';

class _PeriodRepo implements OwnerRepository {
  final List<({String from, String to, String granularity})> requests = [];
  Object? toThrow;
  Completer<DashboardMetrics>? hold;
  DashboardMetrics reply = DashboardMetrics(
    bars: [DashboardBar(label: '1 Jul', amount: 1200)],
  );

  @override
  Future<DashboardMetrics> getPeriodMetrics({
    required String from,
    required String to,
    required String granularity,
  }) {
    requests.add((from: from, to: to, granularity: granularity));
    if (toThrow != null) return Future.error(toThrow!);
    final pending = hold;
    if (pending != null) {
      hold = null;
      return pending.future;
    }
    return Future.value(reply);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  late _PeriodRepo repo;
  late OwnerBloc bloc;

  setUp(() {
    repo = _PeriodRepo();
    bloc = OwnerBloc(ownerRepository: repo);
  });

  tearDown(() => bloc.close());

  PeriodRange custom(DateTime from, DateTime to) =>
      PeriodRange('custom', customFrom: from, customTo: to);

  test(
    'a past range compares with the same number of days just before it',
    () async {
      // 10 days: 10-19 Aug, so the comparison is 31 Jul - 9 Aug.
      final range = custom(DateTime(2026, 8, 10), DateTime(2026, 8, 19));
      bloc.add(LoadPreviousPeriodEvent(range: range, requestKey: 'k1'));

      final state = await bloc.stream.firstWhere(
        (s) => s.previousBars.isNotEmpty,
      );

      expect(repo.requests.single.from, '2026-07-31');
      expect(repo.requests.single.to, '2026-08-09');
      expect(repo.requests.single.granularity, range.granularity);
      expect(state.previousKey, 'k1');
      expect(state.previousBars.single.amount, 1200);
    },
  );

  test(
    'a range that runs into the future is measured up to today only',
    () async {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day - 2);
      // Ends well after today; only the 3 days up to and including today count.
      final to = DateTime(today.year, today.month, today.day + 10);
      bloc.add(
        LoadPreviousPeriodEvent(range: custom(from, to), requestKey: 'k1'),
      );

      await bloc.stream.firstWhere((s) => s.previousBars.isNotEmpty);

      expect(
        repo.requests.single.from,
        _iso(DateTime(from.year, from.month, from.day - 3)),
      );
      expect(
        repo.requests.single.to,
        _iso(DateTime(from.year, from.month, from.day - 1)),
      );
    },
  );

  test(
    'a failed comparison request leaves the page untouched and sets no error',
    () async {
      repo.toThrow = Exception('offline');
      bloc.add(
        LoadPreviousPeriodEvent(
          range: custom(DateTime(2026, 8, 10), DateTime(2026, 8, 19)),
          requestKey: 'k1',
        ),
      );

      await pumpEventQueue();

      expect(bloc.state.previousBars, isEmpty);
      expect(bloc.state.error, isNull);
      expect(repo.requests, hasLength(1));
    },
  );

  test('a late reply for an earlier selection is dropped', () async {
    final slow = Completer<DashboardMetrics>();
    repo.hold = slow;
    final first = custom(DateTime(2026, 8, 10), DateTime(2026, 8, 19));
    final second = custom(DateTime(2026, 7, 1), DateTime(2026, 7, 5));

    bloc.add(LoadPreviousPeriodEvent(range: first, requestKey: 'first'));
    await pumpEventQueue();
    repo.reply = DashboardMetrics(
      bars: [DashboardBar(label: '27 Jun', amount: 777)],
    );
    bloc.add(LoadPreviousPeriodEvent(range: second, requestKey: 'second'));
    await bloc.stream.firstWhere((s) => s.previousBars.isNotEmpty);

    slow.complete(
      DashboardMetrics(bars: [DashboardBar(label: '1 Jul', amount: 1)]),
    );
    await pumpEventQueue();

    expect(bloc.state.previousKey, 'second');
    expect(bloc.state.previousBars.single.amount, 777);
  });
}
