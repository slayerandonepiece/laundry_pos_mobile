import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';

class MockOrdersRepository implements OrdersRepository {
  Order? updatedOrder;
  Order? orderToReturnOnRecordPayment;
  String? recordedOrderCode;
  int? recordedAmount;
  String? recordedMethod;
  String? invoiceRequestedOrderCode;

  @override
  Future<Order> recordPayment(
    String orderCode,
    int amount,
    String method,
  ) async {
    recordedOrderCode = orderCode;
    recordedAmount = amount;
    recordedMethod = method;
    if (orderToReturnOnRecordPayment != null) {
      return orderToReturnOnRecordPayment!;
    }
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
  Future<InvoiceInfo> getOrCreateInvoice(String orderCode) async {
    invoiceRequestedOrderCode = orderCode;
    return InvoiceInfo(
      exists: true,
      invoiceSeq: 101,
      accessToken: 'token-abc',
      generatedAt: DateTime.now(),
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

    test('To collect includes a delivered order that still owes money', () {
      final deliveredUnpaid = Order(
        id: 'EL-104',
        name: 'Late Payer',
        phone: '9000000000',
        date: '2026-09-08',
        due: '2026-09-10',
        status: 'Delivered',
        lines: [
          OrderLine(
            productId: 'p1',
            name: 'Shirt',
            quantity: 1,
            unit: 'PIECE',
            amount: 500,
          ),
        ],
        payments: [],
      );
      final state = OrdersState(
        allOrders: [order1, order2, order3, deliveredUnpaid],
        activeFilter: 'To collect',
      );
      expect(state.filteredOrders.map((o) => o.id), ['EL-101', 'EL-104']);
      expect(state.countFor('to_collect'), 2);
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

    group('Employee register filters (O1)', () {
      String day(int offset) {
        final d = DateTime.now().add(Duration(days: offset));
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      Order make(
        String id, {
        required String status,
        required int dueOffset,
        required int total,
        required int paid,
      }) => Order(
        id: id,
        name: 'Customer $id',
        phone: '9000000000',
        date: day(-3),
        due: day(dueOffset),
        status: status,
        lines: [
          OrderLine(
            productId: 'p',
            name: 'Item',
            quantity: 1,
            unit: 'PIECE',
            amount: total,
          ),
        ],
        payments: paid > 0
            ? [
                OrderPayment(
                  id: 'pay-$id',
                  amount: paid,
                  date: day(-2),
                  method: 'Cash',
                ),
              ]
            : [],
      );

      // A: unpaid, due today, pending   B: part-paid, late, in progress
      // C: paid, due tomorrow, ready    D: paid, due today, delivered
      final a = make('A', status: 'Pending', dueOffset: 0, total: 100, paid: 0);
      final b = make(
        'B',
        status: 'In Progress',
        dueOffset: -2,
        total: 100,
        paid: 40,
      );
      final c = make('C', status: 'Ready', dueOffset: 1, total: 100, paid: 100);
      final d = make(
        'D',
        status: 'Delivered',
        dueOffset: 0,
        total: 100,
        paid: 100,
      );
      List<String> ids(OrdersState s) =>
          s.filteredOrders.map((o) => o.id).toList();

      test('payment status narrows to paid, unpaid or part-paid', () {
        final all = [a, b, c, d];
        expect(ids(OrdersState(allOrders: all, paymentFilter: 'paid')), [
          'C',
          'D',
        ]);
        expect(ids(OrdersState(allOrders: all, paymentFilter: 'unpaid')), [
          'A',
        ]);
        expect(ids(OrdersState(allOrders: all, paymentFilter: 'partial')), [
          'B',
        ]);
      });

      test('due today and late only ever include undelivered orders', () {
        final all = [a, b, c, d];
        expect(ids(OrdersState(allOrders: all, dueFilter: 'due_today')), ['A']);
        expect(ids(OrdersState(allOrders: all, dueFilter: 'late')), ['B']);
      });

      test('work status, payment and due date combine', () {
        final all = [a, b, c, d];
        final state = OrdersState(
          allOrders: all,
          activeFilter: 'Pending',
          paymentFilter: 'unpaid',
          dueFilter: 'due_today',
        );
        expect(ids(state), ['A']);
        expect(
          ids(
            OrdersState(
              allOrders: all,
              activeFilter: 'Pending',
              paymentFilter: 'paid',
            ),
          ),
          isEmpty,
        );
      });

      test('chip counts agree with what the chip would show under the other filters', () {
        final state = OrdersState(
          allOrders: [a, b, c, d],
          paymentFilter: 'paid',
        );
        // Only C and D are paid: All 2, Ready 1, Delivered 1, Pending 0.
        expect(state.countFor('all'), 2);
        expect(state.countFor('ready'), 1);
        expect(state.countFor('delivered'), 1);
        expect(state.countFor('pending'), 0);
        // And a chip's count equals the rows it then shows.
        final ready = state.copyWith(activeFilter: 'ready');
        expect(ready.filteredOrders.length, state.countFor('ready'));
      });

      test('search also feeds the chip counts', () {
        final state = OrdersState(
          allOrders: [a, b, c, d],
          searchQuery: 'Customer B',
        );
        expect(state.countFor('all'), 1);
        expect(state.countFor('in_progress'), 1);
        expect(state.countFor('pending'), 0);
      });

      test('hasActiveFilters is false only for the plain list', () {
        expect(OrdersState().hasActiveFilters, isFalse);
        expect(OrdersState(searchQuery: 'x').hasActiveFilters, isTrue);
        expect(OrdersState(activeFilter: 'Ready').hasActiveFilters, isTrue);
        expect(OrdersState(paymentFilter: 'paid').hasActiveFilters, isTrue);
        expect(OrdersState(dueFilter: 'late').hasActiveFilters, isTrue);
      });

      test(
        'the events set each filter and one event clears them all',
        () async {
          ordersBloc.add(SearchOrdersEvent('abc'));
          ordersBloc.add(FilterOrdersEvent('Ready'));
          ordersBloc.add(PaymentFilterEvent('paid'));
          ordersBloc.add(DueFilterEvent('late'));
          await Future<void>.delayed(Duration.zero);
          expect(ordersBloc.state.paymentFilter, 'paid');
          expect(ordersBloc.state.dueFilter, 'late');
          expect(ordersBloc.state.hasActiveFilters, isTrue);

          ordersBloc.add(ClearOrderFiltersEvent());
          await Future<void>.delayed(Duration.zero);
          expect(ordersBloc.state.hasActiveFilters, isFalse);
          expect(ordersBloc.state.searchQuery, '');
          expect(ordersBloc.state.activeFilter, 'all');
        },
      );
    });

    test('Prepaid delivery check: Option B eligible for handover dialog', () {
      expect(order2.isReady, isTrue);
      expect(order2.isPaidInFull, isTrue);
      expect(order2.balanceDue, equals(0));
    });

    test('RecordPaymentEvent calls repository, updates order, and preserves status', () async {
      ordersBloc.add(
        RecordPaymentEvent(orderCode: 'EL-101', amount: 5000, method: 'UPI'),
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

    test('RecordPaymentEvent on delivered order when fully paid triggers getOrCreateInvoice', () async {
      final deliveredOrder = Order(
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
            quantity: 1,
            unit: 'PIECE',
            amount: 100,
          ),
        ],
        payments: [
          OrderPayment(
            id: 'pay-new',
            amount: 100,
            date: '2026-09-10',
            method: 'Cash',
          ),
        ],
      );
      mockRepo.orderToReturnOnRecordPayment = deliveredOrder;

      ordersBloc.add(
        RecordPaymentEvent(orderCode: 'EL-103', amount: 100, method: 'Cash'),
      );

      final state = await ordersBloc.stream.firstWhere(
        (s) => s.actionSuccessMessage != null,
      );

      expect(state.selectedOrder?.isDelivered, isTrue);
      expect(state.selectedOrder?.isPaidInFull, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockRepo.invoiceRequestedOrderCode, equals('EL-103'));
    });
  });
}
