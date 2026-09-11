abstract class OrdersEvent {}

class LoadOrdersEvent extends OrdersEvent {}

/// Pull-to-refresh (or a manual "Sync now" tap) — the only thing allowed to
/// trigger a network sync from the Orders screen. LoadOrdersEvent never
/// touches the network; this is what does.
class RefreshOrdersEvent extends OrdersEvent {}

class FilterOrdersEvent extends OrdersEvent {
  final String filter; // 'To collect' | 'All' | 'Pending' | 'In progress' | 'Ready' | 'Delivered'

  FilterOrdersEvent(this.filter);
}

class SearchOrdersEvent extends OrdersEvent {
  final String query;

  SearchOrdersEvent(this.query);
}

class LoadOrderDetailEvent extends OrdersEvent {
  final String orderCode;

  LoadOrderDetailEvent(this.orderCode);
}

class UpdateOrderStatusEvent extends OrdersEvent {
  final String orderCode;
  final String nextStatus;

  UpdateOrderStatusEvent({required this.orderCode, required this.nextStatus});
}

class CollectPaymentEvent extends OrdersEvent {
  final String orderCode;
  final int amount;
  final String method;

  CollectPaymentEvent({
    required this.orderCode,
    required this.amount,
    required this.method,
  });
}

class HandoverOrderEvent extends OrdersEvent {
  final String orderCode;

  HandoverOrderEvent(this.orderCode);
}

class RefreshInvoiceEvent extends OrdersEvent {
  final String orderCode;

  RefreshInvoiceEvent(this.orderCode);
}
