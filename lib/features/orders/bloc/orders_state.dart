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

  /// 'all' | 'paid' | 'unpaid' | 'partial'
  final String paymentFilter;

  /// 'any' | 'due_today' | 'late' — the delivery date scope.
  final String dueFilter;
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
    this.paymentFilter = 'all',
    this.dueFilter = 'any',
    this.selectedOrder,
    this.isUpdatingStatus = false,
    this.isCollectingPayment = false,
    this.actionSuccessMessage,
    this.loadFailed = false,
  });

  /// True when anything narrows the list beyond showing every order.
  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      activeFilter.toLowerCase().replaceAll(' ', '_') != 'all' ||
      paymentFilter != 'all' ||
      dueFilter != 'any';

  static String _chipKey(String chip) =>
      chip.toLowerCase().replaceAll(' ', '_');

  /// Search, payment status and due date — everything except the status chip.
  bool _matchesOtherFilters(Order order) {
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase().trim();
      final matchesId = order.displayCode.toLowerCase().contains(query);
      final matchesName = order.name.toLowerCase().contains(query);
      final matchesPhone = order.phone.contains(query);
      if (!matchesId && !matchesName && !matchesPhone) return false;
    }

    switch (paymentFilter) {
      case 'paid':
        if (order.balanceDue > 0) return false;
      case 'unpaid':
        if (order.paidAmount != 0 || order.totalAmount <= 0) return false;
      case 'partial':
        if (order.paidAmount <= 0 || order.balanceDue <= 0) return false;
    }

    if (dueFilter != 'any') {
      // Due today / late only make sense for orders still to be delivered.
      if (order.isDelivered) return false;
      // No usable due date: can be neither "due today" nor "late".
      if (!order.hasValidDueDate) return false;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final due = order.dueDateTime;
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueFilter == 'due_today' && !dueDay.isAtSameMomentAs(today)) {
        return false;
      }
      if (dueFilter == 'late' && !dueDay.isBefore(today)) return false;
    }
    return true;
  }

  bool _matchesChip(Order order, String chip) {
    switch (_chipKey(chip)) {
      case 'to_collect':
        // Any order with money still due — including a delivered one, which
        // can be paid after handover — matching the owner's "To collect".
        return order.balanceDue > 0;
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
  }

  List<Order> get filteredOrders => allOrders
      .where(
        (order) =>
            _matchesOtherFilters(order) && _matchesChip(order, activeFilter),
      )
      .toList();

  /// How many orders the chip [chip] would show right now, given the search,
  /// payment and due filters — so a chip's number always agrees with its list.
  int countFor(String chip) => allOrders
      .where(
        (order) => _matchesOtherFilters(order) && _matchesChip(order, chip),
      )
      .length;

  OrdersState copyWith({
    bool? isLoading,
    String? error,
    List<Order>? allOrders,
    String? activeFilter,
    String? searchQuery,
    String? paymentFilter,
    String? dueFilter,
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
      paymentFilter: paymentFilter ?? this.paymentFilter,
      dueFilter: dueFilter ?? this.dueFilter,
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
