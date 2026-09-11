import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/utils/date_formatter.dart';
import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/features/pos/data/pos_repository.dart';

import 'cart_event.dart';
import 'cart_state.dart';

class CartBloc extends Bloc<CartEvent, CartState> {
  final PosRepository posRepository;

  CartBloc({required this.posRepository}) : super(CartState()) {
    on<LoadCatalogEvent>(_onLoadCatalog);
    on<RefreshCatalogEvent>(_onRefreshCatalog);
    on<CategoryFilterChangedEvent>(_onCategoryFilterChanged);
    on<SearchQueryChangedEvent>(_onSearchQueryChanged);
    on<AddItemToCartEvent>(_onAddItemToCart);
    on<UpdateItemQuantityEvent>(_onUpdateItemQuantity);
    on<RemoveItemFromCartEvent>(_onRemoveItemFromCart);
    on<ClearCartEvent>(_onClearCart);
    on<SetCustomerDetailsEvent>(_onSetCustomerDetails);
    on<SubmitOrderEvent>(_onSubmitOrder);
    on<ResetSaleEvent>(_onResetSale);
  }

  /// Cold open: read local cache only, no network call.
  /// If the cache is completely empty (first-ever launch, nothing cached yet),
  /// fall back to a one-time network fetch so the screen isn't blank.
  Future<void> _onLoadCatalog(
    LoadCatalogEvent event,
    Emitter<CartState> emit,
  ) async {
    final cachedProducts = posRepository.getCachedProductsList();
    if (cachedProducts.isNotEmpty) {
      emit(state.copyWith(allProducts: cachedProducts, error: null));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      final products = await posRepository.listProducts();
      emit(state.copyWith(isLoading: false, allProducts: products));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  /// Manual reload / "Sync now": fetches catalog from network and updates cache.
  Future<void> _onRefreshCatalog(
    RefreshCatalogEvent event,
    Emitter<CartState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final products = await posRepository.listProducts();
      emit(state.copyWith(isLoading: false, allProducts: products));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onCategoryFilterChanged(
    CategoryFilterChangedEvent event,
    Emitter<CartState> emit,
  ) {
    emit(state.copyWith(selectedCategory: event.category));
  }

  void _onSearchQueryChanged(
    SearchQueryChangedEvent event,
    Emitter<CartState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onAddItemToCart(AddItemToCartEvent event, Emitter<CartState> emit) {
    final updated = Map<String, CartItem>.from(state.items);
    final existing = updated[event.product.id];

    if (existing != null) {
      // If already in cart, increment quantity
      updated[event.product.id] = existing.copyWith(
        quantity: existing.quantity + event.quantity,
      );
    } else {
      updated[event.product.id] = CartItem(
        product: event.product,
        quantity: event.quantity,
      );
    }
    emit(state.copyWith(items: updated));
  }

  void _onUpdateItemQuantity(
    UpdateItemQuantityEvent event,
    Emitter<CartState> emit,
  ) {
    final updated = Map<String, CartItem>.from(state.items);
    final existing = updated[event.productId];
    if (existing != null) {
      if (event.quantity <= 0) {
        updated.remove(event.productId);
      } else {
        updated[event.productId] = existing.copyWith(quantity: event.quantity);
      }
      emit(state.copyWith(items: updated));
    }
  }

  void _onRemoveItemFromCart(
    RemoveItemFromCartEvent event,
    Emitter<CartState> emit,
  ) {
    final updated = Map<String, CartItem>.from(state.items);
    updated.remove(event.productId);
    emit(state.copyWith(items: updated));
  }

  void _onClearCart(ClearCartEvent event, Emitter<CartState> emit) {
    emit(state.copyWith(items: const {}));
  }

  void _onSetCustomerDetails(
    SetCustomerDetailsEvent event,
    Emitter<CartState> emit,
  ) {
    emit(
      state.copyWith(
        customerPhone: event.phone,
        customerName: event.customerName,
        dueDate: event.dueDate,
        notes: event.notes,
      ),
    );
  }

  Future<void> _onSubmitOrder(
    SubmitOrderEvent event,
    Emitter<CartState> emit,
  ) async {
    if (state.items.isEmpty) return;

    emit(state.copyWith(isSubmitting: true, submissionError: null));

    try {
      final entries = state.items.values.map((item) {
        return {
          'productId': item.product.id,
          'quantity': item.product.isWeight
              ? item.quantity
              : item.quantity.toInt(),
        };
      }).toList();

      Map<String, dynamic>? initialPayment;
      if (event.paymentChoice != 'delivery') {
        final methodName =
            event.paymentMethodName ??
            (event.paymentChoice == 'upi' ? 'UPI' : 'Cash');
        initialPayment = {'amount': state.totalAmount, 'method': methodName};
      }

      // Optimistic: saves locally & returns immediately; API fires in background
      final order = await posRepository.createOrderOptimistic(
        idempotencyKey: state.idempotencyKey,
        phone: state.customerPhone,
        customerName: state.customerName,
        dueDate: DateFormatter.toIsoDateString(state.dueDate),
        notes: state.notes,
        entries: entries,
        initialPayment: initialPayment,
      );

      emit(state.copyWith(isSubmitting: false, placedOrder: order));
    } catch (e) {
      // NOTE: Preserves existing idempotencyKey so subsequent retries send the exact same key!
      emit(state.copyWith(isSubmitting: false, submissionError: e.toString()));
    }
  }

  void _onResetSale(ResetSaleEvent event, Emitter<CartState> emit) {
    emit(
      state.copyWith(
        items: const {},
        customerPhone: '',
        customerName: '',
        notes: '',
        dueDate: DateTime.now().add(const Duration(days: 2)),
        idempotencyKey: IdempotencyKeyGenerator.generate(),
        clearPlacedOrder: true,
        submissionError: null,
      ),
    );
  }
}
