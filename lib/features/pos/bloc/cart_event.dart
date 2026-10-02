import '../data/models/product_model.dart';

abstract class CartEvent {}

class LoadCatalogEvent extends CartEvent {}

class RefreshCatalogEvent extends CartEvent {}

class CategoryFilterChangedEvent extends CartEvent {
  final String category; // 'all' | 'wash' | 'dryclean' | 'iron'

  CategoryFilterChangedEvent(this.category);
}

class SearchQueryChangedEvent extends CartEvent {
  final String query;

  SearchQueryChangedEvent(this.query);
}

class AddItemToCartEvent extends CartEvent {
  final Product product;
  final double quantity;

  AddItemToCartEvent({required this.product, required this.quantity});
}

class UpdateItemQuantityEvent extends CartEvent {
  final String productId;
  final double quantity;

  UpdateItemQuantityEvent({required this.productId, required this.quantity});
}

class RemoveItemFromCartEvent extends CartEvent {
  final String productId;

  RemoveItemFromCartEvent(this.productId);
}

class ClearCartEvent extends CartEvent {}

class SetCustomerDetailsEvent extends CartEvent {
  final String phone;
  final String customerName;
  final DateTime dueDate;
  final String notes;

  SetCustomerDetailsEvent({
    required this.phone,
    required this.customerName,
    required this.dueDate,
    required this.notes,
  });
}

class SubmitOrderEvent extends CartEvent {
  final String
  paymentChoice; // 'prepaid' (needs paymentMethodName) | 'delivery'
  final String? paymentMethodName;

  /// Paise received at creation for a prepaid order; null means the full total.
  final int? receivedNow;
  final DateTime? dueDate;
  final String? notes;

  SubmitOrderEvent({
    required this.paymentChoice,
    this.paymentMethodName,
    this.receivedNow,
    this.dueDate,
    this.notes,
  });
}

class UpdateOrderDetailsEvent extends CartEvent {
  final DateTime? dueDate;
  final String? notes;

  UpdateOrderDetailsEvent({this.dueDate, this.notes});
}

class ResetSaleEvent extends CartEvent {
  final String? outletId;

  ResetSaleEvent({this.outletId});
}
