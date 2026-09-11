import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/sync/sync_engine.dart';
import '../data/orders_repository.dart';
import 'orders_event.dart';
import 'orders_state.dart';

class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final OrdersRepository ordersRepository;

  OrdersBloc({required this.ordersRepository}) : super(OrdersState()) {
    on<LoadOrdersEvent>(_onLoadOrders);
    on<RefreshOrdersEvent>(_onRefreshOrders);
    on<FilterOrdersEvent>(_onFilterOrders);
    on<SearchOrdersEvent>(_onSearchOrders);
    on<LoadOrderDetailEvent>(_onLoadOrderDetail);
    on<UpdateOrderStatusEvent>(_onUpdateOrderStatus);
    on<CollectPaymentEvent>(_onCollectPayment);
    on<HandoverOrderEvent>(_onHandoverOrder);
    on<RefreshInvoiceEvent>(_onRefreshInvoice);
  }

  /// Cold open (navigating to the Orders tab): read local cache only, no
  /// network call. If the cache is completely empty (first-ever launch,
  /// nothing to show yet) fall back to a one-time sync so the screen isn't
  /// just permanently blank until the user thinks to pull-to-refresh.
  Future<void> _onLoadOrders(
    LoadOrdersEvent event,
    Emitter<OrdersState> emit,
  ) async {
    final cachedOrders = ordersRepository.getCachedOrdersList();
    if (cachedOrders.isNotEmpty) {
      emit(state.copyWith(allOrders: cachedOrders, error: null));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    await SyncEngine.instance.trigger();
    emit(
      state.copyWith(
        isLoading: false,
        allOrders: ordersRepository.getCachedOrdersList(),
      ),
    );
  }

  /// Pull-to-refresh / manual "Sync now": the only path that touches the
  /// network from this screen. Uses retryNow() rather than trigger() —
  /// this is always a deliberate user action, so it should always get a
  /// fresh attempt rather than being silently ignored because an earlier,
  /// unrelated run of bad luck already used up the failure streak.
  Future<void> _onRefreshOrders(
    RefreshOrdersEvent event,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    await SyncEngine.instance.retryNow();
    emit(
      state.copyWith(
        isLoading: false,
        allOrders: ordersRepository.getCachedOrdersList(),
      ),
    );
  }

  void _onFilterOrders(FilterOrdersEvent event, Emitter<OrdersState> emit) {
    emit(state.copyWith(activeFilter: event.filter));
  }

  void _onSearchOrders(SearchOrdersEvent event, Emitter<OrdersState> emit) {
    emit(state.copyWith(searchQuery: event.query));
  }

  Future<void> _onLoadOrderDetail(
    LoadOrderDetailEvent event,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final order = await ordersRepository.getOrderDetail(event.orderCode);
      emit(state.copyWith(isLoading: false, selectedOrder: order));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onUpdateOrderStatus(
    UpdateOrderStatusEvent event,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isUpdatingStatus: true, error: null));
    try {
      // Local-first: this returns instantly, already reflecting the change.
      final updated = await ordersRepository.updateStatus(
        event.orderCode,
        event.nextStatus,
      );
      final updatedList = state.allOrders
          .map((o) => o.id == updated.id ? updated : o)
          .toList();

      emit(
        state.copyWith(
          isUpdatingStatus: false,
          selectedOrder: updated,
          allOrders: updatedList,
          actionSuccessMessage: 'Status updated to ${event.nextStatus}',
        ),
      );

      // Fire-and-forget — UI has already moved on.
      SyncEngine.instance.trigger();
    } catch (e) {
      emit(state.copyWith(isUpdatingStatus: false, error: e.toString()));
    }
  }

  Future<void> _onCollectPayment(
    CollectPaymentEvent event,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isCollectingPayment: true, error: null));
    try {
      // 1 & 2: local-first, both return instantly.
      await ordersRepository.recordPayment(
        event.orderCode,
        event.amount,
        event.method,
      );
      final updated = await ordersRepository.updateStatus(
        event.orderCode,
        'Delivered',
      );

      final updatedList = state.allOrders
          .map((o) => o.id == updated.id ? updated : o)
          .toList();

      // Local-first writes (1 & 2) are done — emit success and let the
      // dialog close immediately, regardless of connectivity. Nothing past
      // this point may block the emit above.
      emit(
        state.copyWith(
          isCollectingPayment: false,
          selectedOrder: updated,
          allOrders: updatedList,
          actionSuccessMessage: 'Payment collected & order marked delivered',
        ),
      );

      // 3: invoice generation genuinely needs the server (invoice numbers
      // are server-assigned) — it can't be made local-first. Fire-and-forget
      // (never awaited) so a slow or offline server can't hold up the
      // dialog-close path above. If it fails, that's fine: the payment and
      // status are already saved locally, and invoice generation is retried
      // the next time this order's detail screen is opened.
      () async {
        try {
          await ordersRepository.getOrCreateInvoice(event.orderCode);
          // getOrCreateInvoice() already merged the invoice into the cache
          // (see OrdersRepository), but this handler has already emitted
          // and returned — re-dispatch as a fresh event so the invoice
          // number shows up on screen now instead of only next reopen.
          if (!isClosed) add(RefreshInvoiceEvent(event.orderCode));
        } catch (_) {
          // Ignored — invoice generation retried the next time this
          // order's detail screen is opened.
        }
      }();

      SyncEngine.instance.trigger();
    } catch (e) {
      emit(state.copyWith(isCollectingPayment: false, error: e.toString()));
    }
  }

  Future<void> _onHandoverOrder(
    HandoverOrderEvent event,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isUpdatingStatus: true, error: null));
    try {
      final updated = await ordersRepository.updateStatus(
        event.orderCode,
        'Delivered',
      );

      final updatedList = state.allOrders
          .map((o) => o.id == updated.id ? updated : o)
          .toList();

      // Local-first write is done — emit success and let the dialog close
      // immediately, regardless of connectivity. Nothing past this point
      // may block the emit above.
      emit(
        state.copyWith(
          isUpdatingStatus: false,
          selectedOrder: updated,
          allOrders: updatedList,
          actionSuccessMessage: 'Order marked delivered',
        ),
      );

      // Invoice generation genuinely needs the server (invoice numbers are
      // server-assigned) — it can't be made local-first. Fire-and-forget
      // (never awaited) so a slow or offline server can't hold up the
      // dialog-close path above. If it fails, the status/payment are
      // already saved locally, and invoice generation is retried the next
      // time this order's detail screen is opened.
      () async {
        try {
          await ordersRepository.getOrCreateInvoice(event.orderCode);
          // getOrCreateInvoice() already merged the invoice into the cache
          // (see OrdersRepository), but this handler has already emitted
          // and returned — re-dispatch as a fresh event so the invoice
          // number shows up on screen now instead of only next reopen.
          if (!isClosed) add(RefreshInvoiceEvent(event.orderCode));
        } catch (_) {
          // Ignored — invoice generation retried the next time this
          // order's detail screen is opened.
        }
      }();

      SyncEngine.instance.trigger();
    } catch (e) {
      emit(state.copyWith(isUpdatingStatus: false, error: e.toString()));
    }
  }

  Future<void> _onRefreshInvoice(
    RefreshInvoiceEvent event,
    Emitter<OrdersState> emit,
  ) async {
    try {
      await ordersRepository.getOrCreateInvoice(event.orderCode);
      final refreshed = await ordersRepository.getOrderDetail(event.orderCode);
      final updatedList = state.allOrders
          .map((o) => o.id == refreshed.id ? refreshed : o)
          .toList();
      emit(state.copyWith(selectedOrder: refreshed, allOrders: updatedList));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
