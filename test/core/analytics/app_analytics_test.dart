import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/analytics/app_analytics.dart';

class _FakeSink implements AppAnalyticsSink {
  final events = <({String name, Map<String, Object>? parameters})>[];
  String? userId;
  final properties = <String, String?>{};
  bool throwErrors = false;

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) async {
    if (throwErrors) throw StateError('test failure');
    events.add((name: name, parameters: parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (throwErrors) throw StateError('test failure');
    this.userId = userId;
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    if (throwErrors) throw StateError('test failure');
    properties[name] = value;
  }
}

void main() {
  tearDown(() => AppAnalytics.setSinkForTesting(null));

  test('emits exact required event names and parameters without PII', () async {
    final sink = _FakeSink();
    AppAnalytics.setSinkForTesting(sink);

    await AppAnalytics.login();
    await AppAnalytics.logout();
    await AppAnalytics.orderPlaced(
      paymentChoice: 'prepaid',
      itemCount: 3,
      valuePaise: 12500,
    );
    await AppAnalytics.paymentRecorded(amountPaise: 2500);

    expect(sink.events.map((event) => event.name), [
      'login',
      'logout',
      'order_placed',
      'payment_recorded',
    ]);
    expect(sink.events[0].parameters, isNull);
    expect(sink.events[1].parameters, isNull);
    expect(sink.events[2].parameters, {
      'payment_choice': 'prepaid',
      'item_count': 3,
      'value_paise': 12500,
    });
    expect(sink.events[3].parameters, {'amount_paise': 2500});

    final payload = sink.events.expand(
      (event) => event.parameters?.values ?? const <Object>[],
    );
    expect(payload, isNot(contains('Distinctive Customer')));
    expect(payload, isNot(contains('+919999999999')));
  });

  test('is a no-op without a sink and swallows sink failures', () async {
    AppAnalytics.setSinkForTesting(null);
    await expectLater(AppAnalytics.login(), completes);

    final sink = _FakeSink()..throwErrors = true;
    AppAnalytics.setSinkForTesting(sink);
    await expectLater(
      AppAnalytics.orderPlaced(
        paymentChoice: 'delivery',
        itemCount: 1,
        valuePaise: 100,
      ),
      completes,
    );
  });
}
