import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/owner/presentation/customer_messages_screen.dart';

class _Orders implements OrdersRepository {
  _Orders({this.cached, this.fresh});
  final List<Map<String, dynamic>>? cached;
  final List<Map<String, dynamic>>? fresh;

  @override
  List<Map<String, dynamic>>? getCachedMessageTemplates() => cached;

  @override
  Future<List<Map<String, dynamic>>> syncMessageTemplates() async {
    if (fresh == null) throw Exception('offline');
    return fresh!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _row(String label, bool on, String attachment) => {
  'statusKey': label.toUpperCase(),
  'label': label,
  'enabled': on,
  'attachment': attachment,
  'body': 'Hi {customer}, order {orderNo} is $label. {link}',
};

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('customer_messages');
    Hive.init(dir.path);
    await Hive.openBox(LocalCacheService.boxName);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app(OrdersRepository repo) =>
      RepositoryProvider<OrdersRepository>.value(
        value: repo,
        child: const MaterialApp(home: CustomerMessagesScreen()),
      );

  testWidgets('shows each status with on/off and attachment', (tester) async {
    await tester.pumpWidget(
      app(
        _Orders(
          fresh: [
            _row('Placed', false, 'NONE'),
            _row('Ready', true, 'INVOICE_PDF'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Placed'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Invoice PDF attached'), findsOneWidget);
    expect(find.text('No attachment'), findsOneWidget);
  });

  testWidgets('offline, keeps the saved copy and says so', (tester) async {
    await tester.pumpWidget(
      app(_Orders(cached: [_row('Ready', true, 'NONE')])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.text("Showing what's saved on this phone. Couldn't refresh."),
      findsOneWidget,
    );
  });

  testWidgets('offline with nothing saved offers a retry', (tester) async {
    await tester.pumpWidget(app(_Orders()));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your messages"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
