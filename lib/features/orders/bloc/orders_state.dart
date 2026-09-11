import '../data/models/order_model.dart';

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
  });

  List<Order> get filteredOrders {
    return allOrders.where((order) {
      // 1. Search Query filter (matches order ID, customer name, customer phone)
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase().trim();
        final matchesId = order.id.toLowerCase().contains(query);
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
    );
  }
}
