import 'package:myshop/core/utils/idempotency.dart';
import 'package:myshop/core/utils/quantity_formatter.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/owner/data/models/payment_method_model.dart';
import 'package:myshop/features/pos/data/models/product_model.dart';

class CartItem {
  final Product product;
  final double quantity;

  CartItem({required this.product, required this.quantity});

  int get computedAmount => product.computePrice(quantity);

  String get displayQuantity {
    if (product.isWeight) {
      return QuantityFormatter.formatWeight(quantity);
    }
    return '${quantity.toInt()} pcs';
  }

  CartItem copyWith({Product? product, double? quantity}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartState {
  final bool isLoading;
  final String? error;
  final List<Product> allProducts;
  final String selectedCategory; // 'all' | 'wash' | 'dry clean' | 'iron'
  final String searchQuery;
  final Map<String, CartItem> items; // keyed by productId
  final List<StorePaymentMethod> paymentMethods;
  final String? outletId;

  // Customer Step
  final String customerPhone;
  final String customerName;
  final DateTime dueDate;
  final String notes;

  // Checkout and submission
  final String idempotencyKey;
  final bool isSubmitting;
  final Order? placedOrder;
  final String? submissionError;

  CartState({
    this.isLoading = false,
    this.error,
    this.allProducts = const [],
    this.selectedCategory = 'all',
    this.searchQuery = '',
    this.items = const {},
    this.paymentMethods = const [],
    this.outletId,
    this.customerPhone = '',
    this.customerName = '',
    DateTime? dueDate,
    this.notes = '',
    String? idempotencyKey,
    this.isSubmitting = false,
    this.placedOrder,
    this.submissionError,
  }) : dueDate = dueDate ?? DateTime.now().add(const Duration(days: 2)),
       idempotencyKey = idempotencyKey ?? IdempotencyKeyGenerator.generate();

  int get totalAmount =>
      items.values.fold(0, (sum, item) => sum + item.computedAmount);
  int get totalItemCount => items.length;
  bool get hasItems => items.isNotEmpty;

  List<Product> get filteredProducts {
    return allProducts.where((product) {
      if (!product.active) return false;
      final matchesCategory =
          selectedCategory == 'all' ||
          product.category.toLowerCase().trim() ==
              selectedCategory.toLowerCase().trim();
      final matchesSearch =
          searchQuery.isEmpty ||
          product.name.toLowerCase().contains(searchQuery.toLowerCase().trim());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  CartState copyWith({
    bool? isLoading,
    String? error,
    List<Product>? allProducts,
    String? selectedCategory,
    String? searchQuery,
    Map<String, CartItem>? items,
    List<StorePaymentMethod>? paymentMethods,
    String? outletId,
    bool clearOutlet = false,
    String? customerPhone,
    String? customerName,
    DateTime? dueDate,
    String? notes,
    String? idempotencyKey,
    bool? isSubmitting,
    Order? placedOrder,
    String? submissionError,
    bool clearPlacedOrder = false,
  }) {
    return CartState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      allProducts: allProducts ?? this.allProducts,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      items: items ?? this.items,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      outletId: clearOutlet ? null : (outletId ?? this.outletId),
      customerPhone: customerPhone ?? this.customerPhone,
      customerName: customerName ?? this.customerName,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      placedOrder: clearPlacedOrder ? null : (placedOrder ?? this.placedOrder),
      submissionError: submissionError,
    );
  }
}
