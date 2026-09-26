import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';

Order _order({String id = '', String? offlineId}) => Order(
  id: id,
  offlineId: offlineId,
  name: '',
  phone: '9000000000',
  date: '2026-09-26',
  due: '2026-09-28',
  status: 'Pending',
  lines: [],
  payments: [],
);

void main() {
  group('Order two ids', () {
    test('orderCode and displayCode for synced and unsynced orders', () {
      final unsynced = _order(
        offlineId: '3f2a9c1e-0000-4000-8000-00000abc12de',
      );
      expect(unsynced.orderCode, '3f2a9c1e-0000-4000-8000-00000abc12de');
      expect(unsynced.displayCode, 'OFF-BC12DE');

      final synced = _order(id: 'EL-7', offlineId: 'u1');
      expect(synced.orderCode, 'EL-7');
      expect(synced.displayCode, 'EL-7');
    });

    test('fromJson treats an empty offlineId as none and round-trips', () {
      expect(Order.fromJson({'id': 'EL-1', 'offlineId': ''}).offlineId, isNull);
      final o = Order.fromJson({'id': '', 'offlineId': 'u2'});
      expect(Order.fromJson(o.toJson()).offlineId, 'u2');
      expect(o.copyWith(id: 'EL-2').offlineId, 'u2');
    });

    test('isSameOrder: ids when both synced, else offlineId', () {
      expect(_order(id: 'EL-1').isSameOrder(_order(id: 'EL-1')), isTrue);
      expect(_order(id: 'EL-1').isSameOrder(_order(id: 'EL-2')), isFalse);
      expect(
        _order(offlineId: 'u1')
            .isSameOrder(_order(id: 'EL-1', offlineId: 'u1')),
        isTrue,
      );
      // Two unsynced orders never match just because both ids are empty.
      expect(
        _order(offlineId: 'u1').isSameOrder(_order(offlineId: 'u2')),
        isFalse,
      );
    });

    test('mergeServerJson keeps a phone-only offlineId', () {
      expect(
        Order.mergeServerJson(
          {'id': 'EL-1', 'offlineId': 'u1'},
          {'id': 'EL-1'},
        ),
        {'id': 'EL-1', 'offlineId': 'u1'},
      );
      expect(
        Order.mergeServerJson({'id': ''}, {'id': 'EL-1', 'offlineId': 'u2'}),
        {'id': 'EL-1', 'offlineId': 'u2'},
      );
    });
  });
}
