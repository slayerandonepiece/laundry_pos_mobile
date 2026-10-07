class StorePaymentMethod {
  final String id;
  final String code;
  final String name;
  final String type;
  final bool active;

  /// PRE_ORDER, POST_ORDER or BOTH. Old cached rows have none; BOTH keeps them
  /// working until the next refresh brings the real stage.
  final String stage;

  StorePaymentMethod({
    required this.id,
    this.code = '',
    required this.name,
    String? type,
    this.active = true,
    this.stage = 'BOTH',
  }) : type = type ?? (code.isNotEmpty ? code : '');

  factory StorePaymentMethod.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    return StorePaymentMethod(
      id: json['id']?.toString() ?? '',
      code: code,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? (code.isNotEmpty ? code : ''),
      active: (json['active'] ?? json['enabled']) != false,
      stage: _parseStage(json['stage']),
    );
  }

  static String _parseStage(Object? raw) {
    final value = raw?.toString().toUpperCase();
    return value == 'PRE_ORDER' || value == 'POST_ORDER' ? value! : 'BOTH';
  }

  /// On the new-order screen: the customer pays up front or on delivery.
  bool get offeredWhenPlacingOrder => stage == 'PRE_ORDER' || stage == 'BOTH';

  /// Recording a payment on an existing order, or collecting at delivery.
  /// Cash on delivery is a promise to pay, never money received, so it is
  /// excluded even if an old row says BOTH (the server rejects it too).
  bool get offeredAfterOrder =>
      !isCashOnDelivery && (stage == 'POST_ORDER' || stage == 'BOTH');

  bool get isCashOnDelivery {
    final value = (code.trim().isNotEmpty ? code : name)
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return value == 'COD' || value == 'CASHONDELIVERY';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type,
      'active': active,
      'stage': stage,
    };
  }
}
