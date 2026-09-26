import '../data/models/order_model.dart';

/// Deliberately has no `==`/`hashCode` override (no Equatable, no manual
/// implementation). `error` and `actionSuccessMessage` are one-shot signals,
/// not durable state — Bloc's `emit()` skips a new state that `==` an
/// existing one, so if two of the same error/message in a row are ever
/// possible, adding equality here would silently drop the second emission
/// and the listener that's supposed to react to it (e.g. a dialog closing,
/// a SnackBar showing) would never fire. Don't add Equatable/copyWith-based
/// equality to this class without first ensuring one-shot fields are always
/// cleared after being consumed.
class OrdersState {
  final bool isLoading;
  final String? error;
  final List<Order> allOrders;
  final String activeFilter; // 'To collect' | 'All' | 'Pending' | 'In progress' | 'Ready' | 'Delivered'
  final String searchQuery;
  final Order? selectedOrder;
  final bool isUpdatingStatus;
  final bool isCollectingPayment;
  final String? actionSuccessMessage;
  final bool loadFailed;

  OrdersState({
    this.isLoading = false,
    this.error,
    this.allOrders = const [],
    this.activeFilter = 'all',
    this.searchQuery = '',
    this.selectedOrder,
    this.isUpdatingStatus = false,
    this.isCollectingPayment = false,
    this.actionSuccessMessage,
    this.loadFailed = false,
  });

  List<Order> get filteredOrders {
    return allOrders.where((order) {
      // 1. Search Query filter (matches order ID, customer name, customer phone)
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase().trim();
        final matchesId = order.displayCode.toLowerCase().contains(query);
        final matchesName = order.name.toLowerCase().contains(query);
        final matchesPhone = order.phone.contains(query);
        if (!matchesId && !matchesName && !matchesPhone) {
          return false;
        }
      }

      // 2. Status/To collect filter
      switch (activeFilter.toLowerCase().replaceAll(' ', '_')) {
        case 'to_collect':
          // Keep in sync with toCollectCount in orders_list_screen.dart —
          // that count excludes delivered orders, so the filter must too or
          // tapping the chip shows more orders than its own label says.
          return order.balanceDue > 0 && !order.isDelivered;
        case 'pending':
          return order.isPending;
        case 'in_progress':
          return order.isInProgress;
        case 'ready':
          return order.isReady;
        case 'delivered':
          return order.isDelivered;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  OrdersState copyWith({
    bool? isLoading,
    String? error,
    List<Order>? allOrders,
    String? activeFilter,
    String? searchQuery,
    Order? selectedOrder,
    bool? isUpdatingStatus,
    bool? isCollectingPayment,
    String? actionSuccessMessage,
    bool? loadFailed,
    bool clearSelectedOrder = false,
  }) {
    return OrdersState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      allOrders: allOrders ?? this.allOrders,
      activeFilter: activeFilter ?? this.activeFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedOrder: clearSelectedOrder
          ? null
          : (selectedOrder ?? this.selectedOrder),
      isUpdatingStatus: isUpdatingStatus ?? this.isUpdatingStatus,
      isCollectingPayment: isCollectingPayment ?? this.isCollectingPayment,
      actionSuccessMessage: actionSuccessMessage,
      loadFailed: loadFailed ?? this.loadFailed,
    );
  }
}
