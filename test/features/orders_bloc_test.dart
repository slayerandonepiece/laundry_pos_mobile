import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';

class MockOrdersRepository implements OrdersRepository {
  Order? updatedOrder;
  String? recordedOrderCode;
  int? recordedAmount;
  String? recordedMethod;

  @override
  Future<Order> recordPayment(
    String orderCode,
    int amount,
    String method,
  ) async {
    recordedOrderCode = orderCode;
    recordedAmount = amount;
    recordedMethod = method;
    return Order(
      id: orderCode,
      name: 'Ramesh Kumar',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Pending', // Does not change status
      lines: [],
      payments: [
        OrderPayment(
          id: 'pay-new',
          amount: amount,
          date: '2026-09-10',
          method: method,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OrdersBloc & Filter Logic Tests', () {
    late OrdersBloc ordersBloc;
    late MockOrdersRepository mockRepo;

    final order1 = Order(
      id: 'EL-101',
      name: 'Ramesh Kumar',
      phone: '9876543210',
      date: '2026-09-10',
      due: '2026-09-12',
      status: 'Pending',
      lines: [
        OrderLine(
          productId: 'p1',
          name: 'Shirt',
          quantity: 2,
          unit: 'PIECE',
          amount: 100,
        ),
      ],
      payments: [], // balanceDue = 100
    );

    final order2 = Order(
      id: 'EL-102',
      name: 'Priya Sharma',
      phone: '9123456780',
      date: '2026-09-09',
      due: '2026-09-11',
      status: 'Ready',
      lines: [
        OrderLine(
          productId: 'p2',
          name: 'Saree',
          quantity: 1,
          unit: 'PIECE',
          amount: 250,
        ),
      ],
      payments: [
        OrderPayment(
          id: 'pay-1',
          amount: 250,
          date: '2026-09-09',
          method: 'UPI',
        ),
      ], // balanceDue = 0, isPaidInFull = true
    );

    final order3 = Order(
      id: 'EL-103',
      name: 'Anand Patel',
      phone: '9988776655',
      date: '2026-09-08',
      due: '2026-09-10',
      status: 'Delivered',
      lines: [
        OrderLine(
          productId: 'p1',
          name: 'Shirt',
          quantity: 3,
          unit: 'PIECE',
          amount: 150,
        ),
      ],
      payments: [
        OrderPayment(
          id: 'pay-2',
          amount: 150,
          date: '2026-09-10',
          method: 'Cash',
        ),
      ], // balanceDue = 0
    );

    setUp(() {
      mockRepo = MockOrdersRepository();
      ordersBloc = OrdersBloc(ordersRepository: mockRepo);
    });

    tearDown(() {
      ordersBloc.close();
    });

    test('To collect filter only returns orders with balance due > 0', () {
      final state = OrdersState(
        allOrders: [order1, order2, order3],
        activeFilter: 'To collect',
      );

      final results = state.filteredOrders;
      expect(results.length, equals(1));
      expect(results.first.id, equals('EL-101'));
      expect(results.first.balanceDue, equals(100));
    });

    test('Filter by status returns matching status orders', () {
      final stateReady = OrdersState(
        allOrders: [order1, order2, order3],
        activeFilter: 'Ready',
      );
      expect(stateReady.filteredOrders.length, equals(1));
      expect(stateReady.filteredOrders.first.id, equals('EL-102'));

      final stateDelivered = OrdersState(
        allOrders: [order1, order2, order3],
        activeFilter: 'Delivered',
      );
      expect(stateDelivered.filteredOrders.length, equals(1));
      expect(stateDelivered.filteredOrders.first.id, equals('EL-103'));
    });

    test('Search query matches order code, name, or phone', () {
      final state = OrdersState(
        allOrders: [order1, order2, order3],
        activeFilter: 'All',
        searchQuery: 'priya',
      );

      expect(state.filteredOrders.length, equals(1));
      expect(state.filteredOrders.first.name, equals('Priya Sharma'));

      final stateByCode = OrdersState(
        allOrders: [order1, order2, order3],
        activeFilter: 'All',
        searchQuery: 'EL-103',
      );
      expect(stateByCode.filteredOrders.length, equals(1));
      expect(stateByCode.filteredOrders.first.id, equals('EL-103'));
    });

    test('Prepaid delivery check: Option B eligible for handover dialog', () {
      expect(order2.isReady, isTrue);
      expect(order2.isPaidInFull, isTrue);
      expect(order2.balanceDue, equals(0));
    });

    test('RecordPaymentEvent calls repository, updates order, and preserves status', () async {
      ordersBloc.add(
        RecordPaymentEvent(
          orderCode: 'EL-101',
          amount: 5000,
          method: 'UPI',
        ),
      );

      final state = await ordersBloc.stream.firstWhere(
        (s) => s.actionSuccessMessage != null,
      );

      expect(mockRepo.recordedOrderCode, equals('EL-101'));
      expect(mockRepo.recordedAmount, equals(5000));
      expect(mockRepo.recordedMethod, equals('UPI'));
      expect(state.actionSuccessMessage, equals('Payment recorded'));
      expect(state.selectedOrder?.id, equals('EL-101'));
      expect(state.selectedOrder?.status, equals('Pending'));
      expect(state.isCollectingPayment, isFalse);
    });
  });
}
