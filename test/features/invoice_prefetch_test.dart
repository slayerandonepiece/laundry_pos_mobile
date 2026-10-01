import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:myshop/core/network/api_client.dart';
import 'package:myshop/core/network/api_exceptions.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/utils/currency_formatter.dart';
import 'package:myshop/core/sync/connectivity_service.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:myshop/features/orders/presentation/invoice_viewer_screen.dart';

class _Offline extends ConnectivityService {
  _Offline(this.offline) : super.internal();
  bool offline;
  @override
  bool get isOffline => offline;
  @override
  Future<bool> checkIsOffline() async => offline;
}

class _InvoiceApi implements ApiClient {
  final List<String> asked = [];
  int inFlight = 0;
  int peakInFlight = 0;

  /// Codes the server answers with a 4xx, and one that answers 401.
  final Set<String> refused = {};
  String? unauthorized;

  /// Runs when a request arrives (used to simulate signing out mid-run).
  void Function(String code)? onAsk;

  @override
  Future<dynamic> get(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final code = RegExp(r'orders/([^/]+)/invoice').firstMatch(url)!.group(1)!;
    asked.add(code);
    onAsk?.call(code);
    inFlight++;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    inFlight--;
    if (code == unauthorized) {
      throw AuthException(code: 'UNAUTHENTICATED', statusCode: 401);
    }
    if (refused.contains(code)) {
      throw ApiException('Bad request', statusCode: 400);
    }
    return {
      'exists': true,
      'invoiceSeq': int.parse(code.split('-').last),
      'accessToken': 'tok-$code',
      'generatedAt': '2026-09-30T10:00:00.000Z',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _deliveredPaid(int n) => {
  'id': 'EL-$n',
  'name': 'Customer $n',
  'phone': '9876543210',
  'date': '2026-09-20',
  'due': '2026-09-21',
  'status': 'Delivered',
  'lines': [
    {
      'productId': 'p1',
      'name': 'Wash',
      'quantity': 1,
      'unit': 'PIECE',
      'amount': 5000,
    },
  ],
  'payments': [
    {'id': 'pay-$n', 'amount': 5000, 'date': '2026-09-21', 'method': 'CASH'},
  ],
};

void main() {
  late Directory tempDir;
  late LocalCacheService cache;
  late _InvoiceApi api;
  late OrdersRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_invoice_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalCacheService.boxName);
    cache = LocalCacheService();
    await cache.setActiveStoreId('store-1');
    await cache.setActiveOutletId('outlet-a');
    ConnectivityService.instance = _Offline(false);
    api = _InvoiceApi();
    repo = OrdersRepository(apiClient: api, localCache: cache);
  });

  tearDown(() async {
    ConnectivityService.instance = ConnectivityService.internal();
    await Hive.box(LocalCacheService.boxName).close();
    await Hive.deleteBoxFromDisk(LocalCacheService.boxName);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seed(int count) => cache.setCachedOrders([
    for (var i = 1; i <= count; i++) _deliveredPaid(i),
  ]);

  testWidgets('invoice Paid uses the updated order after final payment', (
    tester,
  ) async {
    final updated = (await tester.runAsync(() async {
      await cache.setCachedOrders([
        {
          'id': 'EL-230',
          'name': 'Customer',
          'phone': '9876543210',
          'date': '2026-09-30',
          'due': '2026-10-01',
          'status': 'Delivered',
          'lines': [
            {
              'productId': 'p1',
              'name': 'Wash',
              'quantity': 1,
              'unit': 'PIECE',
              'amount': 23000,
            },
          ],
          'payments': [
            {
              'id': 'first',
              'amount': 10000,
              'date': '2026-09-30',
              'method': 'Cash',
            },
          ],
        },
      ]);
      return repo.recordPayment('EL-230', 13000, 'Cash');
    }))!;
    expect(updated.paidAmount, 23000);
    expect(updated.isPaidInFull, isTrue);
    expect(repo.getCachedOrdersList().single.paidAmount, 23000);
    await tester.pumpWidget(
      MaterialApp(home: InvoiceViewerScreen(order: updated)),
    );
    expect(find.text('Paid in full'), findsOneWidget);
    expect(find.text(CurrencyFormatter.formatPdf(23000)), findsAtLeastNWidgets(2));
    expect(find.text(CurrencyFormatter.formatPdf(10000)), findsNothing);
  });

  test('fetches in small parallel batches and keeps every invoice', () async {
    await seed(10);

    await repo.retryMissingInvoices();

    expect(api.asked.length, 10);
    expect(api.peakInFlight, greaterThan(1));
    expect(api.peakInFlight, lessThanOrEqualTo(4));
    // No reply overwrote another: all ten orders now carry their invoice.
    final orders = cache.getCachedOrders()!;
    expect(orders.every((o) => o['invoice'] != null), isTrue);
  });

  test('an order is asked about once, however many syncs follow', () async {
    await seed(3);

    await repo.retryMissingInvoices();
    await repo.retryMissingInvoices();
    // Another scope's copy of the same orders, still without invoices.
    await seed(3);
    await repo.retryMissingInvoices();

    expect(api.asked.length, 3);
  });

  test(
    'a refused order (4xx) is not asked again; the rest still complete',
    () async {
      await seed(3);
      api.refused.add('EL-2');

      await repo.retryMissingInvoices();
      await repo.retryMissingInvoices();

      expect(api.asked.where((c) => c == 'EL-2').length, 1);
      final orders = cache.getCachedOrders()!;
      expect(orders.where((o) => o['invoice'] != null).length, 2);
    },
  );

  test(
    'stops as soon as the session is gone (401) — no further batches',
    () async {
      await seed(12);
      api.unauthorized = 'EL-1';

      await repo.retryMissingInvoices();

      // The first batch of 4 went out; nothing after it.
      expect(api.asked.length, 4);
    },
  );

  test('stops when the user signs out mid-run', () async {
    await seed(12);
    api.onAsk = (code) {
      if (code == 'EL-1') cache.clearActiveStoreId();
    };

    await repo.retryMissingInvoices();

    expect(api.asked.length, 4);
  });

  test('does nothing while offline', () async {
    await seed(5);
    ConnectivityService.instance = _Offline(true);

    await repo.retryMissingInvoices();

    expect(api.asked, isEmpty);
  });
}
